package com.example.comerune.speech.infrastructure.player

import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import com.example.comerune.speech.domain.model.PlayerState
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
class AndroidTtsSpeaker(
    private val factory: TextToSpeechFactory,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : TtsSpeaker {

    companion object {
        private const val TAG = "AndroidTtsSpeaker"
        private const val SPEAK_TIMEOUT_MS = 60_000L
    }

    private var tts: TextToSpeechAdapter? = null

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
                    ready = true
                    state = PlayerState.IDLE
                    currentEngine.setOnUtteranceProgressListener(
                        object : UtteranceProgressListener() {
                            override fun onStart(id: String?) {
                                speaking = true
                                state = PlayerState.PLAYING
                            }

                            override fun onDone(id: String?) {
                                speaking = false
                                state = PlayerState.IDLE
                                currentContinuation?.let { c ->
                                    if (c.isActive) c.resume(Result.success(Unit))
                                }
                                currentContinuation = null
                            }

                            @Deprecated("Deprecated in API")
                            override fun onError(id: String?) {
                                speaking = false
                                state = PlayerState.ERROR
                                currentContinuation?.let { c ->
                                    if (c.isActive) {
                                        c.resume(
                                            Result.failure(
                                                RuntimeException("TTS error for $id")
                                            )
                                        )
                                    }
                                }
                                currentContinuation = null
                            }

                            override fun onError(id: String?, errorCode: Int) {
                                speaking = false
                                state = PlayerState.ERROR
                                currentContinuation?.let { c ->
                                    if (c.isActive) {
                                        c.resume(
                                            Result.failure(
                                                RuntimeException(
                                                    "TTS error code=$errorCode for $id"
                                                )
                                            )
                                        )
                                    }
                                }
                                currentContinuation = null
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

        val result = withTimeoutOrNull(SPEAK_TIMEOUT_MS) {
            suspendCancellableCoroutine { cont ->
                currentContinuation = cont

                val params = Bundle().apply {
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                }

                val speakResult =
                    engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                if (speakResult != TextToSpeech.SUCCESS) {
                    currentContinuation = null
                    speaking = false
                    state = PlayerState.ERROR
                    if (cont.isActive) {
                        cont.resume(
                            Result.failure(
                                RuntimeException(
                                    "TTS speak() returned error: $speakResult"
                                )
                            )
                        )
                    }
                }

                cont.invokeOnCancellation {
                    currentContinuation = null
                    engine.stop()
                    speaking = false
                    state = PlayerState.STOPPED
                }
            }
        }

        if (result == null) {
            currentContinuation = null
            engine.stop()
            speaking = false
            state = PlayerState.ERROR
            Log.w(TAG, "speak() timed out after ${SPEAK_TIMEOUT_MS}ms for $utteranceId")
            return Result.failure(RuntimeException("TTS speak timed out"))
        }

        return result
    }

    override suspend fun stop(): Result<Unit> {
        currentContinuation = null
        engine?.stop()
        speaking = false
        state = PlayerState.STOPPED
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
        ready = false
        speaking = false
        state = PlayerState.IDLE
        val engineToShutdown = tts
        tts = null
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
