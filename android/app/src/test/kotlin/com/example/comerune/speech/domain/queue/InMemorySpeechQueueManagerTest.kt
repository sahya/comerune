package com.example.comerune.speech.domain.queue

import com.example.comerune.speech.domain.model.QueueOfferResult
import com.example.comerune.speech.domain.model.SpeechQueueItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class InMemorySpeechQueueManagerTest {

    private lateinit var queue: InMemorySpeechQueueManager

    @Before
    fun setUp() {
        queue = InMemorySpeechQueueManager(maxSize = 3)
    }

    private fun item(text: String, id: String = text): SpeechQueueItem =
        SpeechQueueItem(commentId = id, text = text, priority = 0, createdAt = System.currentTimeMillis())

    // --- FIFO ordering ---

    @Test
    fun `poll returns items in FIFO order`() {
        queue.offer(item("first"))
        queue.offer(item("second"))
        queue.offer(item("third"))

        assertEquals("first", queue.poll()?.text)
        assertEquals("second", queue.poll()?.text)
        assertEquals("third", queue.poll()?.text)
    }

    // --- maxSize rejection ---

    @Test
    fun `offer rejects with queue_full when at max capacity`() {
        queue.offer(item("a"))
        queue.offer(item("b"))
        queue.offer(item("c"))

        val result = queue.offer(item("d"))
        assertFalse(result.accepted)
        assertEquals("queue_full", result.reason)
        assertEquals(3, queue.size())
    }

    // --- Duplicate text rejection ---

    @Test
    fun `offer rejects duplicate text with queue_duplicate`() {
        queue.offer(item("hello", id = "id1"))

        val result = queue.offer(item("hello", id = "id2"))
        assertFalse(result.accepted)
        assertEquals("queue_duplicate", result.reason)
        assertEquals(1, queue.size())
    }

    @Test
    fun `offer accepts same text after previous one is polled`() {
        queue.offer(item("hello"))
        queue.poll()

        val result = queue.offer(item("hello", id = "id2"))
        assertTrue(result.accepted)
    }

    // --- clear ---

    @Test
    fun `clear empties the queue`() {
        queue.offer(item("a"))
        queue.offer(item("b"))

        queue.clear()
        assertTrue(queue.isEmpty())
        assertEquals(0, queue.size())
    }

    // --- poll on empty ---

    @Test
    fun `poll on empty queue returns null`() {
        assertNull(queue.poll())
    }

    // --- updateMaxSize ---

    @Test
    fun `updateMaxSize allows more items after increase`() {
        queue.offer(item("a"))
        queue.offer(item("b"))
        queue.offer(item("c"))

        // At capacity, next offer rejected
        val rejected = queue.offer(item("d"))
        assertFalse(rejected.accepted)

        // Increase max size
        queue.updateMaxSize(5)

        val accepted = queue.offer(item("d"))
        assertTrue(accepted.accepted)
        assertEquals(4, queue.size())
    }

    @Test
    fun `updateMaxSize does not evict existing items when decreased`() {
        queue.offer(item("a"))
        queue.offer(item("b"))
        queue.offer(item("c"))

        queue.updateMaxSize(1)

        // Existing items are kept
        assertEquals(3, queue.size())

        // But new items are rejected
        val result = queue.offer(item("d"))
        assertFalse(result.accepted)
        assertEquals("queue_full", result.reason)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `updateMaxSize rejects zero`() {
        queue.updateMaxSize(0)
    }

    @Test(expected = IllegalArgumentException::class)
    fun `constructor rejects zero maxSize`() {
        InMemorySpeechQueueManager(maxSize = 0)
    }

    // --- Accepted offer returns correct result ---

    @Test
    fun `successful offer returns accepted true with no reason`() {
        val result = queue.offer(item("hello"))
        assertTrue(result.accepted)
        assertNull(result.reason)
    }
}
