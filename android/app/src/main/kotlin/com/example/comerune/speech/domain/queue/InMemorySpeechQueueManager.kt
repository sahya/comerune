package com.example.comerune.speech.domain.queue

import com.example.comerune.speech.domain.model.QueueOfferResult
import com.example.comerune.speech.domain.model.SpeechQueueItem

/**
 * In-memory FIFO queue for speech items with max size control
 * and duplicate text rejection.
 */
class InMemorySpeechQueueManager(
    maxSize: Int = 20
) : SpeechQueueManager {

    init {
        require(maxSize > 0) { "maxSize must be positive, but was $maxSize" }
    }

    /**
     * Maximum number of items allowed in the queue.
     * Can be updated at runtime via [updateMaxSize].
     */
    @Volatile
    var currentMaxSize: Int = maxSize
        private set

    /**
     * Update the maximum queue size at runtime.
     * If the new size is smaller than the current queue length, existing items
     * are NOT evicted — the new limit applies only to future [offer] calls.
     */
    @Synchronized
    override fun updateMaxSize(newMaxSize: Int) {
        require(newMaxSize > 0) { "maxSize must be positive, but was $newMaxSize" }
        currentMaxSize = newMaxSize
    }

    private val queue = ArrayDeque<SpeechQueueItem>()

    @Synchronized
    override fun offer(item: SpeechQueueItem): QueueOfferResult {
        if (queue.any { it.text == item.text }) {
            return QueueOfferResult(accepted = false, reason = "queue_duplicate")
        }

        if (queue.size >= currentMaxSize) {
            return QueueOfferResult(accepted = false, reason = "queue_full")
        }

        queue.addLast(item)
        return QueueOfferResult(accepted = true)
    }

    @Synchronized
    override fun poll(): SpeechQueueItem? = queue.removeFirstOrNull()

    @Synchronized
    override fun peek(): SpeechQueueItem? = queue.firstOrNull()

    @Synchronized
    override fun clear() {
        queue.clear()
    }

    @Synchronized
    override fun size(): Int = queue.size

    @Synchronized
    override fun isEmpty(): Boolean = queue.isEmpty()
}
