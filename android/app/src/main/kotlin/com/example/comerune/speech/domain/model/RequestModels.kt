package com.example.comerune.speech.domain.model

data class SpeechRequest(
    val text: String,
    val speakerId: Int,
    val speedScale: Float,
    val pitchScale: Float,
    val intonationScale: Float,
    val volumeScale: Float,
    val prePhonemeLength: Float,
    val postPhonemeLength: Float
)

data class SubmitResult(
    val accepted: Boolean,
    val skipped: Boolean,
    val normalizedText: String?,
    val skipReason: String?,
    val queueSize: Int
)

data class QueueOfferResult(
    val accepted: Boolean,
    val reason: String? = null
)
