package com.example.comerune.speech.domain.model

data class SpeechQueueItem(
    val commentId: String,
    val text: String,
    val priority: Int,
    val createdAt: Long
)
