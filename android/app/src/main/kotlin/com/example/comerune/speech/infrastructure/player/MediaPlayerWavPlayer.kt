package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import androidx.annotation.RequiresApi
import com.example.comerune.speech.domain.model.PlayerState
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
class MediaPlayerWavPlayer(private val context: Context) : WavPlayer {

    private val lock = Any()
    private var mediaPlayer: MediaPlayer? = null
    private var state: PlayerState = PlayerState.IDLE
    private var tempFile: File? = null
    private var released: Boolean = false
    private var activeContinuation: CancellableContinuation<Unit>? = null

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val audioAttributes: AudioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                stopInternal()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Allow ducking; continue playback at reduced volume managed by the system
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                // No action needed for initial version
            }
        }
    }

    // Lazy to avoid class-loading crash on API < 26 where AudioFocusRequest
    // does not exist.  The play() method already guards with a runtime check.
    private val audioFocusRequest: AudioFocusRequest by lazy {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(audioAttributes)
            .setOnAudioFocusChangeListener(focusChangeListener)
            .build()
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
                        player.setDataSource(file.absolutePath)
                        player.prepare()

                        player.setOnCompletionListener {
                            abandonAudioFocus()
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
                            abandonAudioFocus()
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

                        val focusResult = audioManager.requestAudioFocus(audioFocusRequest)
                        if (focusResult != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                            synchronized(lock) {
                                activeContinuation = null
                            }
                            releaseMediaPlayer()
                            cleanupTempFile()
                            continuation.resumeWithException(
                                IllegalStateException("Audio focus request denied")
                            )
                            return@suspendCancellableCoroutine
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
                releaseMediaPlayer()
                cleanupTempFile()
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
        synchronized(lock) {
            state = PlayerState.IDLE
        }
    }

    private fun stopInternal() {
        abandonAudioFocus()
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

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioManager.abandonAudioFocusRequest(audioFocusRequest)
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
