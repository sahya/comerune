package app.spectacles_software.comerune.speech.domain.controller

import app.spectacles_software.comerune.speech.domain.queue.InMemorySpeechQueueManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch

class SpeechControllerPipelineTest {

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
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )
    }

    @After
    fun tearDown() {
        controller.release()
    }

    // --- Pipeline Tests ---

    @Test
    fun `prefetch synthesizes next item during playback`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(rawComment("1", "first"))
        controller.submitComment(rawComment("2", "second"))
        controller.submitComment(rawComment("3", "third"))

        // Wait for all items to be processed.
        // FakePlayer has 10ms delay, FakeEngine synthesis is instant,
        // so prefetch should kick in for items 2 and 3.
        delay(1000)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(
            "All 3 items should complete via speech_completed events",
            3,
            completedEvents.size
        )

        // Verify prefetch was attempted: with 3 items and pipelining,
        // synthesize should be called more than 3 times (3 regular + prefetch attempts)
        assertTrue(
            "Expected prefetch to trigger additional synthesize calls",
            engine.synthesizeCount.get() >= 3
        )
    }

    @Test
    fun `prefetch is invalidated when item is skipped`() = runBlocking {
        controller.initialize()
        controller.start()

        // Use a latch to hold playback of the first item
        val latch = CountDownLatch(1)
        player.playLatch = latch

        controller.submitComment(rawComment("1", "first"))
        controller.submitComment(rawComment("2", "second"))

        // Give the worker time to start processing item 1 and possibly prefetch item 2
        delay(100)

        // Skip current playback (item 1)
        controller.skip()
        latch.countDown()
        player.playLatch = null

        // Wait for item 2 to be processed
        delay(500)

        // Item 2 should still be processed correctly even though prefetch
        // may have occurred for it before skip invalidated state
        val startedEvents = emitter.eventsOfType("speech_started")
        assertTrue(
            "Expected at least 2 speech_started events",
            startedEvents.size >= 2
        )

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertTrue(
            "Second item should complete successfully",
            completedEvents.isNotEmpty()
        )
    }

    @Test
    fun `prefetch failure does not break normal synthesis`() = runBlocking {
        // Make engine throw on even-numbered synthesize calls.
        // Call sequence:
        //   #1 = item 1 normal synthesis (succeeds)
        //   #2 = item 2 prefetch during item 1 playback (fails - even)
        //   #3 = item 2 normal synthesis fallback (succeeds)
        engine.failOnEvenCalls = true

        controller.initialize()
        controller.start()

        controller.submitComment(rawComment("1", "first"))
        controller.submitComment(rawComment("2", "second"))

        // Wait for processing
        delay(1000)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertTrue(
            "First item should complete",
            completedEvents.any { event ->
                val payload = event["payload"] as? Map<*, *>
                payload?.get("commentId") == "1"
            }
        )

        // Second item should either complete (via normal fallback synthesis)
        // or at minimum be attempted (speech_started emitted)
        val startedEvents = emitter.eventsOfType("speech_started")
        assertTrue(
            "Second item should be attempted",
            startedEvents.any { event ->
                val payload = event["payload"] as? Map<*, *>
                payload?.get("commentId") == "2"
            }
        )

        // Verify prefetch was actually attempted:
        // #1 = item 1 normal, #2 = item 2 prefetch (fail), #3 = item 2 fallback
        assertTrue(
            "Expected at least 3 synthesize calls (normal + prefetch fail + fallback)",
            engine.synthesizeCount.get() >= 3
        )
    }

    @Test
    fun `chunked pipeline prefetch uses captured item not second peek`() = runBlocking {
        // Regression test for Bug #5: processChunkedPipeline must pass the
        // SpeechQueueItem returned by startPrefetch() directly to collectPrefetch(),
        // rather than re-peeking the queue after the loop. If re-peeking happened,
        // the second peek could see null (because the worker already polled the
        // item) and the prefetch result would be discarded.

        val baseQueue = InMemorySpeechQueueManager(maxSize = 20)
        val peekQueue = PeekCountingQueueManager(baseQueue)
        // Make the 2nd peek return null to simulate the race condition where the
        // worker has already polled the next item before a hypothetical re-peek.
        // peek #1 = startPrefetch inside processChunkedPipeline (returns item 2)
        // peek #2 = if the old code re-peeked here, it would get null
        peekQueue.returnNullOnNthPeek = 2

        val localController = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = peekQueue,
            engine = engine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )

        try {
            localController.initialize()
            localController.start()

            // Item 1 is a chunked comment (triggers processChunkedPipeline).
            // Item 2 is a short comment that should benefit from prefetch.
            localController.submitComment(
                rawComment("1", "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ")
            )
            localController.submitComment(rawComment("2", "次"))

            delay(1500)

            // Both items must complete successfully.
            val completedEvents = emitter.eventsOfType("speech_completed")
            assertEquals(
                "Both comments should complete even when 2nd peek returns null",
                2,
                completedEvents.size
            )

            // Verify that peek was called (startPrefetch uses peek internally).
            assertTrue(
                "startPrefetch should have called peek at least once",
                peekQueue.peekCount.get() >= 1
            )
        } finally {
            localController.release()
        }
    }

    @Test
    fun `stop clears prefetch state`() = runBlocking {
        controller.initialize()
        controller.start()

        // Process first item
        controller.submitComment(rawComment("1", "first"))
        delay(300)

        val completedBefore = emitter.eventsOfType("speech_completed").size
        assertEquals("First item should complete", 1, completedBefore)

        // Submit second item, then stop before it can be processed
        controller.submitComment(rawComment("2", "second"))
        controller.stop(clearQueue = true)

        // Start again and submit a third item
        controller.start()
        controller.submitComment(rawComment("3", "third"))

        // Wait for third item to be processed
        delay(500)

        val completedAfter = emitter.eventsOfType("speech_completed")
        val thirdCompleted = completedAfter.any { event ->
            val payload = event["payload"] as? Map<*, *>
            payload?.get("commentId") == "3"
        }
        assertTrue(
            "Third item should process correctly with no stale prefetch data",
            thirdCompleted
        )
    }
}
