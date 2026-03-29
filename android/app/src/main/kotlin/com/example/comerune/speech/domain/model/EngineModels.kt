package com.example.comerune.speech.domain.model

// TODO: VoicevoxConfig is unused after initialize() was decoupled from config.
//  Retained for future use when external configuration of dict/model paths is needed.
data class VoicevoxConfig(
    val openJtalkDictDir: String,
    val modelDir: String,
    val defaultSpeakerId: Int
)

data class WavSynthesisResult(
    val wavBytes: ByteArray,
    val text: String,
    val durationEstimateMs: Long?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as WavSynthesisResult
        if (!wavBytes.contentEquals(other.wavBytes)) return false
        if (text != other.text) return false
        if (durationEstimateMs != other.durationEstimateMs) return false
        return true
    }

    override fun hashCode(): Int {
        var result = wavBytes.contentHashCode()
        result = 31 * result + text.hashCode()
        result = 31 * result + (durationEstimateMs?.hashCode() ?: 0)
        return result
    }
}
