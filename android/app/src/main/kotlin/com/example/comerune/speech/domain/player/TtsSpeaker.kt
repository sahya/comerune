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
    fun release()
}
