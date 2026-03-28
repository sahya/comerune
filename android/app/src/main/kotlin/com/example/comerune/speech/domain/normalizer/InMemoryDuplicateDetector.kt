package com.example.comerune.speech.domain.normalizer

/**
 * In-memory duplicate detector that suppresses:
 * 1. Exact same text posted within the time window
 * 2. Rapid-fire posts from the same userId within the time window
 *
 * Thread-safe via @Synchronized. History is bounded to [maxEntries].
 */
class InMemoryDuplicateDetector(
    private val duplicateWindowMs: Long = DEFAULT_WINDOW_MS,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
    private val timeProvider: () -> Long = System::currentTimeMillis
) : DuplicateDetector {

    private data class Entry(
        val normalizedText: String,
        val userId: String?,
        val timestampMs: Long
    )

    private val history = mutableListOf<Entry>()

    @Synchronized
    override fun isDuplicate(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean {
        evict(currentTimeMs)

        for (entry in history) {
            val withinWindow = (currentTimeMs - entry.timestampMs) < duplicateWindowMs

            if (!withinWindow) continue

            // Rule 1: Exact text match within window
            if (entry.normalizedText == normalizedText) {
                return true
            }

            // Rule 2: Same userId rapid-fire within window
            if (userId != null && entry.userId == userId) {
                return true
            }
        }

        return false
    }

    @Synchronized
    override fun record(normalizedText: String, userId: String?, currentTimeMs: Long) {
        evict(currentTimeMs)

        // Enforce max entries by removing oldest if at capacity
        while (history.size >= maxEntries) {
            history.removeAt(0)
        }

        history.add(Entry(normalizedText, userId, currentTimeMs))
    }

    @Synchronized
    override fun checkAndRecord(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean {
        if (isDuplicate(normalizedText, userId, currentTimeMs)) {
            return true
        }
        record(normalizedText, userId, currentTimeMs)
        return false
    }

    @Synchronized
    override fun clear() {
        history.clear()
    }

    private fun evict(currentTimeMs: Long) {
        history.removeAll { (currentTimeMs - it.timestampMs) >= duplicateWindowMs }
    }

    companion object {
        const val DEFAULT_WINDOW_MS = 5000L
        const val DEFAULT_MAX_ENTRIES = 50
    }
}
