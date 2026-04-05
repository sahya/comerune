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
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
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

        delay(500)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(3, completedEvents.size)
    }

    @Test
    fun `worker continues to next item after playback failure`() = runBlocking {
        controller.initialize()
        controller.start()

        player.failOnPlay = true

        controller.submitComment(rawComment("1", "will-fail"))
        controller.submitComment(rawComment("2", "should-succeed"))

        delay(500)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }

    @Test
    fun `worker restarts when new item submitted after queue was empty`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(rawComment("1", "first"))
        delay(300)

        val completedBefore = emitter.eventsOfType("speech_completed").size
        assertEquals(1, completedBefore)

        controller.submitComment(rawComment("2", "second"))
        delay(300)

        val completedAfter = emitter.eventsOfType("speech_completed").size
        assertEquals(2, completedAfter)
    }

    @Test
    fun `skip during playback allows next item to be processed`() = runBlocking {
        controller.initialize()
        controller.start()

        val latch = CountDownLatch(1)
        player.playLatch = latch

        controller.submitComment(rawComment("1", "first"))
        controller.submitComment(rawComment("2", "second"))

        delay(100)

        controller.skip()
        latch.countDown()
        player.playLatch = null

        delay(500)

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

        controller.submitComment(rawComment("2", "while-stopped"))

        controller.start()
        delay(300)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(2, completedEvents.size)
    }

    @Test
    fun `worker survives unexpected exception in processItem`() = runBlocking {
        controller.initialize()
        controller.start()

        engine.throwOnSynthesize = true

        controller.submitComment(rawComment("1", "will-throw"))
        controller.submitComment(rawComment("2", "should-succeed"))

        delay(500)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }

    // --- Chunked pipeline tests ---

    @Test
    fun `long text with particle is split and synthesized as multiple chunks`() = runBlocking {
        controller.initialize()
        controller.start()

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        assertEquals(2, engine.synthesizedTexts.size)
        assertEquals("でも岩国は今豪雨らしいから", engine.synthesizedTexts[0])
        assertEquals("これぐらいの雨でまだよかったよ", engine.synthesizedTexts[1])

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }

    @Test
    fun `short text is not split`() = runBlocking {
        controller.initialize()
        controller.start()

        val text = "こんにちは"
        controller.submitComment(rawComment("1", text))

        delay(500)

        assertTrue(engine.synthesizedTexts.size >= 1)
        assertEquals(text, engine.synthesizedTexts[0])
    }

    @Test
    fun `chunked pipeline emits single speech_started event`() = runBlocking {
        controller.initialize()
        controller.start()

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        val startedEvents = emitter.eventsOfType("speech_started")
        assertEquals(1, startedEvents.size)
    }

    @Test
    fun `chunked pipeline with playback failure on first chunk emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        player.failOnPlay = true

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `chunked pipeline with synthesis failure on second chunk emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        engine.failOnNthSynthesize = 2

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `three chunk text synthesizes all chunks in order`() = runBlocking {
        controller.initialize()
        controller.start()

        val text = "今日は忙しかったからでもなんとか終わったので帰れるよ"
        controller.submitComment(rawComment("1", text))

        delay(800)

        assertEquals(3, engine.synthesizedTexts.size)
        assertEquals(text, engine.synthesizedTexts.joinToString(""))
        assertTrue(text.startsWith(engine.synthesizedTexts[0]))

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(1, completedEvents.size)
    }

    @Test
    fun `three chunk pipeline with middle chunk synthesis failure emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        engine.failOnNthSynthesize = 2

        val text = "今日は忙しかったからでもなんとか終わったので帰れるよ"
        controller.submitComment(rawComment("1", text))

        delay(800)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `chunked pipeline continues to next comment after completion`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(
            rawComment("1", "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ")
        )
        controller.submitComment(rawComment("2", "そうだね"))

        delay(800)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(2, completedEvents.size)
    }

    @Test
    fun `skip during chunked playback allows next comment to be processed`() = runBlocking {
        controller.initialize()
        controller.start()

        val latch = CountDownLatch(1)
        player.playLatch = latch

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))
        controller.submitComment(rawComment("2", "次のコメント"))

        delay(100)

        controller.skip()
        latch.countDown()
        player.playLatch = null

        delay(800)

        val startedEvents = emitter.eventsOfType("speech_started")
        assertTrue("Expected at least 2 speech_started events", startedEvents.size >= 2)
    }
}
