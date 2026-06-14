package com.example.comerune.speech.infrastructure.player

import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.AudioFocusGuard
import com.example.comerune.speech.domain.player.TtsSpeakException
import com.example.comerune.speech.domain.player.TtsSpeaker
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

/**
 * Wraps [android.speech.tts.TextToSpeech] with coroutine-friendly init /
 * speak / release semantics.
 *
 * Blocking native calls are kept off the caller's (typically
 * [Dispatchers.Main.immediate]) dispatcher:
 *   - the [TextToSpeech] constructor (blocks ~100 ms while the system TTS
 *     engine is picked up) is dispatched to [ioDispatcher];
 *   - [TextToSpeech.shutdown] is offloaded to a short-lived daemon thread
 *     from [release] because the caller (`onDetachedFromEngine`) is not a
 *     suspend boundary and must return promptly.
 *
 * [factory] supplies the underlying [TextToSpeechAdapter] so that JVM unit
 * tests can swap in a fake implementation without pulling in Android
 * framework types.
 *
 * @param ioDispatcher dispatcher used for the blocking TTS constructor.
 *   Defaults to [Dispatchers.IO]; override in tests with a deterministic
 *   dispatcher when needed.
 */
internal class AndroidTtsSpeaker(
    private val factory: TextToSpeechFactory,
    private val audioFocusGuard: AudioFocusGuard? = null,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : TtsSpeaker {

    companion object {
        private const val TAG = "AndroidTtsSpeaker"
        // Issue #962: previously 60s. The worker now relies on stop() resuming
        // the speak continuation for prompt interruption; the timeout stays as
        // a safety net for cases where neither stop() nor the
        // UtteranceProgressListener delivers a terminal event (e.g. native TTS
        // engine wedges). Long utterances on slow devices may need a
        // configurable value in the future — track in Issue #962.
        private const val SPEAK_TIMEOUT_MS = 15_000L
    }

    private var tts: TextToSpeechAdapter? = null

    private val speechAudioAttributesProfile = defaultSpeechAudioAttributesProfile()

    /**
     * Listener registered against [audioFocusGuard] (when present) so
     * losses on the shared session immediately silence the system TTS.
     * Stops on permanent loss; transient losses are also stopped because
     * Android's TextToSpeech does not support a true pause/resume —
     * stopping is the safest user-visible response.
     */
    private val focusListener: AudioFocusGuard.FocusChangeListener =
        AudioFocusGuard.FocusChangeListener { event ->
            when (event) {
                AudioFocusGuard.FocusEvent.LOSS,
                AudioFocusGuard.FocusEvent.LOSS_TRANSIENT,
                AudioFocusGuard.FocusEvent.LOSS_TRANSIENT_CAN_DUCK -> {
                    val current = tts
                    try {
                        current?.stop()
                    } catch (e: Exception) {
                        Log.w(TAG, "engine.stop() during focus loss failed: ${e.message}")
                    }
                    speaking = false
                    state = PlayerState.STOPPED
                    val cont = currentContinuation
                    currentContinuation = null
                    if (cont != null && cont.isActive) {
                        // Issue #964: same TOCTOU defence as stop() — a
                        // listener callback can resume between the isActive
                        // check and resume() below.
                        try {
                            cont.resume(
                                Result.failure(TtsSpeakException.FocusLost()),
                            )
                        } catch (e: IllegalStateException) {
                            // Observe (not ignore) the benign double-resume so
                            // a regression surfaces in logs.
                            Log.w(
                                TAG,
                                "focusListener: continuation already resumed concurrently: ${e.message}",
                            )
                        }
                    }
                }
                AudioFocusGuard.FocusEvent.GAIN -> {
                    // Re-acquire is requested per-speak(); nothing to do
                    // here because TextToSpeech cannot resume mid-utterance.
                }
            }
        }

    init {
        audioFocusGuard?.addListener(focusListener)
    }

    @Volatile
    private var ready = false

    @Volatile
    private var speaking = false

    @Volatile
    private var state = PlayerState.IDLE

    @Volatile
    private var speechRate = 1.0f

    @Volatile
    private var pitch = 1.0f

    @Volatile
    private var volume = 1.0f

    @Volatile
    private var currentContinuation: CancellableContinuation<Result<Unit>>? = null

    // utteranceId of the in-flight speak() call, paired with
    // [currentContinuation]. Used by the [UtteranceProgressListener] callbacks
    // to ignore stale events from a previously-flushed utterance: with
    // QUEUE_FLUSH, the platform may still deliver onError/onDone for the
    // cancelled utterance after a new speak() has installed its own
    // continuation. Resuming on a stale id would wrongly fail/complete the
    // current speak. This field must always be updated together with
    // [currentContinuation] so the pair stays consistent.
    @Volatile
    private var currentUtteranceId: String? = null

    // Signals to an in-flight initialize() that the caller has released the
    // speaker and any freshly-constructed TextToSpeech must be shut down
    // instead of reported as ready. release() is not suspend, so it cannot
    // take `initMutex`; this flag closes the initialize()/release() race
    // without requiring release() to block.
    @Volatile
    private var released = false

    // Serializes initialize() so concurrent callers (e.g. eager VOICEVOX init +
    // availability check from the settings screen) do not spawn multiple
    // TextToSpeech instances and leak the first one.
    private val initMutex = Mutex()

    override suspend fun initialize(): Result<Unit> = initMutex.withLock {
        // Clear the released flag so a release()-then-initialize() sequence
        // can succeed. We only observe `released` inside this mutex or the
        // single-threaded TTS init callback, so the reset does not race with
        // a concurrent release() that raced our lock acquisition — such a
        // release() simply sets the flag back to true before we touch TTS.
        released = false
        if (ready) return@withLock Result.success(Unit)
        doInitialize()
    }

    // The `TextToSpeech` constructor and any companion shutdown of the
    // previous engine can block the caller for ~100 ms on Android. Run the
    // initialization bootstrap on [ioDispatcher] so the plugin's
    // `Dispatchers.Main.immediate` scope stays responsive during app start
    // and settings-screen availability checks.
    private suspend fun doInitialize(): Result<Unit> = withContext(ioDispatcher) {
        suspendCancellableCoroutine { cont ->
            // Defensively shutdown any lingering TextToSpeech from a previous
            // failed init; otherwise we leak the native instance when a caller
            // retries (e.g. the settings screen re-invoking the availability
            // check after voice data is installed).
            tts?.let { previous ->
                try {
                    previous.shutdown()
                } catch (e: Exception) {
                    Log.w(TAG, "Error shutting down previous TTS: ${e.message}")
                }
                tts = null
            }
            lateinit var newEngine: TextToSpeechAdapter
            newEngine = factory.create { status ->
                // If release() fired while the native TTS was initializing,
                // drop the fresh instance instead of leaking it. Without this
                // check, the engine silently becomes ready-to-go even though
                // the caller has already asked us to release.
                if (released) {
                    abortInitDueToRelease(newEngine, cont)
                    return@create
                }
                val currentEngine = tts
                if (currentEngine == null) {
                    if (cont.isActive) {
                        cont.resume(
                            Result.failure(
                                IllegalStateException("TTS engine was released during init")
                            )
                        )
                    }
                    return@create
                }
                if (status == TextToSpeech.SUCCESS) {
                    val result = currentEngine.setLanguage(Locale.JAPANESE)
                    if (result == TextToSpeech.LANG_MISSING_DATA ||
                        result == TextToSpeech.LANG_NOT_SUPPORTED
                    ) {
                        Log.w(TAG, "Japanese not available, status=$result")
                        ready = false
                        if (cont.isActive) {
                            cont.resume(
                                Result.failure(
                                    IllegalStateException("Japanese TTS not available")
                                )
                            )
                        }
                        return@create
                    }
                    currentEngine.setSpeechRate(speechRate)
                    currentEngine.setPitch(pitch)
                    // Apply the same focus profile (USAGE_ASSISTANT / SPEECH)
                    // we use for the WAV pipeline. Without this, the
                    // platform may treat system TTS output as
                    // USAGE_UNKNOWN and silence it during DND or
                    // battery-saver focus restrictions (#736).
                    val attributesResult =
                        currentEngine.setSpeechAudioAttributes(speechAudioAttributesProfile)
                    if (attributesResult != TextToSpeech.SUCCESS) {
                        Log.w(
                            TAG,
                            "setAudioAttributes failed (result=$attributesResult). " +
                                "Continuing with engine defaults; voice may be ducked or routed " +
                                "to an unexpected stream on this device.",
                        )
                    }
                    ready = true
                    state = PlayerState.IDLE
                    currentEngine.setOnUtteranceProgressListener(
                        object : UtteranceProgressListener() {
                            // Each callback first compares `id` against the
                            // currently-tracked utteranceId. With QUEUE_FLUSH,
                            // a freshly-cancelled utterance can still emit
                            // onStart/onDone/onError after speak() has moved
                            // on to a new id; resuming the new continuation on
                            // a stale event would corrupt its result. See
                            // issue #737.
                            override fun onStart(id: String?) {
                                if (id != currentUtteranceId) return
                                speaking = true
                                state = PlayerState.PLAYING
                            }

                            override fun onDone(id: String?) {
                                if (id != currentUtteranceId) return
                                speaking = false
                                state = PlayerState.IDLE
                                currentContinuation?.let { c ->
                                    if (c.isActive) c.resume(Result.success(Unit))
                                }
                                currentContinuation = null
                                currentUtteranceId = null
                            }

                            // Override required by UtteranceProgressListener stub even though
                            // the single-arg form is deprecated since API 21 (two-arg form below).
                            // Kotlin 2.3 surfaces OVERRIDE_DEPRECATION despite @Deprecated.
                            @Deprecated("Deprecated in API")
                            @Suppress("OVERRIDE_DEPRECATION")
                            override fun onError(id: String?) {
                                if (id != currentUtteranceId) return
                                speaking = false
                                state = PlayerState.ERROR
                                currentContinuation?.let { c ->
                                    if (c.isActive) {
                                        c.resume(
                                            Result.failure(
                                                TtsSpeakException.EngineError(
                                                    "TTS error for $id"
                                                )
                                            )
                                        )
                                    }
                                }
                                currentContinuation = null
                                currentUtteranceId = null
                            }

                            override fun onError(id: String?, errorCode: Int) {
                                if (id != currentUtteranceId) return
                                speaking = false
                                state = PlayerState.ERROR
                                currentContinuation?.let { c ->
                                    if (c.isActive) {
                                        c.resume(
                                            Result.failure(
                                                TtsSpeakException.EngineError(
                                                    "TTS error code=$errorCode for $id"
                                                )
                                            )
                                        )
                                    }
                                }
                                currentContinuation = null
                                currentUtteranceId = null
                            }

                            // Issue #962: TextToSpeech.stop() can deliver
                            // onStop on API 23+. Resume the in-flight speak()
                            // with a failure so the queue worker advances
                            // immediately. AndroidTtsSpeaker.stop() also
                            // resumes synchronously for the same reason, so
                            // this callback is belt-and-suspenders: whichever
                            // path delivers first wins via isActive checks.
                            override fun onStop(id: String?, interrupted: Boolean) {
                                if (id != currentUtteranceId) return
                                speaking = false
                                state = PlayerState.STOPPED
                                currentContinuation?.let { c ->
                                    if (c.isActive) {
                                        // Issue #966: a platform-delivered
                                        // onStop reflects a caller-driven
                                        // stop (TextToSpeech.stop() was
                                        // invoked by us in [stop] /
                                        // invokeOnCancellation, or by an
                                        // external component on API 23+).
                                        // Surfacing it as the same
                                        // [TtsSpeakException.UserStopped]
                                        // as the synchronous stop() path
                                        // lets the controller skip the
                                        // `speech_failed` emit so the UI
                                        // does not flip to ERROR.
                                        c.resume(
                                            Result.failure(
                                                TtsSpeakException.UserStopped(),
                                            ),
                                        )
                                    }
                                }
                                currentContinuation = null
                                currentUtteranceId = null
                            }
                        }
                    )
                    Log.i(TAG, "Initialized successfully")
                    if (cont.isActive) {
                        cont.resume(Result.success(Unit))
                    }
                } else {
                    Log.e(TAG, "Initialization failed, status=$status")
                    ready = false
                    state = PlayerState.ERROR
                    if (cont.isActive) {
                        cont.resume(
                            Result.failure(
                                IllegalStateException("TTS init failed: $status")
                            )
                        )
                    }
                }
            }
            tts = newEngine

            // Close the window between `tts = newEngine` and the init
            // callback firing: if release() ran during the TextToSpeech
            // constructor or this stash, the callback may still claim the
            // engine is ready. Shut it down here so no live native instance
            // outlives release().
            if (released) {
                abortInitDueToRelease(newEngine, cont)
                return@suspendCancellableCoroutine
            }

            cont.invokeOnCancellation {
                newEngine.shutdown()
                tts = null
                ready = false
            }
        }
    }

    // Shared cleanup for the two doInitialize() spots where a concurrent
    // release() can invalidate the freshly-constructed TextToSpeech: both
    // call sites must shutdown newEngine, clear `tts` only if it still
    // points to newEngine, and fail the init continuation with the same
    // message. Extracting this avoids two copies of the cleanup drifting
    // apart over time (noted by the Round 1 "保守性仙人" review).
    private fun abortInitDueToRelease(
        newEngine: TextToSpeechAdapter,
        cont: CancellableContinuation<Result<Unit>>,
    ) {
        try {
            newEngine.shutdown()
        } catch (e: Exception) {
            Log.w(TAG, "Error shutting down TTS during release race: ${e.message}")
        }
        if (tts === newEngine) {
            tts = null
        }
        ready = false
        if (cont.isActive) {
            cont.resume(
                Result.failure(
                    IllegalStateException("TTS engine released during init")
                )
            )
        }
    }

    private val engine: TextToSpeechAdapter?
        get() = tts

    override suspend fun speak(text: String, utteranceId: String): Result<Unit> {
        val engine = this.engine
        if (engine == null || !ready) {
            return Result.failure(IllegalStateException("TTS not initialized"))
        }

        // Acquire shared audio focus before handing the text to the system
        // TTS engine. Without this, Android's focus policy can silence the
        // engine in DND / battery-saver / focus-loss scenarios with no
        // error surfaced (#736). Failures here propagate to the caller so
        // the queue can move on instead of waiting for an utterance that
        // will never come.
        val guard = audioFocusGuard
        if (guard != null) {
            val focusResult = guard.acquire()
            if (focusResult.isFailure) {
                return Result.failure(
                    focusResult.exceptionOrNull()
                        ?: IllegalStateException("Audio focus request denied"),
                )
            }
        }

        val result = withTimeoutOrNull(SPEAK_TIMEOUT_MS) {
            suspendCancellableCoroutine { cont ->
                // Pair the utteranceId with the continuation so the
                // UtteranceProgressListener can ignore stale callbacks from
                // a previously-flushed utterance (issue #737).
                currentContinuation = cont
                currentUtteranceId = utteranceId

                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                }

                val speakResult =
                    engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                if (speakResult != TextToSpeech.SUCCESS) {
                    currentContinuation = null
                    currentUtteranceId = null
                    speaking = false
                    state = PlayerState.ERROR
                    if (cont.isActive) {
                        cont.resume(
                            Result.failure(
                                TtsSpeakException.EngineError(
                                    "TTS speak() returned error: $speakResult"
                                )
                            )
                        )
                    }
                }

                cont.invokeOnCancellation {
                    currentContinuation = null
                    currentUtteranceId = null
                    engine.stop()
                    speaking = false
                    state = PlayerState.STOPPED
                }
            }
        }

        // Release focus with a grace window so back-to-back utterances
        // do not duck/unduck the rest of the system between every comment.
        guard?.scheduleRelease()

        if (result == null) {
            currentContinuation = null
            currentUtteranceId = null
            engine.stop()
            speaking = false
            state = PlayerState.ERROR
            Log.w(TAG, "speak() timed out after ${SPEAK_TIMEOUT_MS}ms for $utteranceId")
            return Result.failure(TtsSpeakException.Timeout(SPEAK_TIMEOUT_MS))
        }

        return result
    }

    override suspend fun stop(): Result<Unit> {
        // Issue #962: capture and resume any in-flight continuation BEFORE
        // clearing the pair so the queue worker leaves speak() immediately.
        // Previously this path set currentContinuation = null first and then
        // called engine.stop(); the listener's id-equality check then
        // discarded the onStop/onDone callback and the worker sat in
        // suspendCancellableCoroutine until the 60s safety timeout fired.
        val pending = currentContinuation
        currentContinuation = null
        currentUtteranceId = null
        try {
            engine?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "engine.stop() failed: ${e.message}")
        }
        speaking = false
        state = PlayerState.STOPPED
        if (pending != null && pending.isActive) {
            // Defensive: a listener callback (onDone/onError/onStop) on the
            // native TTS worker thread can race with us between this
            // isActive check and the resume call below. If the listener
            // wins, kotlinx.coroutines throws IllegalStateException on our
            // second resume attempt; swallow it so stop() stays
            // unconditional and idempotent. The earlier resume's result
            // (success on onDone, failure on onError/onStop) is preserved —
            // only our redundant failure here is dropped.
            //
            // Regression test:
            //   AndroidTtsSpeakerTest.`concurrent stop and onDone do not
            //   double-resume the speak continuation`.
            try {
                pending.resume(
                    Result.failure(TtsSpeakException.UserStopped()),
                )
            } catch (e: IllegalStateException) {
                Log.d(TAG, "stop(): continuation already resumed concurrently: ${e.message}")
            }
        }
        return Result.success(Unit)
    }

    override fun isReady(): Boolean = ready

    override fun isSpeaking(): Boolean = speaking

    override fun currentState(): PlayerState = state

    override fun setSpeechRate(rate: Float) {
        speechRate = rate.coerceIn(0.1f, 4.0f)
        engine?.setSpeechRate(speechRate)
    }

    override fun setPitch(pitch: Float) {
        this.pitch = pitch.coerceIn(0.1f, 4.0f)
        engine?.setPitch(this.pitch)
    }

    override fun setVolume(volume: Float) {
        this.volume = volume.coerceIn(0.0f, 1.0f)
    }

    override fun release() {
        // Set `released` first so that any initialize() coroutine still
        // racing with us observes the flag before it finishes wiring up a
        // fresh TextToSpeech instance. The follow-up shutdown of the
        // currently-stashed engine is a best-effort: initialize() also
        // checks `released` after storing newEngine and will clean up the
        // instance we could not see yet.
        released = true
        currentContinuation = null
        currentUtteranceId = null
        ready = false
        speaking = false
        state = PlayerState.IDLE
        val engineToShutdown = tts
        tts = null
        // Unsubscribe from the shared guard so it does not retain this
        // torn-down speaker. We deliberately do NOT call guard.release()
        // because the guard is shared with the WAV players and their
        // playback may still need the focus token. Their release path
        // (or a scheduleRelease() that fires after them) will abandon
        // focus when no consumer is left.
        audioFocusGuard?.removeListener(focusListener)
        // stop() is non-blocking per Android docs, keep it on the caller's
        // thread so any in-flight utterance is cancelled immediately.
        try {
            engineToShutdown?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error during stop(): ${e.message}")
        }
        // shutdown() can block for ~100 ms while the native TTS service
        // unbinds. release() is called from onDetachedFromEngine which is
        // synchronous, so we offload the blocking part to a short-lived
        // daemon thread — fire-and-forget is safe because no one observes
        // completion (the speaker is already marked not-ready above).
        if (engineToShutdown != null) {
            Thread {
                try {
                    engineToShutdown.shutdown()
                } catch (e: Exception) {
                    Log.w(TAG, "Error during background shutdown(): ${e.message}")
                }
            }.apply {
                name = "AndroidTtsSpeaker-shutdown"
                isDaemon = true
                start()
            }
        }
    }
}
