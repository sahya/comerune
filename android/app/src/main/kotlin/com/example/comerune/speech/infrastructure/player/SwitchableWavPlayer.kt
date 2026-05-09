package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.os.Build
import androidx.annotation.RequiresApi
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.player.AudioFocusGuard
import com.example.comerune.speech.domain.player.WavPlayer

/**
 * A [WavPlayer] that delegates to either [AudioTrackWavPlayer] or
 * [MediaPlayerWavPlayer] based on the configured player type.
 *
 * The active player can be switched at runtime via [switchPlayerType].
 * The actual switch is deferred to the next [play] call to avoid
 * interrupting in-progress playback. If the underlying player is still
 * [PlayerState.PLAYING] at the time the next [play] is invoked, the
 * switch is deferred again and applied at the following [play] call.
 *
 * Both delegates share the same [AudioFocusGuard] instance so the focus
 * token survives the player swap and never gets orphaned by an
 * out-of-order release on the previous delegate.
 *
 * Issue #741 (Problem 1): the previous implementation captured the
 * delegate reference outside of [applyPendingSwitch] and did not check
 * whether playback was already running. Adding the [PlayerState.PLAYING]
 * guard means a `switchPlayerType()` issued mid-playback can never tear
 * down the player that the in-flight `play()` is still using.
 */
@RequiresApi(Build.VERSION_CODES.O)
class SwitchableWavPlayer internal constructor(
    private val playerFactory: (String) -> WavPlayer,
) : WavPlayer {

    /**
     * Production constructor. The factory closes over [context] and creates
     * the real Android-backed players, both sharing [audioFocusGuard] so
     * the focus session survives a delegate swap.
     */
    constructor(context: Context, audioFocusGuard: AudioFocusGuard) : this(
        playerFactory = { type ->
            when (type) {
                TYPE_MEDIA_PLAYER -> MediaPlayerWavPlayer(context, audioFocusGuard)
                else -> AudioTrackWavPlayer(context, audioFocusGuard)
            }
        },
    )

    companion object {
        const val TYPE_AUDIO_TRACK = "audio_track"
        const val TYPE_MEDIA_PLAYER = "media_player"
    }

    private val lock = Any()
    private var currentType: String = TYPE_AUDIO_TRACK
    private var pendingType: String? = null
    private var delegate: WavPlayer = createPlayer(TYPE_AUDIO_TRACK)

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
            pendingType = if (type == currentType) null else type
        }
    }

    fun currentPlayerType(): String {
        synchronized(lock) {
            return currentType
        }
    }

    /**
     * Apply a pending player switch, but only if the current delegate is
     * not actively playing. The whole swap (state check, release, replace,
     * type update) happens inside [lock] so a concurrent `switchPlayerType()`
     * cannot leak a stale `pendingType` past the swap.
     *
     * If the delegate is still PLAYING (e.g. the worker calls `play()` again
     * before the previous playback has fully drained), the pending request
     * is preserved and re-evaluated on the next call.
     */
    private fun applyPendingSwitch() {
        synchronized(lock) {
            val newType = pendingType ?: return
            // Issue #741: defer the swap if playback is in progress so the
            // in-flight play()'s WavPlayer reference is never released
            // out from under it.
            if (delegate.currentState() == PlayerState.PLAYING) return
            if (newType == currentType) {
                pendingType = null
                return
            }
            delegate.release()
            delegate = createPlayer(newType)
            currentType = newType
            pendingType = null
        }
    }

    private fun createPlayer(type: String): WavPlayer = playerFactory(type)

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        // Apply any pending player type switch before starting playback.
        // This is safe because play() is called from the worker loop
        // after the previous playback has completed.
        applyPendingSwitch()
        val player = synchronized(lock) { delegate }
        return player.play(wavBytes)
    }

    override suspend fun stop(): Result<Unit> {
        val player = synchronized(lock) { delegate }
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

    /**
     * Returns the intent flag of the current delegate. [SwitchableWavPlayer]
     * itself does **not** hold an intent field — the delegate is the single
     * source of truth.
     *
     * Swap semantics (see Issue #916 AC5):
     *
     * - **(a)** Right after [switchPlayerType] sets `pendingType` but before
     *   [applyPendingSwitch] has run, the swap has not happened yet. This
     *   call returns the intent of the **current (= old) delegate**.
     * - **(b)** Immediately after [applyPendingSwitch] tears down the old
     *   delegate (which calls [WavPlayer.release], driving its intent to
     *   `false`) and creates a fresh delegate, this call returns `false`
     *   because the new delegate has not received any [play] yet. The old
     *   delegate's intent value is **not** carried over.
     * - **(c)** After the first [play] on the new delegate, this call
     *   returns the new delegate's intent.
     * - **(d)** After [release], the (now released) delegate reports
     *   `false`, so this call also returns `false`.
     */
    override fun shouldBePlaying(): Boolean {
        val player = synchronized(lock) { delegate }
        return player.shouldBePlaying()
    }

    /**
     * Release the underlying delegate and clear any pending switch.
     *
     * Post-release contract (Issue #917): once [release] has returned, any
     * subsequent [play] call MUST resolve to a [Result.failure] — it must
     * NOT throw, and it must NOT silently succeed. The current
     * implementation routes the failed `play()` straight to the released
     * delegate, which then returns a failure from its own released-guard
     * (search "Player has been released" in [MediaPlayerWavPlayer] /
     * [AudioTrackWavPlayer]). A future change may add an early-out guard
     * here in [SwitchableWavPlayer]. Either path is contract-compliant.
     * Tests assert the failure status only and intentionally do not pin
     * the exception type or the guard's location, so the implementation
     * can evolve without rewriting the contract test.
     *
     * Note on AC2 of Issue #917: the issue body's AC2 example asserts the
     * concrete `IllegalStateException` failure type for the delegate
     * players. That assertion is verified at the production source level
     * (see the `Result.failure(IllegalStateException(...))` in each
     * delegate's `play()`) and is exercised through the
     * [SwitchableWavPlayer] external contract above. A direct runtime
     * assertion against the delegate would require Robolectric — without
     * it, the SDK-level guard `Build.VERSION.SDK_INT < O` short-circuits
     * with [UnsupportedOperationException] before the released-guard is
     * reachable on a pure-JVM unit test. Adding Robolectric for this
     * single assertion is out of scope; the implementation lock is
     * provided by the external [SwitchableWavPlayer] contract test plus
     * the [MediaPlayerWavPlayer] / [AudioTrackWavPlayer] release
     * idempotency tests.
     *
     * Calling [release] more than once is safe (idempotent at the
     * delegate level — see [MediaPlayerWavPlayer.release] /
     * [AudioTrackWavPlayer.release], both of which set `released = true`
     * before doing any teardown).
     */
    override fun release() {
        synchronized(lock) {
            pendingType = null
            delegate.release()
        }
    }
}
