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

    // Two coordinating latches form a "freeze + signal" pair around the
    // intent-flip point inside [play]. They are intentionally separated so
    // a test can (1) wait until play() has been reached and (2) decide
    // when it may proceed past the freeze point.
    //
    //   test thread          fake.play() coroutine
    //   -----------          ---------------------
    //                        playCount.incrementAndGet()
    //                        playEnteredSignal.countDown()  <-- step 1
    //   playEnteredSignal.await()
    //   <observe pre-intent>
    //                        playProceedGate.await()        <-- step 2
    //   playProceedGate.countDown()
    //                        shouldBePlayingFlag = true
    //                        ...
    //
    // Both default to null so production-style tests are unaffected.

    /**
     * Test-only freeze gate. The test side calls `countDown()` on this
     * latch when it wants the suspended [play] coroutine to resume past
     * the freeze point and flip [shouldBePlayingFlag] to true. While the
     * latch's count is non-zero, [play] is parked on `await()` BEFORE the
     * intent-flip assignment.
     */
    @Volatile
    var playProceedGate: CountDownLatch? = null

    /**
     * Test-only reached-the-freeze-point signal. Counted down by [play]
     * once it has incremented [playCount] and is about to park on
     * [playProceedGate]. The test side calls `await()` to be told that
     * the swap has completed and the new delegate is now the one inside
     * `play()` but has not yet asserted intent.
     */
    @Volatile
    var playEnteredSignal: CountDownLatch? = null

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        playCount.incrementAndGet()
        playEnteredSignal?.countDown()
        // Hold here BEFORE the intent flip so the test can observe the
        // post-swap pre-intent window deterministically.
        playProceedGate?.await(5, TimeUnit.SECONDS)
        // Mirror MediaPlayerWavPlayer L78-82 / AudioTrackWavPlayer L200-204:
        // once release() has run, every subsequent play() must resolve to
        // a failure Result. Locking this into the fake means the
        // SwitchableWavPlayer post-release contract test (Issue #917)
        // observes realistic delegate behaviour without dragging in
        // Robolectric / a real Android Context. The guard fires BEFORE the
        // intent flip so a released player never reports intent-to-play.
        if (released) {
            return Result.failure(
                IllegalStateException("Player has been released")
            )
        }
        // Mirror real implementations: intent flips to true on play() and
        // back to false on natural completion / stop / release.
        shouldBePlayingFlag = true
        state = PlayerState.PLAYING
        // Hold PLAYING for the full delay so other coroutines can observe
        // the in-flight state via [isPlaying]/[currentState].
        if (playDelayMs > 0) delay(playDelayMs)
        state = PlayerState.IDLE
        shouldBePlayingFlag = false
        successfulPlayCount.incrementAndGet()
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
        // Idempotent at the flag level: matches MediaPlayerWavPlayer L222 /
        // AudioTrackWavPlayer L401, where calling release() repeatedly
        // simply re-sets `released = true` and re-runs cleanup.
        released = true
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
