package com.example.comerune.speech.domain.player

import com.example.comerune.speech.domain.model.PlayerState

interface WavPlayer {
    suspend fun play(wavBytes: ByteArray): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isPlaying(): Boolean
    fun currentState(): PlayerState
    fun release()

    /**
     * Returns whether the caller still _intends_ playback to be live.
     *
     * This is a logical / intent flag and is independent of the physical
     * [PlayerState]. It stays `true` for the entire lifetime of an
     * utterance — set on [play] before any suspension and cleared on
     * normal completion, [stop], or unrecoverable error — so that
     * transient transitions to [PlayerState.PAUSED] / [PlayerState.STOPPED]
     * caused by audio focus loss can be distinguished from an explicit
     * stop. AudioFocus `GAIN` handlers should consult this predicate
     * before resuming playback.
     *
     * Implementations must keep `shouldBePlaying()` consistent with the
     * intent set inside their own [play] / [stop] / completion / error
     * paths, and return `false` after [release].
     *
     * TODO(follow-up after #735 / #746 land): consume this predicate from
     * `AudioFocusGuard` / `SpeechControllerImpl`'s focus-gain path so
     * focus-resume decisions read intent through the contract instead of
     * re-deriving it from the physical [PlayerState]. Tracked under Issue
     * #916 AC2 (deferred to keep this PR scoped to the contract change).
     */
    fun shouldBePlaying(): Boolean
}
