package com.example.comerune.speech.domain.normalizer

interface DuplicateDetector {
    fun isDuplicate(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean
    fun record(normalizedText: String, userId: String?, currentTimeMs: Long)

    /**
     * Atomically checks if the text is a duplicate and, if not, records it.
     * Returns true if the text is a duplicate (i.e., should be skipped).
     */
    fun checkAndRecord(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean

    fun clear()

    /**
     * Update the duplicate detection window at runtime.
     * Takes effect on the next [isDuplicate] / [checkAndRecord] call.
     */
    fun updateDuplicateWindowMs(ms: Long)
}
