package com.example.comerune.speech.infrastructure.player

import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.WavPlayer
import kotlinx.coroutines.delay
import java.util.concurrent.atomic.AtomicInteger

/**
 * Minimal WAV player double for unit tests. Avoids any Android framework
 * dependency so it can run in a pure JVM unit test (Robolectric is not
 * configured for the SwitchableWavPlayer tests).
 *
 * The class is intentionally small and explicit: each fake instance holds
 * its own state, exposes a [tag] for identity assertions, and tracks how
 * many times each lifecycle method ran. Tests can drive playback timing
 * by setting [playDelayMs].
 */
class FakeWavPlayer(
    val tag: String = "fake",
    var playDelayMs: Long = 0L
) : WavPlayer {

    @Volatile
    private var state: PlayerState = PlayerState.IDLE
    val playCount = AtomicInteger(0)
    val stopCount = AtomicInteger(0)
    val releaseCount = AtomicInteger(0)

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        playCount.incrementAndGet()
        state = PlayerState.PLAYING
        // Hold PLAYING for the full delay so other coroutines can observe
        // the in-flight state via [isPlaying]/[currentState].
        if (playDelayMs > 0) delay(playDelayMs)
        state = PlayerState.IDLE
        return Result.success(Unit)
    }

    override suspend fun stop(): Result<Unit> {
        stopCount.incrementAndGet()
        state = PlayerState.STOPPED
        return Result.success(Unit)
    }

    override fun isPlaying(): Boolean = state == PlayerState.PLAYING

    override fun currentState(): PlayerState = state

    override fun release() {
        releaseCount.incrementAndGet()
        state = PlayerState.IDLE
    }

    /** Test-only: forcibly set the reported state. */
    fun setStateForTest(newState: PlayerState) {
        state = newState
    }
}
