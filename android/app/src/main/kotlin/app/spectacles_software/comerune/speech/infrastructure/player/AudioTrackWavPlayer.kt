package app.spectacles_software.comerune.speech.infrastructure.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import app.spectacles_software.comerune.speech.domain.model.PlayerState
import app.spectacles_software.comerune.speech.domain.player.WavPlayer
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@RequiresApi(Build.VERSION_CODES.O)
class AudioTrackWavPlayer(private val context: Context) : WavPlayer {

    companion object {
        private const val TAG = "AudioTrackWavPlayer"
        /** Extra margin added to the WAV duration for the marker fallback timeout. */
        private const val MARKER_TIMEOUT_MARGIN_MS = 2000L

        /**
         * Parses a WAV file header from the given byte array.
         *
         * Handles non-standard WAV files where the "data" chunk may not start at
         * byte 44 by scanning through chunks to locate the "data" chunk ID.
         *
         * Visible for testing.
         */
        internal fun parseWavHeader(wavBytes: ByteArray): WavInfo {
            val buffer = ByteBuffer.wrap(wavBytes).order(ByteOrder.LITTLE_ENDIAN)

            // Skip "RIFF" (4 bytes) + file size (4 bytes) + "WAVE" (4 bytes)
            buffer.position(12)

            var sampleRate = 0
            var channels = 0
            var bitsPerSample = 0
            var dataOffset = -1
            var dataSize = 0

            // Iterate through chunks
            while (buffer.remaining() >= 8) {
                val chunkId = ByteArray(4)
                buffer.get(chunkId)
                val chunkIdStr = String(chunkId, Charsets.US_ASCII)
                val chunkSize = buffer.getInt()

                when (chunkIdStr) {
                    "fmt " -> {
                        if (chunkSize < 16 || buffer.remaining() < chunkSize) {
                            throw IllegalArgumentException(
                                "fmt chunk invalid: size=$chunkSize, remaining=${buffer.remaining()}"
                            )
                        }
                        val audioFormat = buffer.getShort().toInt() and 0xFFFF
                        if (audioFormat != 1) {
                            // 1 = PCM; other formats (e.g. 3 = IEEE float) are not
                            // expected from VOICEVOX but reject gracefully.
                            throw IllegalArgumentException(
                                "Unsupported audio format: $audioFormat (only PCM is supported)"
                            )
                        }
                        channels = buffer.getShort().toInt() and 0xFFFF
                        sampleRate = buffer.getInt()
                        // Skip byteRate (4 bytes) and blockAlign (2 bytes)
                        buffer.position(buffer.position() + 6)
                        bitsPerSample = buffer.getShort().toInt() and 0xFFFF

                        // Skip any extra bytes in the fmt chunk beyond the 16 we read
                        val extraBytes = chunkSize - 16
                        if (extraBytes > 0) {
                            buffer.position(buffer.position() + extraBytes)
                        }
                    }
                    "data" -> {
                        dataOffset = buffer.position()
                        dataSize = chunkSize
                        // No need to continue parsing after finding data chunk
                        break
                    }
                    else -> {
                        // Skip unknown chunks
                        if (chunkSize < 0 || buffer.position() + chunkSize > wavBytes.size) {
                            throw IllegalArgumentException(
                                "Invalid chunk '$chunkIdStr' with size $chunkSize at position ${buffer.position()}"
                            )
                        }
                        buffer.position(buffer.position() + chunkSize)
                    }
                }
            }

            if (dataOffset < 0) {
                throw IllegalArgumentException("WAV data chunk not found")
            }
            if (channels == 0 || sampleRate == 0 || bitsPerSample == 0) {
                throw IllegalArgumentException(
                    "Incomplete WAV header: channels=$channels, sampleRate=$sampleRate, bitsPerSample=$bitsPerSample"
                )
            }

            // Clamp dataSize to available bytes
            val availableBytes = wavBytes.size - dataOffset
            if (dataSize > availableBytes) {
                Log.w(
                    TAG,
                    "WAV data chunk size ($dataSize) exceeds available bytes ($availableBytes), clamping"
                )
                dataSize = availableBytes
            }

            return WavInfo(
                sampleRate = sampleRate,
                channels = channels,
                bitsPerSample = bitsPerSample,
                dataOffset = dataOffset,
                dataSize = dataSize
            )
        }
    }

    internal data class WavInfo(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val dataOffset: Int,
        val dataSize: Int
    )

    private val lock = Any()
    private val timeoutScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var audioTrack: AudioTrack? = null
    private var state: PlayerState = PlayerState.IDLE
    private var released: Boolean = false
    private var activeContinuation: CancellableContinuation<Unit>? = null
    private var markerTimeoutJob: Job? = null

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val audioAttributes: AudioAttributes =
        AudioAttributes.Builder().apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setUsage(AudioAttributes.USAGE_ASSISTANT)
            } else {
                setUsage(AudioAttributes.USAGE_MEDIA)
            }
            setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        }.build()

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                stopInternal()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                pauseInternal()
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                // Allow ducking; continue playback at reduced volume managed by the system
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                resumeInternal()
            }
        }
    }

    private val audioFocusRequest: AudioFocusRequest by lazy {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
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

        val wavInfo = try {
            parseWavHeader(wavBytes)
        } catch (e: Exception) {
            return Result.failure(
                IllegalArgumentException("Failed to parse WAV header: ${e.message}", e)
            )
        }

        // Stop any existing playback before starting new one
        stopInternal()

        return withContext(Dispatchers.IO) {
            runCatching {
                suspendCancellableCoroutine { continuation ->
                    val channelConfig = when (wavInfo.channels) {
                        1 -> AudioFormat.CHANNEL_OUT_MONO
                        2 -> AudioFormat.CHANNEL_OUT_STEREO
                        else -> throw IllegalArgumentException(
                            "Unsupported channel count: ${wavInfo.channels}"
                        )
                    }

                    val audioEncoding = when (wavInfo.bitsPerSample) {
                        8 -> AudioFormat.ENCODING_PCM_8BIT
                        16 -> AudioFormat.ENCODING_PCM_16BIT
                        else -> throw IllegalArgumentException(
                            "Unsupported bits per sample: ${wavInfo.bitsPerSample}"
                        )
                    }

                    val format = AudioFormat.Builder()
                        .setSampleRate(wavInfo.sampleRate)
                        .setChannelMask(channelConfig)
                        .setEncoding(audioEncoding)
                        .build()

                    val track = AudioTrack.Builder()
                        .setAudioAttributes(audioAttributes)
                        .setAudioFormat(format)
                        .setBufferSizeInBytes(wavInfo.dataSize)
                        .setTransferMode(AudioTrack.MODE_STATIC)
                        .build()

                    synchronized(lock) {
                        audioTrack = track
                        activeContinuation = continuation
                    }

                    try {
                        // Write PCM data directly from the ByteArray into AudioTrack
                        val bytesWritten = track.write(
                            wavBytes,
                            wavInfo.dataOffset,
                            wavInfo.dataSize
                        )

                        if (bytesWritten < 0) {
                            throw IOException(
                                "AudioTrack.write failed with error code: $bytesWritten"
                            )
                        }

                        if (bytesWritten != wavInfo.dataSize) {
                            Log.w(
                                TAG,
                                "AudioTrack.write: expected ${wavInfo.dataSize} bytes but wrote $bytesWritten"
                            )
                        }

                        // Calculate total frame count for marker position
                        val bytesPerFrame =
                            wavInfo.channels * (wavInfo.bitsPerSample / 8)
                        val totalFrames = wavInfo.dataSize / bytesPerFrame

                        track.setNotificationMarkerPosition(totalFrames)
                        track.setPlaybackPositionUpdateListener(
                            object : AudioTrack.OnPlaybackPositionUpdateListener {
                                override fun onMarkerReached(track: AudioTrack?) {
                                    markerTimeoutJob?.cancel()
                                    markerTimeoutJob = null
                                    abandonAudioFocus()
                                    releaseAudioTrack()
                                    val cont: CancellableContinuation<Unit>?
                                    synchronized(lock) {
                                        state = PlayerState.IDLE
                                        cont = activeContinuation
                                        activeContinuation = null
                                    }
                                    cont?.takeIf { it.isActive }?.resume(Unit)
                                }

                                override fun onPeriodicNotification(track: AudioTrack?) {
                                    // Not used
                                }
                            }
                        )

                        continuation.invokeOnCancellation {
                            stopInternal()
                        }

                        val focusResult = audioManager.requestAudioFocus(audioFocusRequest)
                        if (focusResult != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                            synchronized(lock) {
                                activeContinuation = null
                            }
                            releaseAudioTrack()
                            continuation.resumeWithException(
                                IllegalStateException("Audio focus request denied")
                            )
                            return@suspendCancellableCoroutine
                        }

                        synchronized(lock) {
                            state = PlayerState.PLAYING
                        }
                        track.play()

                        // Safety timeout: if onMarkerReached never fires (known
                        // issue on some devices), force-resume the coroutine after
                        // the expected playback duration plus a margin.
                        val durationMs = totalFrames * 1000L / wavInfo.sampleRate
                        val timeoutMs = durationMs + MARKER_TIMEOUT_MARGIN_MS
                        markerTimeoutJob = timeoutScope.launch {
                            delay(timeoutMs)
                            Log.w(TAG, "Marker timeout fired after ${timeoutMs}ms — forcing completion")
                            abandonAudioFocus()
                            releaseAudioTrack()
                            val cont: CancellableContinuation<Unit>?
                            synchronized(lock) {
                                state = PlayerState.IDLE
                                cont = activeContinuation
                                activeContinuation = null
                            }
                            cont?.takeIf { it.isActive }?.resume(Unit)
                        }
                    } catch (e: Exception) {
                        synchronized(lock) {
                            state = PlayerState.ERROR
                            activeContinuation = null
                        }
                        releaseAudioTrack()
                        throw e
                    }
                }
            }.onFailure {
                synchronized(lock) {
                    if (state == PlayerState.PLAYING) {
                        state = PlayerState.ERROR
                    }
                }
                releaseAudioTrack()
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
        timeoutScope.cancel()
        synchronized(lock) {
            state = PlayerState.IDLE
        }
    }

    private fun pauseInternal() {
        synchronized(lock) {
            audioTrack?.let { track ->
                try {
                    if (state == PlayerState.PLAYING) {
                        track.pause()
                        state = PlayerState.PAUSED
                    }
                } catch (_: IllegalStateException) {
                    // AudioTrack may already be in an invalid state
                }
            }
        }
    }

    private fun resumeInternal() {
        val resumeFailed: Boolean
        synchronized(lock) {
            resumeFailed = if (state == PlayerState.PAUSED) {
                audioTrack?.let { track ->
                    try {
                        track.play()
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
        // If resume failed, stop entirely so the worker loop can proceed.
        if (resumeFailed) {
            stopInternal()
        }
    }

    private fun stopInternal() {
        markerTimeoutJob?.cancel()
        markerTimeoutJob = null
        abandonAudioFocus()
        val cont: CancellableContinuation<Unit>?
        synchronized(lock) {
            audioTrack?.let { track ->
                try {
                    if (state == PlayerState.PLAYING || state == PlayerState.PAUSED) {
                        track.stop()
                    }
                } catch (_: IllegalStateException) {
                    // AudioTrack may already be in an invalid state
                }
            }
            state = PlayerState.STOPPED
            cont = activeContinuation
            activeContinuation = null
        }
        releaseAudioTrack()
        // Resume the suspended play() coroutine so the worker loop is unblocked.
        // Use IOException (not CancellationException) to avoid cancelling the entire
        // worker coroutine — the caller treats this as a normal playback failure and
        // proceeds to the next queue item.
        cont?.takeIf { it.isActive }?.resumeWithException(
            IOException("Playback interrupted")
        )
    }

    private fun releaseAudioTrack() {
        synchronized(lock) {
            audioTrack?.release()
            audioTrack = null
        }
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioManager.abandonAudioFocusRequest(audioFocusRequest)
        }
    }

}
