package app.spectacles_software.comerune.speech.domain.model

/**
 * VOICEVOX synthesis mode.
 *
 * - [AUDIO_QUERY]: Two-step AudioQuery → Synthesis path. Supports speed/pitch/
 *   intonation/volume parameters. Higher quality but slower.
 * - [ONE_SHOT]: Single-step TTS path. Faster but ignores all audio parameters
 *   (speed/pitch/intonation/volume are fixed at engine defaults).
 */
enum class SynthesisMode {
    AUDIO_QUERY,
    ONE_SHOT;

    companion object {
        fun fromString(value: String?): SynthesisMode =
            when (value?.uppercase()) {
                "ONE_SHOT" -> ONE_SHOT
                else -> AUDIO_QUERY
            }
    }
}

/**
 * Identifies which TTS engine to use for speech synthesis/playback.
 *
 * - [VOICEVOX]: On-device neural TTS via VOICEVOX Core (synthesize to WAV → play).
 * - [ANDROID_TTS]: Android platform TextToSpeech API (direct speak, no WAV step).
 */
enum class EngineType {
    VOICEVOX,
    ANDROID_TTS;

    companion object {
        fun fromString(value: String?): EngineType =
            when (value?.lowercase()) {
                "android_tts" -> ANDROID_TTS
                else -> VOICEVOX
            }
    }
}

/**
 * User-configurable speech settings.
 *
 * In [SynthesisMode.AUDIO_QUERY] mode, the audio parameters (speed, pitch,
 * intonation, volume) are applied to the AudioQuery before synthesis.
 * In [SynthesisMode.ONE_SHOT] mode, these parameters are ignored by the
 * engine and the built-in defaults are used instead.
 */
data class SpeechSettings(
    val enabled: Boolean = true,
    val engineType: EngineType = EngineType.VOICEVOX,
    val synthesisMode: SynthesisMode = SynthesisMode.AUDIO_QUERY,
    val speakerId: Int = 10004, // VOICEVOX Nemo・女声3（AppSettings.voicevoxSpeaker と同期）
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
    val playerType: String = "audio_track",
    val androidTtsSpeed: Float = 1.0f,
    val androidTtsPitch: Float = 1.0f,
    val androidTtsVolume: Float = 1.0f
)

data class ReplaceRule(
    val pattern: String,
    val replacement: String,
    val enabled: Boolean = true
)
