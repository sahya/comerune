package com.example.comerune.speech.infrastructure.player

import android.content.ContextWrapper
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Issue #917: post-release contract for [MediaPlayerWavPlayer].
 *
 * Scope (intentionally narrow):
 * - Verify that [MediaPlayerWavPlayer.release] is idempotent: calling it
 *   twice is safe, both invocations remove a listener cleanly via the
 *   shared [FakeAudioFocusGuard], and no state-machine or focus-guard
 *   exception leaks out.
 *
 * Why no `release() -> play() returns IllegalStateException` test here:
 *   The first statement in [MediaPlayerWavPlayer.play] checks
 *   `Build.VERSION.SDK_INT < Build.VERSION_CODES.O` and short-circuits
 *   with [UnsupportedOperationException]. In a pure-JVM unit test the
 *   stub `Build.VERSION.SDK_INT` is always 0 — and Java 17 inlines that
 *   constant at the call site, so reflection cannot raise it without
 *   Robolectric. Pinning the released-guard's `IllegalStateException`
 *   (the assertion AC2 of Issue #917 calls for) therefore requires a
 *   Robolectric or instrumented-test setup. Adding that here would be a
 *   structural change well outside the "test-additions only" scope of
 *   this issue, so the released-guard's exception type is verified by
 *   inspection (search "Player has been released" in
 *   [MediaPlayerWavPlayer]) and locked at the external contract level by
 *   [SwitchableWavPlayerTest] instead.
 *
 * Why a stub Context works:
 *   [MediaPlayerWavPlayer.release] never touches `context` — it only
 *   tears down the (null-when-never-played) MediaPlayer / temp file and
 *   detaches its focus listener. Construction stores the reference but
 *   does not dereference it. We therefore pass a [ContextWrapper] with
 *   no base Context: any accidental method call would NPE immediately
 *   and fail the test loudly, so this stub cannot silently mask a real
 *   regression.
 */
class MediaPlayerWavPlayerTest {

    // TODO(post-#917): when Robolectric is introduced for any other
    // unit test in this module, add a `release-then-play returns
    // IllegalStateException` test here so the runtime assertion AC2 of
    // Issue #917 originally asked for is recovered automatically. The
    // one-line addition is `assertTrue(result.exceptionOrNull() is
    // IllegalStateException)` once the SDK_INT guard can be bypassed.

    private fun stubContext(): android.content.Context = ContextWrapper(null)

    @Test
    fun `release is idempotent and detaches the focus listener exactly once`() {
        val focusGuard = FakeAudioFocusGuard()
        val player = MediaPlayerWavPlayer(stubContext(), focusGuard)
        // init { addListener(focusListener) } registers exactly one listener.
        assertEquals(1, focusGuard.listenerCount)

        player.release()
        assertEquals(0, focusGuard.listenerCount)

        // A second release must NOT throw (idempotent contract — search
        // "released = true" in MediaPlayerWavPlayer.release: the flag is
        // set unconditionally, and removeListener of an already-removed
        // listener is a no-op on FakeAudioFocusGuard /
        // CopyOnWriteArrayList).
        player.release()
        assertEquals(0, focusGuard.listenerCount)
    }

    /**
     * Issue #927: drift guard. The production released-guard message and the
     * [FakeWavPlayer] released-guard message must stay identical. Both now
     * read the shared [PLAYER_RELEASED_MESSAGE] constant, so renaming it
     * changes production and the fake together. This test fails the moment
     * the fake's released failure stops matching the shared constant —
     * catching the silent drift the comment-only "search the literal"
     * convention could not.
     */
    @Test
    fun `fake released-guard message matches the shared production constant`() =
        runBlocking {
            val fake = FakeWavPlayer()
            fake.release()
            val result = fake.play(ByteArray(0))

            assertEquals(true, result.isFailure)
            assertEquals(
                PLAYER_RELEASED_MESSAGE,
                result.exceptionOrNull()?.message
            )
        }
}
