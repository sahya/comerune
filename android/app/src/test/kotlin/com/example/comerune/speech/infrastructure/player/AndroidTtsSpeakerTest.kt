package com.example.comerune.speech.infrastructure.player

import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.os.Build
import com.example.comerune.speech.domain.player.AudioFocusGuard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [AndroidTtsSpeaker] that exercise the init/release state
 * machine through the [TextToSpeechFactory] seam.  These run on the pure
 * JVM unit-test class path — no Robolectric, no instrumented device — so
 * behavior that depends on the Android [android.speech.tts.TextToSpeech]
 * engine is replaced with [FakeTextToSpeechFactory].
 *
 * Tests poll [FakeTextToSpeechFactory.hasPendingInit] with a bounded wait
 * (see [awaitPendingInit]) instead of relying on a single `yield()`, so
 * they stay deterministic whether the init bootstrap runs on the test
 * dispatcher or on a separate dispatcher (e.g. `Dispatchers.IO`, once the
 * speaker offloads the blocking native constructor — see issue #597).
 */
class AndroidTtsSpeakerTest {

    @Test
    fun `default speech audio profile uses media before Android Q`() {
        assertEquals(
            SpeechAudioAttributesProfile(
                usage = android.media.AudioAttributes.USAGE_MEDIA,
                contentType = android.media.AudioAttributes.CONTENT_TYPE_SPEECH,
            ),
            defaultSpeechAudioAttributesProfile(sdkInt = Build.VERSION_CODES.P),
        )
    }

    @Test
    fun `default speech audio profile uses assistant on Android Q and later`() {
        assertEquals(
            SpeechAudioAttributesProfile(
                usage = android.media.AudioAttributes.USAGE_ASSISTANT,
                contentType = android.media.AudioAttributes.CONTENT_TYPE_SPEECH,
            ),
            defaultSpeechAudioAttributesProfile(sdkInt = Build.VERSION_CODES.Q),
        )
    }

    @Test
    fun `default speech audio profile uses assistant on Android versions after Q`() {
        assertEquals(
            SpeechAudioAttributesProfile(
                usage = android.media.AudioAttributes.USAGE_ASSISTANT,
                contentType = android.media.AudioAttributes.CONTENT_TYPE_SPEECH,
            ),
            defaultSpeechAudioAttributesProfile(sdkInt = Build.VERSION_CODES.Q + 1),
        )
    }

    @Test
    fun `initialize is idempotent when called sequentially after success`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val firstJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        firstJob.join()

        assertTrue("speaker must be ready after successful init", speaker.isReady())
        assertEquals(1, factory.createCount)

        // Second call on a ready speaker must short-circuit.
        val secondResult = speaker.initialize()
        assertTrue(
            "second initialize must succeed without recreating the engine",
            secondResult.isSuccess,
        )
        assertEquals(
            "ready speaker must not create a new TextToSpeech instance",
            1,
            factory.createCount,
        )
    }

    @Test
    fun `concurrent initialize calls spawn only one TextToSpeech instance`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val results = coroutineScope {
            val a = async(Dispatchers.Default) { speaker.initialize() }
            val b = async(Dispatchers.Default) { speaker.initialize() }
            val c = async(Dispatchers.Default) { speaker.initialize() }

            // Let the coroutines contend for initMutex, then complete the
            // first (and only) pending init. Subsequent mutex holders should
            // observe ready == true and skip create().
            factory.awaitPendingInit()
            factory.completePendingInit(TextToSpeech.SUCCESS)

            listOf(a, b, c).awaitAll()
        }

        assertTrue(results.all { it.isSuccess })
        assertEquals(
            "only one TextToSpeech must be created even under concurrent initialize",
            1,
            factory.createCount,
        )
    }

    @Test
    fun `a previous failed TextToSpeech is shutdown before re-initializing`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        // First attempt fails (ERROR status from the platform).
        val firstJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        val firstEngine = factory.completePendingInit(TextToSpeech.ERROR)
        firstJob.join()
        assertNotNull(firstEngine)
        assertFalse(
            "failed init must leave the speaker in a not-ready state",
            speaker.isReady(),
        )
        assertEquals(
            "failed init should not shutdown the fresh engine yet — doInitialize will do that on retry",
            0,
            firstEngine!!.shutdownCount,
        )

        // Retry: the stashed (failed) engine must be shut down before a new
        // one is created, otherwise we leak the native instance.
        val secondJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        assertEquals(
            "retry must shutdown the previously-failed engine",
            1,
            firstEngine.shutdownCount,
        )
        factory.completePendingInit(TextToSpeech.SUCCESS)
        secondJob.join()

        assertTrue(speaker.isReady())
        assertEquals(2, factory.createCount)
    }

    @Test
    fun `release marks the speaker not-ready and shuts down the engine`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val job = launch { speaker.initialize() }
        factory.awaitPendingInit()
        val engine = factory.completePendingInit(TextToSpeech.SUCCESS)
        job.join()
        assertTrue(speaker.isReady())

        speaker.release()

        assertFalse("release must flip ready to false", speaker.isReady())
        // Shutdown may be offloaded to a background thread (see #597), so
        // poll briefly instead of asserting synchronously.
        waitUntil("release must shutdown the live engine") {
            engine!!.shutdownCount >= 1
        }
    }

    @Test
    fun `release while initialize is in flight aborts the fresh engine`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()

        // Caller releases before the engine finishes construction.
        speaker.release()

        // Completing the init now must NOT leave a live engine behind.
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()

        val freshEngine = factory.createdEngines.last()
        waitUntil("fresh engine must be shutdown when release raced init") {
            freshEngine.shutdownCount >= 1
        }
        assertFalse("speaker must report not-ready after a racing release", speaker.isReady())
    }

    @Test
    fun `initialize fails when Japanese voice data is missing`() = runBlocking {
        val factory = FakeTextToSpeechFactory(
            defaultLanguageResult = TextToSpeech.LANG_MISSING_DATA,
        )
        val speaker = AndroidTtsSpeaker(factory)

        val job = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        job.join()

        assertFalse(
            "missing Japanese voice data must leave the speaker not-ready",
            speaker.isReady(),
        )
    }

    // ----------------------------------------------------------------------
    // Issue #737: stale UtteranceProgressListener callbacks must be ignored
    // when their `id` no longer matches the in-flight speak() call. The
    // platform may still deliver onStart/onDone/onError for a previously
    // QUEUE_FLUSH'd utterance after speak() has installed a new continuation;
    // resuming on a stale id would corrupt the new speak's result.
    // ----------------------------------------------------------------------

    @Test
    fun `stale onError for previous utteranceId does not resume current speak`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        // Two back-to-back speak() calls: the second installs a fresh
        // continuation/utteranceId (QUEUE_FLUSH semantics on the real
        // platform). The first speak() coroutine is left orphaned because we
        // never fire onDone/onError that match its id — we cancel it at the
        // end so the test does not hang.
        val aJob = async(Dispatchers.Default) { speaker.speak("hello A", "A") }
        awaitSpeakRecorded(factory, "A")

        val bJob = async(Dispatchers.Default) { speaker.speak("hello B", "B") }
        awaitSpeakRecorded(factory, "B")

        // Stale onError(id="A") arrives late from the platform.
        listener.onError("A", -1)

        // The current speak (B) must remain in flight — the stale callback
        // must not have resumed it with a Failure.
        assertTrue("speak(B) must remain in flight after stale onError(A)", bJob.isActive)

        // The genuine onDone(id="B") must success-resume B.
        listener.onDone("B")
        val bResult = bJob.await()
        assertTrue("speak(B) must succeed when its own onDone fires", bResult.isSuccess)

        // A's continuation is orphaned by design; cancel to clean up.
        aJob.cancel()
    }

    @Test
    fun `stale onDone for previous utteranceId does not resume current speak`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val aJob = async(Dispatchers.Default) { speaker.speak("hello A", "A") }
        awaitSpeakRecorded(factory, "A")

        val bJob = async(Dispatchers.Default) { speaker.speak("hello B", "B") }
        awaitSpeakRecorded(factory, "B")

        // Stale onDone(id="A") arrives late — must not resume B with success.
        listener.onDone("A")
        assertTrue("speak(B) must remain in flight after stale onDone(A)", bJob.isActive)

        // The genuine onError(id="B") must failure-resume B.
        listener.onError("B", -1)
        val bResult = bJob.await()
        assertTrue("speak(B) must fail when its own onError fires", bResult.isFailure)

        aJob.cancel()
    }

    @Test
    fun `stale onStart for previous utteranceId does not flip speaking flag`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val aJob = async(Dispatchers.Default) { speaker.speak("hello A", "A") }
        awaitSpeakRecorded(factory, "A")

        val bJob = async(Dispatchers.Default) { speaker.speak("hello B", "B") }
        awaitSpeakRecorded(factory, "B")

        // No onStart has fired for B yet, so speaking must still be false.
        assertFalse(
            "speaking must be false before onStart fires for B",
            speaker.isSpeaking(),
        )

        // Stale onStart(id="A") must NOT flip speaking to true.
        listener.onStart("A")
        assertFalse(
            "stale onStart(A) must not flip speaking flag for current utterance",
            speaker.isSpeaking(),
        )

        // The genuine onStart(B) does flip it.
        listener.onStart("B")
        assertTrue(
            "onStart(B) must flip speaking flag to true",
            speaker.isSpeaking(),
        )

        listener.onDone("B")
        bJob.await()
        aJob.cancel()
    }

    @Test
    fun `deprecated onError single-arg ignores stale utteranceId`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val aJob = async(Dispatchers.Default) { speaker.speak("hello A", "A") }
        awaitSpeakRecorded(factory, "A")

        val bJob = async(Dispatchers.Default) { speaker.speak("hello B", "B") }
        awaitSpeakRecorded(factory, "B")

        @Suppress("DEPRECATION")
        listener.onError("A")
        assertTrue(
            "speak(B) must remain in flight after stale deprecated onError(A)",
            bJob.isActive,
        )

        @Suppress("DEPRECATION")
        listener.onError("B")
        val bResult = bJob.await()
        assertTrue(
            "speak(B) must fail when its own deprecated onError fires",
            bResult.isFailure,
        )

        aJob.cancel()
    }

    @Test
    fun `same-id onDone resumes speak with success (regression)`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val job = async(Dispatchers.Default) { speaker.speak("hello", "X") }
        awaitSpeakRecorded(factory, "X")

        listener.onDone("X")

        val result = job.await()
        assertTrue("matching onDone must resume speak with success", result.isSuccess)
    }

    @Test
    fun `same-id onError resumes speak with failure (regression)`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val job = async(Dispatchers.Default) { speaker.speak("hello", "Y") }
        awaitSpeakRecorded(factory, "Y")

        listener.onError("Y", -42)

        val result = job.await()
        assertTrue("matching onError must resume speak with failure", result.isFailure)
    }

    @Test
    fun `initialize applies AudioAttributes to the TTS engine`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val job = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        job.join()

        val engine = factory.createdEngines.last()
        assertEquals(
            "doInitialize must call setAudioAttributes exactly once",
            1,
            engine.audioAttributesCalls.size,
        )
        assertEquals(
            "doInitialize must apply the shared speech audio profile",
            defaultSpeechAudioAttributesProfile(),
            engine.audioAttributesCalls.single(),
        )
    }

    @Test
    fun `initialize continues and is ready when audio-attributes application fails`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val job = launch { speaker.initialize() }
        factory.awaitPendingInit()
        // Arrange failure BEFORE completing init so the callback-driven
        // doInitialize sees the error result from setSpeechAudioAttributes.
        factory.createdEngines.last().audioAttributesResult = TextToSpeech.ERROR
        factory.completePendingInit(TextToSpeech.SUCCESS)
        job.join()

        assertTrue(
            "speaker must be ready despite audio-attributes failure",
            speaker.isReady(),
        )
        assertEquals(
            "audio-attributes application must have been attempted once",
            1,
            factory.createdEngines.last().audioAttributesCalls.size,
        )
    }

    @Test
    fun `speak acquires audio focus before delegating to the engine`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val guard = FakeAudioFocusGuard()
        val speaker = AndroidTtsSpeaker(factory, audioFocusGuard = guard)

        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()

        val engine = factory.createdEngines.last()
        // Drive a speak: completion is signalled by onDone via the
        // registered progress listener. We schedule that on a different
        // coroutine so speak() suspends first.
        val speakJob = launch {
            speaker.speak("hello", "u-1")
        }
        // Wait until speak() has actually invoked engine.speak.
        waitUntil("speak must reach engine.speak") {
            engine.speakInvocations.isNotEmpty()
        }
        assertEquals(
            "audio focus must be acquired before engine.speak",
            1,
            guard.acquireCount,
        )
        // Fire onDone to release the suspending speak().
        engine.registeredProgressListeners.first().onDone("u-1")
        speakJob.join()

        assertTrue(
            "speak must scheduleRelease after completion to debounce focus",
            guard.scheduleReleaseCount >= 1,
        )
    }

    @Test
    fun `speak fails fast when audio focus is denied`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val guard = FakeAudioFocusGuard(
            acquireResult = Result.failure(IllegalStateException("denied")),
        )
        val speaker = AndroidTtsSpeaker(factory, audioFocusGuard = guard)

        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()

        val result = speaker.speak("hi", "u-1")
        assertTrue("speak must fail when focus is denied", result.isFailure)
        val engine = factory.createdEngines.last()
        assertEquals(
            "engine.speak must not be invoked when focus is denied",
            0,
            engine.speakInvocations.size,
        )
    }

    @Test
    fun `focus loss during speak stops the engine and resumes the suspending speak`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val guard = FakeAudioFocusGuard()
        val speaker = AndroidTtsSpeaker(factory, audioFocusGuard = guard)

        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()

        val engine = factory.createdEngines.last()
        val speakJob = async { speaker.speak("hello", "u-1") }
        waitUntil("speak must reach engine.speak") {
            engine.speakInvocations.isNotEmpty()
        }

        // Simulate a focus loss while speaking.
        guard.emit(AudioFocusGuard.FocusEvent.LOSS_TRANSIENT)

        val result = speakJob.await()
        assertTrue(
            "focus loss must surface as a failed speak so the queue moves on",
            result.isFailure,
        )
        assertTrue(
            "engine.stop must be invoked on focus loss",
            engine.stopCount >= 1,
        )
    }

    // ----------------------------------------------------------------------
    // Issue #962: stop() must interrupt an in-flight speak() within ~1s so
    // the queue worker is never frozen waiting on the SPEAK_TIMEOUT_MS
    // safety net. Previously stop() cleared currentContinuation before
    // calling engine.stop(), so the UtteranceProgressListener.onStop/onDone
    // callback's id-equality check discarded the resume and the worker
    // suspended for up to the full timeout.
    // ----------------------------------------------------------------------

    @Test
    fun `stop interrupts in-flight speak synchronously`() = runBlocking {
        val (speaker, factory, _) = readySpeaker()
        val engine = factory.createdEngines.first()

        val speakJob = async(Dispatchers.Default) { speaker.speak("hello", "u-stop") }
        awaitSpeakRecorded(factory, "u-stop")

        // Call stop while the speak continuation is suspended.
        speaker.stop()

        // speak must resume promptly with a failure result. Use a generous
        // 1s ceiling: production must resume within milliseconds, but slow
        // CI runners need headroom over the assertion that proved the bug
        // (60s freeze) is gone.
        val result = withTimeout(1000) { speakJob.await() }
        assertTrue("stop must surface as a failed speak", result.isFailure)
        assertTrue(
            "stop must invoke engine.stop on the native TTS",
            engine.stopCount >= 1,
        )
    }

    @Test
    fun `stop after natural completion does not double-resume`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val speakJob = async(Dispatchers.Default) { speaker.speak("hello", "u-done") }
        awaitSpeakRecorded(factory, "u-done")

        // Natural completion path.
        listener.onDone("u-done")
        val result = speakJob.await()
        assertTrue("matching onDone must resume speak with success", result.isSuccess)

        // A subsequent stop() must be a benign no-op — no exception, no
        // attempt to resume an already-resumed continuation. Assert success
        // both to verify the no-op contract AND so the test method's body
        // (which is `= runBlocking { ... }`) returns Unit; otherwise JUnit
        // rejects the whole class with InvalidTestClassError because the
        // last expression of `runBlocking` is the `Result<Unit>` returned
        // by stop().
        assertTrue(
            "subsequent stop() after natural completion must be a benign no-op",
            speaker.stop().isSuccess,
        )
    }

    @Test
    fun `onStop callback resumes the in-flight speak with failure`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val speakJob = async(Dispatchers.Default) { speaker.speak("hello", "u-onstop") }
        awaitSpeakRecorded(factory, "u-onstop")

        // Simulate the platform delivering onStop (e.g. external TTS.stop()
        // by some other component on API 23+). `interrupted` is positional —
        // Kotlin prohibits named arguments for Java framework methods.
        listener.onStop("u-onstop", true)

        val result = speakJob.await()
        assertTrue("onStop must resume speak with failure", result.isFailure)
    }

    @Test
    fun `stale onStop for previous utteranceId does not resume current speak`() = runBlocking {
        val (speaker, factory, listener) = readySpeaker()

        val aJob = async(Dispatchers.Default) { speaker.speak("hello A", "A") }
        awaitSpeakRecorded(factory, "A")

        val bJob = async(Dispatchers.Default) { speaker.speak("hello B", "B") }
        awaitSpeakRecorded(factory, "B")

        // Stale onStop(id="A") must not resume B. (Positional — Kotlin
        // prohibits named arguments for Java framework methods.)
        listener.onStop("A", true)
        assertTrue("speak(B) must remain in flight after stale onStop(A)", bJob.isActive)

        listener.onDone("B")
        val bResult = bJob.await()
        assertTrue("speak(B) must succeed when its own onDone fires", bResult.isSuccess)

        aJob.cancel()
    }

    @Test
    fun `stop swallows native engine stop exception and still resumes speak`() = runBlocking {
        val (speaker, factory, _) = readySpeaker()
        val engine = factory.createdEngines.first()
        engine.throwOnStop = true

        val speakJob = async(Dispatchers.Default) { speaker.speak("hello", "u-stop-throw") }
        awaitSpeakRecorded(factory, "u-stop-throw")

        // stop() must return success even when engine.stop() throws, AND it
        // must still resume the suspended speak() so the queue worker is not
        // wedged on the safety timeout.
        val stopResult = speaker.stop()
        assertTrue(
            "stop() must surface success even when engine.stop() throws",
            stopResult.isSuccess,
        )

        val result = withTimeout(1000) { speakJob.await() }
        assertTrue(
            "speak() must resume with failure even when engine.stop() threw",
            result.isFailure,
        )
        assertTrue(
            "engine.stop() must have been attempted before the swallow",
            engine.stopCount >= 1,
        )
    }

    @Test
    fun `stop after release is a benign no-op`() = runBlocking {
        val (speaker, _, _) = readySpeaker()
        speaker.release()

        // No in-flight speak, engine reference cleared by release(); stop()
        // must still return success without throwing.
        assertTrue(
            "stop() after release must remain a benign no-op",
            speaker.stop().isSuccess,
        )
        // release()'s post-condition: speaker reports not-ready until a
        // fresh initialize() succeeds. Re-asserting here records that
        // stop() does not accidentally flip readiness back on.
        assertFalse(
            "speaker must stay not-ready after release()+stop()",
            speaker.isReady(),
        )
    }

    @Test
    fun `concurrent stop and onDone do not double-resume the speak continuation`() = runBlocking {
        // Reproduce the TOCTOU window between AndroidTtsSpeaker.stop()'s
        // isActive check and pending.resume(): a listener callback on the
        // native TTS worker thread can resume the continuation in between.
        // The IllegalStateException catch in stop() must keep stop()
        // idempotent and prevent the failure from escaping the speaker.
        // 100 iterations: 20 in round 1 detected nothing; widening the
        // window improves the chance of catching a regression while still
        // running under ~1s on a typical CI worker.
        repeat(100) { iteration ->
            val (speaker, factory, listener) = readySpeaker()
            val id = "u-race-$iteration"
            val speakJob = async(Dispatchers.Default) { speaker.speak("hello", id) }
            awaitSpeakRecorded(factory, id)

            // Fire stop() and onDone() concurrently. Whichever resumes the
            // continuation first wins; the loser must not crash stop().
            val stopJob = async(Dispatchers.Default) { speaker.stop() }
            val doneJob = async(Dispatchers.Default) { listener.onDone(id) }

            val stopResult = withTimeout(2000) { stopJob.await() }
            doneJob.await()
            assertTrue(
                "iteration $iteration: stop() must stay idempotent under race",
                stopResult.isSuccess,
            )

            // speak() must have resumed exactly once (success or failure).
            withTimeout(2000) { speakJob.await() }
            speaker.release()
        }
    }

    @Test
    fun `release unsubscribes from the audio focus guard`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val guard = FakeAudioFocusGuard()
        val speaker = AndroidTtsSpeaker(factory, audioFocusGuard = guard)
        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()
        assertEquals(1, guard.listenerCount)

        speaker.release()

        assertEquals(
            "release must remove the speaker's listener from the shared guard",
            0,
            guard.listenerCount,
        )
    }

    @Test
    fun `initialize after release constructs a fresh engine`() = runBlocking {
        val factory = FakeTextToSpeechFactory()
        val speaker = AndroidTtsSpeaker(factory)

        val firstJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        firstJob.join()
        assertTrue(speaker.isReady())

        speaker.release()
        assertFalse(speaker.isReady())

        val secondJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        secondJob.join()

        assertTrue(
            "speaker must be ready again after re-initialization",
            speaker.isReady(),
        )
        assertEquals(
            "re-initialization should construct a fresh TextToSpeech",
            2,
            factory.createCount,
        )
    }
}

/**
 * Suspends until [FakeTextToSpeechFactory.hasPendingInit] returns `true`,
 * polling every millisecond.  Fails the test if [timeoutMs] elapses first.
 *
 * Replaces a bare `yield()` so the tests do not deadlock when
 * `AndroidTtsSpeaker.doInitialize` runs on a different dispatcher (e.g.
 * the real `Dispatchers.IO`) than the test coroutine.
 */
private suspend fun FakeTextToSpeechFactory.awaitPendingInit(timeoutMs: Long = 1000) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (!hasPendingInit()) {
        if (System.currentTimeMillis() > deadline) {
            throw AssertionError(
                "factory.create was not invoked within ${timeoutMs}ms — " +
                    "did AndroidTtsSpeaker reach doInitialize()?",
            )
        }
        delay(1)
    }
}

/**
 * Polls [predicate] every millisecond until it returns `true`, or fails
 * with [reason] once [timeoutMs] elapses.  Used for assertions that may
 * complete on a background thread (e.g. the daemon shutdown thread spawned
 * by `AndroidTtsSpeaker.release`).
 */
private suspend fun waitUntil(
    reason: String,
    timeoutMs: Long = 1000,
    predicate: () -> Boolean,
) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (!predicate()) {
        if (System.currentTimeMillis() > deadline) {
            throw AssertionError("$reason (timed out after ${timeoutMs}ms)")
        }
        delay(1)
    }
}

/**
 * Initializes a [AndroidTtsSpeaker] backed by a [FakeTextToSpeechFactory]
 * and returns the fully-ready triple (speaker, factory, listener) so tests
 * can drive the [UtteranceProgressListener] directly. Used by the issue
 * #737 stale-callback tests.
 */
private suspend fun readySpeaker():
    Triple<AndroidTtsSpeaker, FakeTextToSpeechFactory, UtteranceProgressListener> {
    val factory = FakeTextToSpeechFactory()
    val speaker = AndroidTtsSpeaker(factory)

    coroutineScope {
        val initJob = launch { speaker.initialize() }
        factory.awaitPendingInit()
        factory.completePendingInit(TextToSpeech.SUCCESS)
        initJob.join()
    }

    val listener = factory.createdEngines.first().registeredProgressListeners.first()
    return Triple(speaker, factory, listener)
}

/**
 * Suspends until the fake's [FakeTextToSpeechAdapter.speak] has been
 * invoked with [utteranceId]. This is the deterministic signal that
 * [AndroidTtsSpeaker.speak] has installed both `currentContinuation` and
 * `currentUtteranceId` for that id.
 */
private suspend fun awaitSpeakRecorded(
    factory: FakeTextToSpeechFactory,
    utteranceId: String,
    timeoutMs: Long = 1000,
) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (true) {
        val recorded = factory.createdEngines.firstOrNull()?.speakUtteranceIds.orEmpty()
        if (utteranceId in recorded) return
        if (System.currentTimeMillis() > deadline) {
            throw AssertionError(
                "engine.speak was not invoked with id=$utteranceId within ${timeoutMs}ms",
            )
        }
        delay(1)
    }
}
