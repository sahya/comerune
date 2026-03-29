package com.example.comerune.speech.domain.model

/**
 * User-configurable speech settings.
 *
 * Note: [speedScale], [pitchScale], [intonationScale], [volumeScale],
 * [prePhonemeLength], and [postPhonemeLength] are stored for future use
 * but are NOT yet applied to synthesis. The current VOICEVOX TTS one-shot
 * API does not support these parameters. They will take effect once the
 * audio_query-based synthesis path is implemented.
 */
data class SpeechSettings(
    val enabled: Boolean = true,
    val speakerId: Int = 0, // 四国めたん・あまあま（AppSettings.voicevoxSpeaker と同期）
    val speedScale: Float = 1.15f,
    val pitchScale: Float = 0.0f,
    val intonationScale: Float = 1.0f,
    val volumeScale: Float = 1.0f,
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
    val ngWords: List<String> = emptyList()
)

data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
