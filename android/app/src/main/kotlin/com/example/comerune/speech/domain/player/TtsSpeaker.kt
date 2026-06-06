package com.example.comerune.speech.domain.player

import com.example.comerune.speech.domain.model.PlayerState

/**
 * Platform-agnostic interface for text-to-speech engines that speak text
 * directly (without intermediate WAV synthesis).
 *
 * On Android this is backed by [android.speech.tts.TextToSpeech].
 * On iOS a future implementation would wrap AVSpeechSynthesizer.
 */
interface TtsSpeaker {
    /**
     * Initializes the underlying TTS engine.
     *
     * Contract:
     * - Idempotent: calling [initialize] on an already-ready speaker returns
     *   [Result.success] without recreating the native engine.
     * - Concurrent-safe: overlapping calls must not spawn multiple native
     *   engine instances.
     * - Retry-safe: if a previous call failed, the next call may recreate the
     *   engine without leaking native resources from the failed attempt.
     * - Release-safe: if [release] is called while [initialize] is in flight,
     *   the implementation must shut down any freshly-created native engine
     *   and return a failure, rather than leaving a live instance behind.
     * - Re-init-safe: calling [initialize] after a successful [release] is
     *   valid and must construct a fresh native engine. The implementation
     *   must not permanently latch into a "released" state.
     *
     * Implementations should enforce this contract internally so callers
     * (e.g. UI availability checks + background init paths) can invoke it
     * defensively.
     */
    suspend fun initialize(): Result<Unit>
    suspend fun speak(text: String, utteranceId: String): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isReady(): Boolean
    fun isSpeaking(): Boolean
    fun currentState(): PlayerState
    fun setSpeechRate(rate: Float)
    fun setPitch(pitch: Float)
    fun setVolume(volume: Float)

    /**
     * Sets the safety-net timeout applied to a single [speak] call. The
     * timeout is the upper bound for how long [speak] will suspend waiting
     * for the underlying engine to deliver a terminal callback before the
     * implementation force-cleans up and returns failure. Values are
     * clamped to a sane minimum by implementations to avoid pathological
     * settings (e.g. 0 ms) wedging the queue worker.
     *
     * Issue #965: introduced so slow devices / long utterances can extend
     * the safety net without recompiling. Default behaviour is preserved
     * when callers never invoke this.
     */
    fun setSpeakTimeoutMs(timeoutMs: Long)

    /**
     * Releases all native resources associated with the speaker.
     *
     * Contract:
     * - May be called concurrently with [initialize]. The implementation must
     *   prevent the in-flight init from leaking a `TextToSpeech` instance.
     * - After [release] returns, [isReady] must report `false` until a new
     *   [initialize] succeeds.
     */
    fun release()
}
