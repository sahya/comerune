package app.spectacles_software.comerune.speech.domain.queue

import app.spectacles_software.comerune.speech.domain.model.QueueOfferResult
import app.spectacles_software.comerune.speech.domain.model.SpeechQueueItem

interface SpeechQueueManager {
    fun offer(item: SpeechQueueItem): QueueOfferResult
    fun poll(): SpeechQueueItem?
    fun peek(): SpeechQueueItem?
    fun clear()
    fun size(): Int
    fun isEmpty(): Boolean

    /**
     * Update the maximum queue size at runtime.
     */
    fun updateMaxSize(newMaxSize: Int)
}
