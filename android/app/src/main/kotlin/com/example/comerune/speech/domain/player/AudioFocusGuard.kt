package com.example.comerune.speech.domain.player

/**
 * Centralized abstraction over Android audio focus.
 *
 * Why:
 *   The previous design had each [WavPlayer] implementation request and
 *   abandon focus per utterance. That caused:
 *   1. Treating `AUDIOFOCUS_REQUEST_DELAYED` as a denial (the actual
 *      Android behaviour is "wait for AUDIOFOCUS_GAIN").
 *   2. Per-utterance request/abandon churn — IPC cost and ducking flicker
 *      between consecutive comments.
 *   3. Each player owning its own [android.media.AudioFocusRequest]
 *      instance, so a switch between MediaPlayer and AudioTrack could
 *      orphan a still-held focus token.
 *
 * AudioFocusGuard is a single shared session-style guard:
 *   - [acquire] is idempotent. If focus is already held, it returns
 *     success without re-requesting.
 *   - [acquire] suspends through the DELAYED → GAIN handshake, so
 *     callers see a deterministic Result.
 *   - [scheduleRelease] holds focus across small inter-utterance gaps so
 *     consecutive playbacks do not duck/unduck the rest of the system.
 *   - [release] is the immediate cleanup path used when the player is
 *     fully torn down.
 *
 * Focus loss / regain events are forwarded to callbacks registered via
 * [addListener]. Each player implementation reacts in its own way (pause
 * vs. stop vs. resume) but they all receive the same events.
 */
interface AudioFocusGuard {

    /**
     * Request audio focus.
     *
     * Behaviour:
     * - If focus is already held (and not currently inside a scheduled
     *   release window), returns [Result.success] immediately without
     *   talking to the platform.
     * - Cancels any pending [scheduleRelease] window.
     * - On `AUDIOFOCUS_REQUEST_GRANTED`, returns [Result.success].
     * - On `AUDIOFOCUS_REQUEST_DELAYED`, suspends until the corresponding
     *   `AUDIOFOCUS_GAIN` callback arrives, then returns [Result.success].
     *   If the system instead delivers a definitive failure (LOSS/etc.)
     *   before GAIN, returns [Result.failure].
     * - On `AUDIOFOCUS_REQUEST_FAILED`, returns [Result.failure].
     */
    suspend fun acquire(): Result<Unit>

    /**
     * Release audio focus immediately.
     *
     * Cancels any pending [scheduleRelease] timer and abandons the focus
     * token in one step. Safe to call when no focus is held.
     */
    fun release()

    /**
     * Schedule a deferred release after [graceMs].
     *
     * If [acquire] is called again before [graceMs] elapses, the
     * scheduled release is cancelled and the existing focus token is
     * reused. This avoids duck/unduck flicker between consecutive short
     * utterances.
     *
     * If [graceMs] elapses without another acquire, the underlying
     * [release] runs.
     */
    fun scheduleRelease(graceMs: Long = DEFAULT_GRACE_MS)

    /**
     * Whether focus is currently held (or pending in the DELAYED window).
     */
    val isHeld: Boolean

    /**
     * Subscribe to focus change events. Listener is invoked on the
     * thread where the platform delivered the focus callback (typically
     * the main thread).
     *
     * Listeners must be removed with [removeListener] when the consumer
     * is released so the guard does not retain torn-down players.
     */
    fun addListener(listener: FocusChangeListener)

    fun removeListener(listener: FocusChangeListener)

    fun interface FocusChangeListener {
        fun onFocusChange(event: FocusEvent)
    }

    /**
     * Subset of [android.media.AudioManager] focus codes that callers
     * actually react to. Mapping happens inside the implementation so
     * tests do not need a real AudioManager.
     */
    enum class FocusEvent {
        /** Permanent loss — the consumer should stop playback. */
        LOSS,

        /** Transient loss (call, alarm, etc.) — the consumer should pause. */
        LOSS_TRANSIENT,

        /**
         * Transient loss where the system would normally allow ducking.
         * With `setWillPauseWhenDucked(true)` this is rerouted by the
         * platform to LOSS_TRANSIENT, but it is exposed here for
         * defensive completeness.
         */
        LOSS_TRANSIENT_CAN_DUCK,

        /** Focus regained after a transient loss. */
        GAIN,
    }

    companion object {
        /**
         * Default grace period before deferred release runs. Chosen to
         * cover the typical inter-utterance gap (queue dispatch + WAV
         * synthesis is well under one second; 5s comfortably covers
         * read-ahead and TTS warmup as well).
         */
        const val DEFAULT_GRACE_MS: Long = 5_000L
    }
}
