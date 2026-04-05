package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.queue.InMemorySpeechQueueManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch

class SpeechControllerImplTest {

    private lateinit var normalizer: FakeNormalizer
    private lateinit var queue: InMemorySpeechQueueManager
    private lateinit var engine: FakeEngine
    private lateinit var player: FakePlayer
    private lateinit var settings: FakeSettingsRepository
    private lateinit var emitter: FakeEventEmitter
    private lateinit var controller: SpeechControllerImpl

    @Before
    fun setUp() {
        normalizer = FakeNormalizer()
        queue = InMemorySpeechQueueManager(maxSize = 20)
        engine = FakeEngine()
        player = FakePlayer()
        settings = FakeSettingsRepository()
        emitter = FakeEventEmitter()
        controller = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = engine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default
        )
    }

    @After
    fun tearDown() {
        controller.release()
    }

    // --- Tests ---

    @Test
    fun `worker processes all queued items`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(rawComment("1", "hello"))
        controller.submitComment(rawComment("2", "world"))
        controller.submitComment(rawComment("3", "test"))

        // Wait for worker to process
        delay(500)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(3, completedEvents.size)
    }

    @Test
    fun `worker continues to next item after playback failure`() = runBlocking {
        controller.initialize()
        controller.start()

        // First item will fail playback (simulating interrupted playback)
        player.failOnPlay = true

        controller.submitComment(rawComment("1", "will-fail"))
        controller.submitComment(rawComment("2", "should-succeed"))

        delay(500)

        // First item should have a speech_failed event
        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        // Second item should still be processed successfully
        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }

    @Test
    fun `worker restarts when new item submitted after queue was empty`() = runBlocking {
        controller.initialize()
        controller.start()

        // Submit and let it process
        controller.submitComment(rawComment("1", "first"))
        delay(300)

        val completedBefore = emitter.eventsOfType("speech_completed").size
        assertEquals(1, completedBefore)

        // Submit after queue was emptied — worker should restart
        controller.submitComment(rawComment("2", "second"))
        delay(300)

        val completedAfter = emitter.eventsOfType("speech_completed").size
        assertEquals(2, completedAfter)
    }

    @Test
    fun `skip during playback allows next item to be processed`() = runBlocking {
        controller.initialize()
        controller.start()

        // Use a latch to hold playback so we can skip during it
        val latch = CountDownLatch(1)
        player.playLatch = latch

        controller.submitComment(rawComment("1", "first"))
        controller.submitComment(rawComment("2", "second"))

        // Give the worker time to start processing the first item
        delay(100)

        // Skip current playback
        controller.skip()
        latch.countDown()
        player.playLatch = null

        delay(500)

        // Both items should have been attempted (first failed/skipped, second succeeded)
        val startedEvents = emitter.eventsOfType("speech_started")
        assertTrue("Expected at least 2 speech_started events", startedEvents.size >= 2)
    }

    @Test
    fun `stop then start resumes processing`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(rawComment("1", "before-stop"))
        delay(300)

        controller.stop(clearQueue = false)

        // Submit while stopped (won't be processed immediately)
        controller.submitComment(rawComment("2", "while-stopped"))

        // Restart
        controller.start()
        delay(300)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(2, completedEvents.size)
    }

    @Test
    fun `worker survives unexpected exception in processItem`() = runBlocking {
        controller.initialize()
        controller.start()

        // First item will throw an unexpected exception during synthesis
        engine.throwOnSynthesize = true

        controller.submitComment(rawComment("1", "will-throw"))
        controller.submitComment(rawComment("2", "should-succeed"))

        delay(500)

        // Second item should still be processed successfully despite first throwing
        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }
}
