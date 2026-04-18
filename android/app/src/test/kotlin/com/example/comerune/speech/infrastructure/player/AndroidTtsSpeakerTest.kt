package com.example.comerune.speech.infrastructure.player

import android.speech.tts.TextToSpeech
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
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
