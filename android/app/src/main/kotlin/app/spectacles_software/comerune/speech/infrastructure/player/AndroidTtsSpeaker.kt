package app.spectacles_software.comerune.speech.infrastructure.player

import android.content.Context
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import app.spectacles_software.comerune.speech.domain.model.PlayerState
import app.spectacles_software.comerune.speech.domain.player.TtsSpeaker
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import kotlin.coroutines.resume

class AndroidTtsSpeaker(private val context: Context) : TtsSpeaker {

    companion object {
        private const val TAG = "AndroidTtsSpeaker"
        private const val SPEAK_TIMEOUT_MS = 60_000L
    }

    private var tts: TextToSpeech? = null

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

    override suspend fun initialize(): Result<Unit> =
        suspendCancellableCoroutine { cont ->
            val newEngine = TextToSpeech(context) { status ->
                val currentEngine = tts
                if (currentEngine == null) {
                    if (cont.isActive) {
                        cont.resume(
                            Result.failure(
                                IllegalStateException("TTS engine was released during init")
                            )
                        )
                    }
                    return@TextToSpeech
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
                        return@TextToSpeech
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

            cont.invokeOnCancellation {
                newEngine.shutdown()
                tts = null
                ready = false
            }
        }

    private val engine: TextToSpeech?
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
        currentContinuation = null
        ready = false
        speaking = false
        state = PlayerState.IDLE
        try {
            engine?.stop()
            engine?.shutdown()
        } catch (e: Exception) {
            Log.w(TAG, "Error during release: ${e.message}")
        }
        tts = null
    }
}
