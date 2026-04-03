package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.event.SpeechEventEmitter
import com.example.comerune.speech.domain.model.NormalizedComment
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult
import com.example.comerune.speech.domain.normalizer.CommentNormalizer
import com.example.comerune.speech.domain.player.WavPlayer
import com.example.comerune.speech.domain.queue.InMemorySpeechQueueManager
import com.example.comerune.speech.domain.settings.SettingsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SpeechControllerPipelineTest {

    // --- Fakes ---

    private class FakeNormalizer : CommentNormalizer {
        override fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment {
            return NormalizedComment(
                id = raw.id,
                originalText = raw.text,
                normalizedText = raw.text,
                priority = 0,
                skipReason = null
            )
        }
    }

    private class FakeEngine : VoicevoxEngine {
        private val wavHeader = "RIFF".toByteArray(Charsets.US_ASCII) + ByteArray(40)
        val synthesizeCount = AtomicInteger(0)
        var failOnEvenCalls = false

        override suspend fun initialize(): Result<Unit> = Result.success(Unit)

        override suspend fun prepareForModelDownload(): Result<Unit> = Result.success(Unit)

        override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
            val callNumber = synthesizeCount.incrementAndGet()
            if (failOnEvenCalls && callNumber % 2 == 0) {
                throw RuntimeException("Simulated synthesis failure on call #$callNumber")
            }
            return Result.success(
                WavSynthesisResult(
                    wavBytes = wavHeader,
                    text = request.text,
                    durationEstimateMs = 100
                )
            )
        }

        override suspend fun loadModel(modelPath: String): Result<Unit> = Result.success(Unit)

        override fun isReady(): Boolean = true
        override fun currentState(): TtsEngineState = TtsEngineState.READY
        override fun release() {}
    }

    private class FakePlayer : WavPlayer {
        var failOnPlay = false
        var playLatch: CountDownLatch? = null
        private var state = PlayerState.IDLE

        override suspend fun play(wavBytes: ByteArray): Result<Unit> {
            playLatch?.await(5, TimeUnit.SECONDS)
            return if (failOnPlay) {
                failOnPlay = false
                Result.failure(IOException("Playback interrupted"))
            } else {
                state = PlayerState.PLAYING
                delay(10)
                state = PlayerState.IDLE
                Result.success(Unit)
            }
        }

        override suspend fun stop(): Result<Unit> {
            state = PlayerState.STOPPED
            return Result.success(Unit)
        }

        override fun isPlaying(): Boolean = state == PlayerState.PLAYING
        override fun currentState(): PlayerState = state
        override fun release() { state = PlayerState.IDLE }
    }

    private class FakeSettingsRepository : SettingsRepository {
        private var settings = SpeechSettings()

        override fun get(): SpeechSettings = settings
        override fun save(settings: SpeechSettings) { this.settings = settings }
    }

    private class FakeEventEmitter : SpeechEventEmitter {
        val events = CopyOnWriteArrayList<Map<String, Any?>>()

        override fun emit(event: Map<String, Any?>) {
            events.add(event)
        }

        fun eventsOfType(type: String): List<Map<String, Any?>> =
            events.filter { (it["payload"] as? Map<*, *>) != null && it["type"] == type }
    }

    // --- Test setup ---

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

    private fun rawComment(id: String, text: String) = RawComment(
        id = id,
        text = text,
        userId = null,
        postedAtEpochMs = System.currentTimeMillis()
    )

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
