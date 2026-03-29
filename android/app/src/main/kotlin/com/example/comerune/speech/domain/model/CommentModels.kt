package com.example.comerune.speech.domain.model

data class RawComment(
    val id: String,
    val text: String,
    val userId: String?,
    val postedAtEpochMs: Long,
    val score: Int? = null,
    val isOwner: Boolean = false
)

data class NormalizedComment(
    val id: String,
    val originalText: String,
    val normalizedText: String,
    val priority: Int = 0,
    val skipReason: String? = null
)

data class SpeechQueueItem(
    val commentId: String,
    val text: String,
    val priority: Int,
    val createdAt: Long
)
