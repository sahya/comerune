package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import androidx.annotation.RequiresApi
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.AudioFocusGuard
import com.example.comerune.speech.domain.player.WavPlayer
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@RequiresApi(Build.VERSION_CODES.O)
class MediaPlayerWavPlayer(
    private val context: Context,
    private val audioFocusGuard: AudioFocusGuard,
) : WavPlayer {

    private val lock = Any()
    private var mediaPlayer: MediaPlayer? = null
    private var state: PlayerState = PlayerState.IDLE
    private var tempFile: File? = null
    private var released: Boolean = false
    private var activeContinuation: CancellableContinuation<Unit>? = null

    /**
     * Tracks whether the caller still wants playback to be live. Used to
     * resume from a STOPPED-by-focus-loss state when focus comes back
     * during the same logical utterance, and to avoid spurious resumes
     * after the player has been intentionally stopped. Exposed via
     * [shouldBePlaying] on the [WavPlayer] contract so AudioFocus / DI
     * callers can read the intent without inferring it from the physical
     * [PlayerState].
     */
    @Volatile
    private var shouldBePlayingFlag: Boolean = false

    override fun shouldBePlaying(): Boolean = shouldBePlayingFlag

    // Lazy so that constructing the player on a pure-JVM unit test JVM
    // (where AudioAttributes.Builder.build() returns null via the
    // returnDefaultValues stub) does not NPE during field init. The first
    // play() access triggers the real build on a real device. This mirrors
    // PR #853's same shift for AndroidTtsSpeaker.
    private val audioAttributes: AudioAttributes by lazy {
        AudioAttributes.Builder().apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setUsage(AudioAttributes.USAGE_ASSISTANT)
            } else {
                setUsage(AudioAttributes.USAGE_MEDIA)
            }
            setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        }.build()
    }

    private val focusListener = AudioFocusGuard.FocusChangeListener { event ->
        when (event) {
            AudioFocusGuard.FocusEvent.LOSS -> stopInternal()
            AudioFocusGuard.FocusEvent.LOSS_TRANSIENT -> pauseInternal()
            AudioFocusGuard.FocusEvent.LOSS_TRANSIENT_CAN_DUCK -> {
                // willPauseWhenDucked=true means the system normally maps this
                // to LOSS_TRANSIENT. Defensive no-op kept so we never duck the
                // assistant voice mid-utterance.
            }
            AudioFocusGuard.FocusEvent.GAIN -> resumeInternal()
        }
    }

    init {
        audioFocusGuard.addListener(focusListener)
    }

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return Result.failure(
                UnsupportedOperationException(
                    "AudioFocusRequest requires API 26+, current SDK: ${Build.VERSION.SDK_INT}"
                )
            )
        }

        synchronized(lock) {
            if (released) {
                return Result.failure(IllegalStateException("Player has been released"))
            }
        }

        // Validate WAV header: minimum 44 bytes and starts with "RIFF"
        if (wavBytes.size < 44) {
            return Result.failure(
                IllegalArgumentException("Invalid WAV data: size ${wavBytes.size} is less than minimum WAV header size of 44 bytes")
            )
        }
        val header = String(wavBytes, 0, 4, Charsets.US_ASCII)
        if (header != "RIFF") {
            return Result.failure(
                IllegalArgumentException("Invalid WAV data: expected RIFF header but found '$header'")
            )
        }

        // Stop any existing playback before starting new one
        stopInternal()

        // Mark intent to play before any suspension so a focus-loss
        // racing with prepare() can still trigger a correct resume later.
        shouldBePlayingFlag = true

        // Acquire focus once for this logical utterance. The guard
        // handles DELAYED → GAIN, idempotency for back-to-back
        // utterances, and abandons via scheduleRelease() afterwards.
        val focusResult = audioFocusGuard.acquire()
        if (focusResult.isFailure) {
            shouldBePlayingFlag = false
            return Result.failure(
                focusResult.exceptionOrNull()
                    ?: IllegalStateException("Audio focus request denied"),
            )
        }

        return withContext(Dispatchers.IO) {
            runCatching {
                val file = File.createTempFile("speech_", ".wav", context.cacheDir)
                synchronized(lock) {
                    tempFile = file
                }

                file.outputStream().use { outputStream ->
                    outputStream.write(wavBytes)
                }

                suspendCancellableCoroutine { continuation ->
                    val player = MediaPlayer()
                    synchronized(lock) {
                        mediaPlayer = player
                        activeContinuation = continuation
                    }

                    try {
                        player.setAudioAttributes(audioAttributes)
                        player.setDataSource(file.absolutePath)
                        player.prepare()

                        player.setOnCompletionListener {
                            shouldBePlayingFlag = false
                            audioFocusGuard.scheduleRelease()
                            releaseMediaPlayer()
                            val cont: CancellableContinuation<Unit>?
                            synchronized(lock) {
                                state = PlayerState.IDLE
                                cont = activeContinuation
                                activeContinuation = null
                            }
                            cleanupTempFile()
                            cont?.takeIf { it.isActive }?.resume(Unit)
                        }

                        player.setOnErrorListener { _, what, extra ->
                            shouldBePlayingFlag = false
                            audioFocusGuard.scheduleRelease()
                            releaseMediaPlayer()
                            val cont: CancellableContinuation<Unit>?
                            synchronized(lock) {
                                state = PlayerState.ERROR
                                cont = activeContinuation
                                activeContinuation = null
                            }
                            cleanupTempFile()
                            cont?.takeIf { it.isActive }?.resumeWithException(
                                IOException("MediaPlayer error: what=$what, extra=$extra")
                            )
                            true
                        }

                        continuation.invokeOnCancellation {
                            stopInternal()
                        }

                        synchronized(lock) {
                            state = PlayerState.PLAYING
                        }
                        player.start()
                    } catch (e: Exception) {
                        synchronized(lock) {
                            state = PlayerState.ERROR
                            activeContinuation = null
                        }
                        releaseMediaPlayer()
                        cleanupTempFile()
                        throw e
                    }
                }
            }.onFailure {
                synchronized(lock) {
                    if (state == PlayerState.PLAYING) {
                        state = PlayerState.ERROR
                    }
                }
                shouldBePlayingFlag = false
                releaseMediaPlayer()
                cleanupTempFile()
                audioFocusGuard.scheduleRelease()
            }
        }
    }

    override suspend fun stop(): Result<Unit> {
        return runCatching {
            stopInternal()
        }
    }

    override fun isPlaying(): Boolean {
        synchronized(lock) {
            return state == PlayerState.PLAYING
        }
    }

    override fun currentState(): PlayerState {
        synchronized(lock) {
            return state
        }
    }

    override fun release() {
        synchronized(lock) {
            released = true
        }
        stopInternal()
        audioFocusGuard.removeListener(focusListener)
        synchronized(lock) {
            state = PlayerState.IDLE
        }
    }

    private fun pauseInternal() {
        synchronized(lock) {
            mediaPlayer?.let { player ->
                try {
                    if (player.isPlaying) {
                        player.pause()
                        state = PlayerState.PAUSED
                    }
                } catch (_: IllegalStateException) {
                    // MediaPlayer may already be in an invalid state
                }
            }
        }
    }

    private fun resumeInternal() {
        // Only attempt to resume if the caller still wants playback.
        // shouldBePlayingFlag remains true for the entire utterance lifetime
        // (cleared only on completion / stop / error), so it is the
        // single source of truth for "should GAIN restart playback?".
        if (!shouldBePlayingFlag) return
        val resumeFailed: Boolean
        synchronized(lock) {
            resumeFailed = if (state == PlayerState.PAUSED || state == PlayerState.STOPPED) {
                mediaPlayer?.let { player ->
                    try {
                        player.start()
                        state = PlayerState.PLAYING
                        false
                    } catch (_: IllegalStateException) {
                        true
                    }
                } ?: true
            } else {
                false
            }
        }
        if (resumeFailed) {
            stopInternal()
        }
    }

    private fun stopInternal() {
        shouldBePlayingFlag = false
        val cont: CancellableContinuation<Unit>?
        synchronized(lock) {
            mediaPlayer?.let { player ->
                try {
                    if (player.isPlaying) {
                        player.stop()
                    }
                } catch (_: IllegalStateException) {
                    // MediaPlayer may already be in an invalid state
                }
            }
            state = PlayerState.STOPPED
            cont = activeContinuation
            activeContinuation = null
        }
        releaseMediaPlayer()
        cleanupTempFile()
        // Defer the focus abandon: another utterance may follow.
        audioFocusGuard.scheduleRelease()
        // Resume the suspended play() coroutine so the worker loop is unblocked.
        // Use IOException (not CancellationException) to avoid cancelling the entire
        // worker coroutine — the caller treats this as a normal playback failure and
        // proceeds to the next queue item.
        cont?.takeIf { it.isActive }?.resumeWithException(
            IOException("Playback interrupted")
        )
    }

    private fun releaseMediaPlayer() {
        synchronized(lock) {
            mediaPlayer?.release()
            mediaPlayer = null
        }
    }

    private fun cleanupTempFile() {
        synchronized(lock) {
            tempFile?.let { file ->
                try {
                    file.delete()
                } catch (_: SecurityException) {
                    // Best effort cleanup
                }
                tempFile = null
            }
        }
    }
}
