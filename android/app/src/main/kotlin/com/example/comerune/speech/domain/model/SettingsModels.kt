package com.example.comerune.speech.domain.model

/**
 * User-configurable speech settings.
 *
 * These parameters are applied to the VOICEVOX AudioQuery before synthesis,
 * controlling volume, speed, pitch, and intonation at the engine level.
 */
data class SpeechSettings(
    val enabled: Boolean = true,
    val speakerId: Int = 10000, // VOICEVOX Nemo・男声2（AppSettings.voicevoxSpeaker と同期）
    val speedScale: Float = 1.15f,
    val pitchScale: Float = 0.0f,
    val intonationScale: Float = 1.0f,
    val volumeScale: Float = 0.7f,
    val prePhonemeLength: Float = 0.1f,
    val postPhonemeLength: Float = 0.1f,
    val maxTextLength: Int = 50,
    val maxQueueSize: Int = 20,
    val duplicateWindowMs: Long = 5000L,
    val skipEmojiOnly: Boolean = true,
    val skipUrlOnly: Boolean = true,
    val replaceUrlWith: String = "URL省略",
    val trimLongTextSuffix: String = "、以下省略",
    val dictionaryRules: List<ReplaceRule> = emptyList(),
    val ngWords: List<String> = emptyList(),
    val playerType: String = "audio_track"
)

data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
