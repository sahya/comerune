package app.spectacles_software.comerune.speech.infrastructure.player

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import app.spectacles_software.comerune.speech.domain.model.PlayerState
import app.spectacles_software.comerune.speech.domain.player.WavPlayer

/**
 * A [WavPlayer] that delegates to either [AudioTrackWavPlayer] or
 * [MediaPlayerWavPlayer] based on the configured player type.
 *
 * The active player can be switched at runtime via [switchPlayerType].
 * The actual switch is deferred to the next [play] call to avoid
 * interrupting in-progress playback.
 */
@RequiresApi(Build.VERSION_CODES.O)
class SwitchableWavPlayer(private val context: Context) : WavPlayer {

    companion object {
        const val TYPE_AUDIO_TRACK = "audio_track"
        const val TYPE_MEDIA_PLAYER = "media_player"
    }

    private val lock = Any()
    private var currentType: String = TYPE_AUDIO_TRACK
    private var pendingType: String? = null
    private var delegate: WavPlayer = AudioTrackWavPlayer(context)

    /**
     * Request a player type switch.
     *
     * The switch is deferred until the next [play] call to avoid
     * releasing the player while playback is in progress.
     * If the requested type is the same as the current type, this is a no-op.
     */
    fun switchPlayerType(type: String) {
        synchronized(lock) {
            if (type == currentType && pendingType == null) return
            if (type == currentType) {
                pendingType = null
            } else {
                pendingType = type
            }
        }
    }

    fun currentPlayerType(): String {
        synchronized(lock) {
            return currentType
        }
    }

    private fun applyPendingSwitch() {
        synchronized(lock) {
            val newType = pendingType ?: return
            pendingType = null
            if (newType == currentType) return
            delegate.release()
            delegate = when (newType) {
                TYPE_MEDIA_PLAYER -> MediaPlayerWavPlayer(context)
                else -> AudioTrackWavPlayer(context)
            }
            currentType = newType
        }
    }

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        // Apply any pending player type switch before starting playback.
        // This is safe because play() is called from the worker loop
        // after the previous playback has completed.
        applyPendingSwitch()
        val player: WavPlayer
        synchronized(lock) {
            player = delegate
        }
        return player.play(wavBytes)
    }

    override suspend fun stop(): Result<Unit> {
        val player: WavPlayer
        synchronized(lock) {
            player = delegate
        }
        return player.stop()
    }

    override fun isPlaying(): Boolean {
        synchronized(lock) {
            return delegate.isPlaying()
        }
    }

    override fun currentState(): PlayerState {
        synchronized(lock) {
            return delegate.currentState()
        }
    }

    override fun release() {
        synchronized(lock) {
            pendingType = null
            delegate.release()
        }
    }
}
