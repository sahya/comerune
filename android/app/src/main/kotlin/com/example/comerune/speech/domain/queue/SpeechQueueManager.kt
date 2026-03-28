package com.example.comerune.speech.domain.queue

import com.example.comerune.speech.domain.model.QueueOfferResult
import com.example.comerune.speech.domain.model.SpeechQueueItem

interface SpeechQueueManager {
    fun offer(item: SpeechQueueItem): QueueOfferResult
    fun poll(): SpeechQueueItem?
    fun peek(): SpeechQueueItem?
    fun clear()
    fun size(): Int
    fun isEmpty(): Boolean
}
