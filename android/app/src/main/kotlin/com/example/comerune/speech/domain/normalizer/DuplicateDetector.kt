package com.example.comerune.speech.domain.normalizer

interface DuplicateDetector {
    fun isDuplicate(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean
    fun record(normalizedText: String, userId: String?, currentTimeMs: Long)
    fun clear()
}
