package com.example.comerune.speech.infrastructure.player

import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.WavPlayer
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Issue #741 Problem 1: regression tests for the `SwitchableWavPlayer`
 * pending-switch contract.
 *
 * These tests intentionally avoid Robolectric and the real
 * AudioTrack/MediaPlayer backends — the internal factory hook lets us
 * inject [FakeWavPlayer] instances and observe lifecycle ordering
 * deterministically.
 */
class SwitchableWavPlayerTest {

    private fun newSwitchable(
        audioTrack: FakeWavPlayer,
        mediaPlayer: FakeWavPlayer
    ): SwitchableWavPlayer {
        return SwitchableWavPlayer { type ->
            when (type) {
                SwitchableWavPlayer.TYPE_MEDIA_PLAYER -> mediaPlayer
                else -> audioTrack
            }
        }
    }

    @Test
    fun `default delegate is AUDIO_TRACK and play routes to it`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        player.play(ByteArray(0))

        assertEquals(1, audioTrack.playCount.get())
        assertEquals(0, mediaPlayer.playCount.get())
        assertEquals(
            SwitchableWavPlayer.TYPE_AUDIO_TRACK,
            player.currentPlayerType()
        )
    }

    @Test
    fun `switchPlayerType applies on the next play when state is IDLE`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            // First play uses AUDIO_TRACK and resolves to IDLE.
            player.play(ByteArray(0))
            assertEquals(PlayerState.IDLE, audioTrack.currentState())

            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            // Switch is deferred until the next play().
            assertEquals(
                SwitchableWavPlayer.TYPE_AUDIO_TRACK,
                player.currentPlayerType()
            )

            player.play(ByteArray(0))

            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(1, mediaPlayer.playCount.get())
            assertEquals(
                SwitchableWavPlayer.TYPE_MEDIA_PLAYER,
                player.currentPlayerType()
            )
        }

    @Test
    fun `same-type switch is a no-op`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        player.switchPlayerType(SwitchableWavPlayer.TYPE_AUDIO_TRACK)
        player.play(ByteArray(0))

        assertEquals(0, audioTrack.releaseCount.get())
        assertEquals(0, mediaPlayer.playCount.get())
        assertEquals(
            SwitchableWavPlayer.TYPE_AUDIO_TRACK,
            player.currentPlayerType()
        )
    }

    @Test
    fun `switchPlayerType while PLAYING is deferred until next IDLE play`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio", playDelayMs = 50)
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            // Kick off a slow play() so the delegate sits in PLAYING.
            val playJob = async { player.play(ByteArray(0)) }
            // Wait until the fake transitions to PLAYING.
            while (!audioTrack.isPlaying()) yield()

            // Request a swap mid-flight — must NOT release the running player.
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            assertEquals(0, audioTrack.releaseCount.get())
            assertEquals(
                SwitchableWavPlayer.TYPE_AUDIO_TRACK,
                player.currentPlayerType()
            )

            playJob.await()

            // Now the next play() picks up the deferred switch.
            player.play(ByteArray(0))
            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(1, mediaPlayer.playCount.get())
            assertEquals(
                SwitchableWavPlayer.TYPE_MEDIA_PLAYER,
                player.currentPlayerType()
            )
        }

    @Test
    fun `mid-play switch does not release the in-flight delegate`() =
        runBlocking {
            // Regression for the original Issue #741 description: even
            // though play() releases the lock before invoking the
            // delegate, a concurrent switchPlayerType() must not be able
            // to release the very player object the in-flight play() is
            // holding. The PLAYING-guard in applyPendingSwitch enforces
            // this.
            val audioTrack = FakeWavPlayer(tag = "audio", playDelayMs = 80)
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            val playJob = async { player.play(ByteArray(0)) }
            while (!audioTrack.isPlaying()) yield()

            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            // Even after a few scheduling points the in-flight delegate
            // remains intact.
            repeat(5) { yield() }
            assertEquals(0, audioTrack.releaseCount.get())
            assertTrue(audioTrack.isPlaying())

            val result = playJob.await()
            assertTrue(result.isSuccess)
        }

    @Test
    fun `release clears pending switch and tears down current delegate`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            player.release()

            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(0, mediaPlayer.playCount.get())
        }

    @Test
    fun `currentState delegates to underlying player`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        assertEquals(PlayerState.IDLE, player.currentState())
        audioTrack.setStateForTest(PlayerState.PLAYING)
        assertEquals(PlayerState.PLAYING, player.currentState())
        audioTrack.setStateForTest(PlayerState.IDLE)
    }

    @Test
    fun `next play after in-flight completion uses the new delegate instance`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio", playDelayMs = 30)
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            // First play() is in flight on AUDIO_TRACK.
            val firstPlay = async { player.play(ByteArray(0)) }
            while (!audioTrack.isPlaying()) yield()
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            firstPlay.await()
            // Sanity — both fakes are distinct instances.
            assertNotSame(audioTrack as WavPlayer, mediaPlayer as WavPlayer)
            // After the in-flight play() ends, the next play() must use
            // the freshly created MEDIA_PLAYER delegate.
            player.play(ByteArray(0))
            assertEquals(1, mediaPlayer.playCount.get())
            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(
                SwitchableWavPlayer.TYPE_MEDIA_PLAYER,
                player.currentPlayerType()
            )
        }

    // ---- shouldBePlaying delegate-forwarding (Issue #916 AC5) -----------

    @Test
    fun `shouldBePlaying returns false in initial idle state`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        assertEquals(false, player.shouldBePlaying())
    }

    @Test
    fun `shouldBePlaying mirrors the active delegate's intent flag`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            // Simulate "play() set the intent, focus loss paused the
            // physical state" — intent is still true on the delegate.
            audioTrack.setShouldBePlayingForTest(true)
            assertEquals(true, player.shouldBePlaying())

            audioTrack.setShouldBePlayingForTest(false)
            assertEquals(false, player.shouldBePlaying())
        }

    // AC5 (a): pendingType set but applyPendingSwitch() not yet run.
    // The current (= old) delegate's intent must still be returned.
    @Test
    fun `shouldBePlaying after switchPlayerType reflects current delegate before swap`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            audioTrack.setShouldBePlayingForTest(true)
            // Swap is queued but not applied (no play() yet).
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
            assertEquals(
                SwitchableWavPlayer.TYPE_AUDIO_TRACK,
                player.currentPlayerType()
            )
            // Must still see the OLD delegate's intent.
            assertEquals(true, player.shouldBePlaying())
        }

    // AC5 (b): right after applyPendingSwitch() releases the old delegate
    // and creates a new one, the new delegate has not received play()
    // yet, so shouldBePlaying() is false. The old delegate's intent
    // value must NOT be carried across the swap.
    //
    // This case observes the post-swap pre-intent-flip window directly:
    // the new delegate's [play] is suspended on a latch BEFORE it would
    // set shouldBePlayingFlag = true, so a probe at that moment exercises
    // the contract "old delegate's intent value is not carried over and
    // the new delegate has not asserted its own intent yet".
    @Test
    fun `shouldBePlaying is false in the post-swap pre-intent window`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media").apply {
                playProceedGate = CountDownLatch(1)
                playEnteredSignal = CountDownLatch(1)
            }
            val player = newSwitchable(audioTrack, mediaPlayer)

            // Mark intent on the old delegate so we can prove it does
            // NOT bleed across into the new delegate.
            audioTrack.setShouldBePlayingForTest(true)
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)

            // Drive applyPendingSwitch() via play(). The fake's play()
            // suspends on the entry latch BEFORE flipping intent, so the
            // swap is fully applied (old delegate released, new delegate
            // installed) but the new delegate has not yet asserted intent.
            val playJob = async { player.play(ByteArray(0)) }
            // Bounded wait so a regression cannot hang the suite. The
            // fake's playProceedGate await is also bounded at 5s.
            assertTrue(
                "play() should reach the entered-signal within 5s",
                mediaPlayer.playEnteredSignal!!.await(5, TimeUnit.SECONDS)
            )

            // Swap is fully applied: old delegate was released, the new
            // delegate is the one running play(). Yet its intent flag is
            // still false (the latch holds the assignment back).
            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(1, mediaPlayer.playCount.get())
            assertEquals(false, mediaPlayer.shouldBePlaying())
            assertEquals(false, player.shouldBePlaying())

            // Let play() proceed and run to completion so the test
            // teardown leaves the player in a deterministic state.
            mediaPlayer.playProceedGate!!.countDown()
            playJob.await()
        }

    // Companion to AC5 (b): once play() has completed naturally, the new
    // delegate has cleared its own intent flag, so the Switchable view
    // also reports false. This used to be folded into the AC5(b) case;
    // splitting it keeps each assertion's failure mode unambiguous.
    @Test
    fun `shouldBePlaying is false after first play on new delegate completes`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            val mediaPlayer = FakeWavPlayer(tag = "media")
            val player = newSwitchable(audioTrack, mediaPlayer)

            audioTrack.setShouldBePlayingForTest(true)
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)

            player.play(ByteArray(0))
            assertEquals(1, audioTrack.releaseCount.get())
            assertEquals(1, mediaPlayer.playCount.get())

            // New delegate finished its (no-op) play() and cleared intent.
            assertEquals(false, player.shouldBePlaying())
        }

    // AC5 (c): after the first play() on the new delegate, the new
    // delegate's live intent must be visible through the Switchable.
    @Test
    fun `shouldBePlaying tracks the new delegate's intent after swap and play`() =
        runBlocking {
            val audioTrack = FakeWavPlayer(tag = "audio")
            // Hold PLAYING long enough to read the in-flight intent.
            val mediaPlayer = FakeWavPlayer(tag = "media", playDelayMs = 40)
            val player = newSwitchable(audioTrack, mediaPlayer)

            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)

            val playJob = async { player.play(ByteArray(0)) }
            while (!mediaPlayer.isPlaying()) yield()

            // We are now mid-play on the NEW delegate. Intent on the new
            // delegate is true and must be visible through Switchable.
            assertEquals(true, player.shouldBePlaying())

            playJob.await()
            // After completion the new delegate clears intent.
            assertEquals(false, player.shouldBePlaying())
        }

    // AC5 (d): release() drives the underlying delegate's intent to
    // false, so the Switchable view also reports false.
    @Test
    fun `shouldBePlaying is false after release`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        audioTrack.setShouldBePlayingForTest(true)
        player.release()

        assertEquals(false, player.shouldBePlaying())
    }
}
