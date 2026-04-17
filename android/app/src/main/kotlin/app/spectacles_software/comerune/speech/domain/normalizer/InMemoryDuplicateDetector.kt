package app.spectacles_software.comerune.speech.domain.normalizer

/**
 * In-memory duplicate detector that suppresses exact same text posted
 * within the time window, regardless of which user posted it.
 *
 * Same-user different-text posts are NOT suppressed — this is strictly
 * a duplicate detector, not a rate limiter.
 *
 * Thread-safe via @Synchronized. History is bounded to [maxEntries]
 * and backed by [ArrayDeque] for O(1) removal from front.
 */
class InMemoryDuplicateDetector(
    duplicateWindowMs: Long = DEFAULT_WINDOW_MS,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
    private val timeProvider: () -> Long = System::currentTimeMillis
) : DuplicateDetector {

    /**
     * The time window (in milliseconds) within which identical text is
     * considered a duplicate. Can be updated at runtime
     * via [updateDuplicateWindowMs].
     */
    @Volatile
    var currentDuplicateWindowMs: Long = duplicateWindowMs
        private set

    /**
     * Update the duplicate detection window at runtime.
     * Takes effect on the next [isDuplicate] / [checkAndRecord] call.
     */
    @Synchronized
    override fun updateDuplicateWindowMs(ms: Long) {
        currentDuplicateWindowMs = ms
    }

    private data class Entry(
        val normalizedText: String,
        val userId: String?,
        val timestampMs: Long
    )

    private val history = ArrayDeque<Entry>()

    @Synchronized
    override fun isDuplicate(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean {
        evict(currentTimeMs)
        return isDuplicateInternal(normalizedText, currentTimeMs)
    }

    @Synchronized
    override fun record(normalizedText: String, userId: String?, currentTimeMs: Long) {
        evict(currentTimeMs)
        recordInternal(normalizedText, userId, currentTimeMs)
    }

    @Synchronized
    override fun checkAndRecord(normalizedText: String, userId: String?, currentTimeMs: Long): Boolean {
        evict(currentTimeMs)
        if (isDuplicateInternal(normalizedText, currentTimeMs)) {
            return true
        }
        recordInternal(normalizedText, userId, currentTimeMs)
        return false
    }

    /**
     * Check for duplicates without evicting expired entries.
     * Caller must call [evict] before invoking this method.
     */
    private fun isDuplicateInternal(normalizedText: String, currentTimeMs: Long): Boolean {
        for (entry in history) {
            val withinWindow = (currentTimeMs - entry.timestampMs) < currentDuplicateWindowMs
            if (!withinWindow) continue

            // Exact text match within window (any user)
            if (entry.normalizedText == normalizedText) {
                return true
            }
        }
        return false
    }

    /**
     * Record an entry without evicting expired entries.
     * Caller must call [evict] before invoking this method.
     */
    private fun recordInternal(normalizedText: String, userId: String?, currentTimeMs: Long) {
        // Enforce max entries by removing oldest if at capacity
        while (history.size >= maxEntries) {
            history.removeFirst()
        }
        history.addLast(Entry(normalizedText, userId, currentTimeMs))
    }

    @Synchronized
    override fun clear() {
        history.clear()
    }

    /**
     * Remove expired entries from the front of the deque.
     * Because entries are appended in chronological order, all expired
     * entries are contiguous at the front, giving O(k) removal for k
     * expired items with O(1) per removal.
     */
    private fun evict(currentTimeMs: Long) {
        while (history.isNotEmpty() &&
            (currentTimeMs - history.first().timestampMs) >= currentDuplicateWindowMs
        ) {
            history.removeFirst()
        }
    }

    companion object {
        const val DEFAULT_WINDOW_MS = 5000L
        const val DEFAULT_MAX_ENTRIES = 50
    }
}
