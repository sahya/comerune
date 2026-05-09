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

    @Volatile
    private var released: Boolean = false
    val playCount = AtomicInteger(0)
    val stopCount = AtomicInteger(0)
    val releaseCount = AtomicInteger(0)

    /**
     * Number of [play] calls that completed successfully (i.e. were NOT
     * short-circuited by the released-guard). Useful for the Issue #917
     * post-release contract test — `playCount` increments before the
     * guard fires so it cannot distinguish "tried to play" from
     * "actually played".
     */
    val successfulPlayCount = AtomicInteger(0)

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        playCount.incrementAndGet()
        // Mirror the released-guard in MediaPlayerWavPlayer.play() and
        // AudioTrackWavPlayer.play() (search "Player has been released"
        // in those files — using a stable token rather than line numbers
        // so this comment does not drift when the production source is
        // edited). Once release() has run, every subsequent play() must
        // resolve to a failure Result. Locking this into the fake means
        // the SwitchableWavPlayer post-release contract test (Issue #917)
        // observes realistic delegate behaviour without dragging in
        // Robolectric / a real Android Context.
        if (released) {
            return Result.failure(
                IllegalStateException("Player has been released")
            )
        }
        state = PlayerState.PLAYING
        // Hold PLAYING for the full delay so other coroutines can observe
        // the in-flight state via [isPlaying]/[currentState].
        if (playDelayMs > 0) delay(playDelayMs)
        state = PlayerState.IDLE
        successfulPlayCount.incrementAndGet()
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
        // Idempotent at the flag level: matches the production release()
        // in MediaPlayerWavPlayer and AudioTrackWavPlayer (search
        // "released = true" — symbol-based reference avoids line drift),
        // where calling release() repeatedly simply re-sets
        // `released = true` and re-runs cleanup.
        released = true
        state = PlayerState.IDLE
    }

    /** Test-only: forcibly set the reported state. */
    fun setStateForTest(newState: PlayerState) {
        state = newState
    }
}
