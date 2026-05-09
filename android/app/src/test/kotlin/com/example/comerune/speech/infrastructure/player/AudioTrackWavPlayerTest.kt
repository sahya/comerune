package com.example.comerune.speech.infrastructure.player

import android.content.ContextWrapper
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Issue #917: post-release contract for [AudioTrackWavPlayer].
 *
 * Mirrors [MediaPlayerWavPlayerTest] — see that file's class-level Kdoc
 * for the rationale on (a) the narrow scope, (b) why the released-guard's
 * `IllegalStateException` is verified by inspection rather than asserted
 * here, and (c) why [ContextWrapper] with a null base is a safe stub.
 *
 * The header-parsing contract for this player has its own dedicated test
 * file ([AudioTrackWavParserTest]); keeping the lifecycle / release
 * contract in a separate file follows AGENTS.md "1 対象 = 1 ファイル"
 * by mapping it to the player class itself rather than to the static
 * parser helper.
 */
class AudioTrackWavPlayerTest {

    private fun stubContext(): android.content.Context = ContextWrapper(null)

    @Test
    fun `release is idempotent and detaches the focus listener exactly once`() {
        val focusGuard = FakeAudioFocusGuard()
        val player = AudioTrackWavPlayer(stubContext(), focusGuard)
        // init { addListener(focusListener) } registers exactly one listener.
        assertEquals(1, focusGuard.listenerCount)

        player.release()
        assertEquals(0, focusGuard.listenerCount)

        // Second release must be a no-op (idempotent — see
        // AudioTrackWavPlayer L401: `released = true` is set
        // unconditionally and the timeoutScope is already cancelled).
        player.release()
        assertEquals(0, focusGuard.listenerCount)
    }
}
