package com.example.comerune.speech.domain.model

data class QueueOfferResult(
    val accepted: Boolean,
    val reason: String? = null
)
