package com.example.comerune.speech.infrastructure.player

import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.WavPlayer
import kotlinx.coroutines.delay
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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
    private var shouldBePlayingFlag: Boolean = false
    val playCount = AtomicInteger(0)
    val stopCount = AtomicInteger(0)
    val releaseCount = AtomicInteger(0)

    /**
     * Test-only entry latch. When non-null, [play] increments [playCount]
     * and signals [playEnteredLatch], then blocks on this latch BEFORE
     * flipping [shouldBePlayingFlag] to true. This lets a test observe
     * the narrow "play() invoked but intent not yet set" window — used
     * by the AC5(b) "swap done, new delegate not yet driven" assertion.
     */
    @Volatile
    var playEntryLatch: CountDownLatch? = null

    /**
     * Test-only signal latch. Counted down once [play] has been entered
     * (after [playCount] increment, before the [playEntryLatch] wait).
     */
    @Volatile
    var playEnteredLatch: CountDownLatch? = null

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        playCount.incrementAndGet()
        playEnteredLatch?.countDown()
        // Hold here BEFORE the intent flip so the test can observe the
        // post-swap pre-intent window deterministically.
        playEntryLatch?.await(5, TimeUnit.SECONDS)
        // Mirror real implementations: intent flips to true on play() and
        // back to false on natural completion / stop / release.
        shouldBePlayingFlag = true
        state = PlayerState.PLAYING
        // Hold PLAYING for the full delay so other coroutines can observe
        // the in-flight state via [isPlaying]/[currentState].
        if (playDelayMs > 0) delay(playDelayMs)
        state = PlayerState.IDLE
        shouldBePlayingFlag = false
        return Result.success(Unit)
    }

    override suspend fun stop(): Result<Unit> {
        stopCount.incrementAndGet()
        shouldBePlayingFlag = false
        state = PlayerState.STOPPED
        return Result.success(Unit)
    }

    override fun isPlaying(): Boolean = state == PlayerState.PLAYING

    override fun currentState(): PlayerState = state

    override fun shouldBePlaying(): Boolean = shouldBePlayingFlag

    override fun release() {
        releaseCount.incrementAndGet()
        state = PlayerState.IDLE
        shouldBePlayingFlag = false
    }

    /** Test-only: forcibly set the reported state. */
    fun setStateForTest(newState: PlayerState) {
        state = newState
    }

    /**
     * Test-only: forcibly set the intent flag without going through [play].
     * Used to simulate "intent is still live during a focus-loss pause" in
     * tests that assert delegate forwarding behaviour.
     */
    fun setShouldBePlayingForTest(value: Boolean) {
        shouldBePlayingFlag = value
    }
}
