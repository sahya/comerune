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

    // ---------------------------------------------------------------------
    // Issue #917: post-release contract
    //
    // These tests pin the *external* contract only — "release() then play()
    // resolves to a failure Result". They intentionally do NOT assert which
    // layer (delegate or SwitchableWavPlayer itself) produced the failure,
    // nor the exception type. A future refactor that adds an early-out
    // released-guard inside SwitchableWavPlayer must keep these tests
    // passing without modification.
    //
    // FakeWavPlayer mirrors the production released-guard contract (see
    // FakeWavPlayer.play), so these tests observe realistic delegate
    // behaviour without dragging in Robolectric or a real Android Context.
    // ---------------------------------------------------------------------

    @Test
    fun `release then play returns failure`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        player.release()
        val result = player.play(ByteArray(0))

        // Contract: play() after release() resolves to failure. The
        // failure path (delegate-side guard vs. a hypothetical future
        // SwitchableWavPlayer self-guard) is intentionally NOT asserted.
        assertTrue(
            "play() after release() must return Result.failure (got: $result)",
            result.isFailure
        )
        // Pin the failure transition more precisely:
        //  - Today (delegate-side guard path): play() routes to the
        //    released delegate, so playCount == 1 and successfulPlayCount
        //    == 0 (guard short-circuits before audio is produced).
        //  - Tomorrow (SwitchableWavPlayer self-guard path): play()
        //    short-circuits before reaching the delegate, so playCount ==
        //    0. successfulPlayCount stays 0 either way.
        // We assert only the "no audio actually played" invariant
        // (successfulPlayCount == 0 for both delegates) so a future
        // self-guard refactor does not require rewriting this test.
        assertEquals(0, audioTrack.successfulPlayCount.get())
        assertEquals(0, mediaPlayer.successfulPlayCount.get())
        // Sanity: the second delegate was never constructed-into-use
        // because the active type at release() was AUDIO_TRACK.
        assertEquals(0, mediaPlayer.playCount.get())
    }

    @Test
    fun `release then switchPlayerType does not throw`() = runBlocking {
        val audioTrack = FakeWavPlayer(tag = "audio")
        val mediaPlayer = FakeWavPlayer(tag = "media")
        val player = newSwitchable(audioTrack, mediaPlayer)

        player.release()

        // Contract: switchPlayerType() after release() must not throw.
        // It only mutates pendingType; any subsequent play() is itself
        // guarded to return failure. We deliberately do NOT assert the
        // post-call value of currentPlayerType()/pendingType — those are
        // implementation details that may change if a self-guard is added
        // later in SwitchableWavPlayer.
        //
        // Wrap the call in an explicit try/catch so the test name's
        // "does not throw" claim is enforced loudly: any thrown exception
        // surfaces as an `AssertionError` with the original cause, not as
        // a generic JUnit "test failed" report.
        try {
            player.switchPlayerType(SwitchableWavPlayer.TYPE_MEDIA_PLAYER)
        } catch (t: Throwable) {
            throw AssertionError(
                "switchPlayerType() after release() must not throw",
                t,
            )
        }

        // No second release on the delegate from switchPlayerType alone.
        assertEquals(1, audioTrack.releaseCount.get())
        assertEquals(0, mediaPlayer.releaseCount.get())
    }
}
