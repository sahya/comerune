package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.WavPlayer

/**
 * A [WavPlayer] that delegates to either [AudioTrackWavPlayer] or
 * [MediaPlayerWavPlayer] based on the configured player type.
 *
 * The active player can be switched at runtime via [switchPlayerType].
 * Switching stops any in-progress playback and releases the old player.
 */
@RequiresApi(Build.VERSION_CODES.O)
class SwitchableWavPlayer(private val context: Context) : WavPlayer {

    companion object {
        const val TYPE_AUDIO_TRACK = "audio_track"
        const val TYPE_MEDIA_PLAYER = "media_player"
    }

    private val lock = Any()
    private var currentType: String = TYPE_AUDIO_TRACK
    private var delegate: WavPlayer = AudioTrackWavPlayer(context)

    /**
     * Switch the underlying player implementation.
     *
     * If the type is unchanged, this is a no-op. Otherwise the current
     * player is stopped and released before creating the new one.
     */
    fun switchPlayerType(type: String) {
        synchronized(lock) {
            if (type == currentType) return
            delegate.release()
            delegate = when (type) {
                TYPE_MEDIA_PLAYER -> MediaPlayerWavPlayer(context)
                else -> AudioTrackWavPlayer(context)
            }
            currentType = type
        }
    }

    fun currentPlayerType(): String {
        synchronized(lock) {
            return currentType
        }
    }

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
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
            delegate.release()
        }
    }
}
