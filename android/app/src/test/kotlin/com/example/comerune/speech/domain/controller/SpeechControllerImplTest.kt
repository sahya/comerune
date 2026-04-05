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
import com.example.comerune.speech.domain.splitter.JapaneseTextSplitter
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

class SpeechControllerImplTest {

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
        var throwOnSynthesize = false
        /** When set to N > 0, the N-th call to synthesize() will throw. */
        var failOnNthSynthesize = 0
        private var synthesizeCallCount = 0
        val synthesizedTexts = CopyOnWriteArrayList<String>()

        override suspend fun initialize(): Result<Unit> = Result.success(Unit)

        override suspend fun prepareForModelDownload(): Result<Unit> = Result.success(Unit)

        override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
            synthesizeCallCount++
            if (throwOnSynthesize) {
                throwOnSynthesize = false
                throw RuntimeException("Unexpected engine error")
            }
            if (failOnNthSynthesize > 0 && synthesizeCallCount == failOnNthSynthesize) {
                throw RuntimeException("Synthesis failed on call #$synthesizeCallCount")
            }
            synthesizedTexts.add(request.text)
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

    /**
     * Fake player that tracks play calls. When [failOnPlay] is set, play()
     * returns a failure (simulating interrupted playback from stopInternal).
     */
    private class FakePlayer : WavPlayer {
        var failOnPlay = false
        var playLatch: CountDownLatch? = null
        private var state = PlayerState.IDLE

        override suspend fun play(wavBytes: ByteArray): Result<Unit> {
            playLatch?.await(5, TimeUnit.SECONDS)
            return if (failOnPlay) {
                failOnPlay = false // fail only once
                Result.failure(IOException("Playback interrupted"))
            } else {
                state = PlayerState.PLAYING
                // Simulate brief playback
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
            dispatcher = Dispatchers.Default
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

    // --- Chunked pipeline tests ---

    @Test
    fun `long text with particle is split and synthesized as multiple chunks`() = runBlocking {
        controller.initialize()
        controller.start()

        // This text contains "から" — should be split into 2 chunks
        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        // Should have synthesized 2 chunks separately
        assertEquals(2, engine.synthesizedTexts.size)
        assertEquals("でも岩国は今豪雨らしいから", engine.synthesizedTexts[0])
        assertEquals("これぐらいの雨でまだよかったよ", engine.synthesizedTexts[1])

        // But only one speech_completed event for the whole comment
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

        // Single synthesis call
        assertEquals(1, engine.synthesizedTexts.size)
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

        // No completed event should be emitted
        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `chunked pipeline with synthesis failure on second chunk emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        // Fail on the 2nd synthesize call (= second chunk)
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
    fun `chunked pipeline with synthesis failure on first chunk emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        // Fail on the 1st synthesize call (= first chunk)
        engine.failOnNthSynthesize = 1

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        delay(500)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `chunked pipeline playback failure on second chunk emits speech_failed`() = runBlocking {
        controller.initialize()
        controller.start()

        // Let the first chunk play normally, then fail on the second play.
        // Submit text, then toggle failOnPlay after first play completes.

        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))

        // Give time for first chunk to synthesize and start playing
        delay(50)
        // Set failOnPlay so next play call fails (second chunk)
        player.failOnPlay = true

        delay(500)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `skip during chunked playback allows next comment to be processed`() = runBlocking {
        controller.initialize()
        controller.start()

        // Use a latch to hold playback of the first chunk
        val latch = CountDownLatch(1)
        player.playLatch = latch

        // Submit a long (chunked) comment and a short one
        val text = "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ"
        controller.submitComment(rawComment("1", text))
        controller.submitComment(rawComment("2", "次のコメント"))

        // Give the worker time to start processing the first chunk
        delay(100)

        // Skip current playback
        controller.skip()
        latch.countDown()
        player.playLatch = null

        delay(800)

        // The second comment should have been processed
        val startedEvents = emitter.eventsOfType("speech_started")
        assertTrue("Expected at least 2 speech_started events", startedEvents.size >= 2)
    }

    @Test
    fun `chunked pipeline continues to next comment after completion`() = runBlocking {
        controller.initialize()
        controller.start()

        // First comment — chunked
        controller.submitComment(
            rawComment("1", "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ")
        )
        // Second comment — short (no split)
        controller.submitComment(rawComment("2", "そうだね"))

        delay(800)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(2, completedEvents.size)
    }
}
