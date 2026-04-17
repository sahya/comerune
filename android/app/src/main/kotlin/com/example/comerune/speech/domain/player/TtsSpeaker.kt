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
