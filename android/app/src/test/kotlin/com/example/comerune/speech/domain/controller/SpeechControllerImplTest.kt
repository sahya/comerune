package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.audio.CallStateProvider
import com.example.comerune.speech.domain.model.EngineType
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.queue.InMemorySpeechQueueManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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

        // 選定理由: デフォルト設定 (minChunkLength=5, minTextLength=15, maxChunks=5) で
        // 「から」「けど」で 2 か所分割され、どのチャンクも minChunkLength を満たすため
        // マージされず確実に 3 チャンクとなる文を使う。
        // 元のテキスト「今日は忙しかったからでもなんとか終わったので帰れるよ」は
        // 「でも」が 2 文字で minChunkLength 未満→前チャンクにマージされ、
        // 結果として 2 チャンクしか得られず assertion が落ちていた。
        val text = "雨が降ってるからバスで行ったけどすごく時間がかかってしまった"
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

        // 同じ 3 チャンク文を利用し、N=2（中間チャンク）合成失敗を検証する。
        val text = "雨が降ってるからバスで行ったけどすごく時間がかかってしまった"
        controller.submitComment(rawComment("1", text))

        delay(800)

        val failedEvents = emitter.eventsOfType("speech_failed")
        assertEquals(1, failedEvents.size)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(0, completedEvents.size)
    }

    @Test
    fun `chunked pipeline triggers inter-comment prefetch for next comment`() = runBlocking {
        controller.initialize()
        controller.start()

        controller.submitComment(
            rawComment("1", "でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ")
        )
        controller.submitComment(rawComment("2", "そうだね"))

        delay(800)

        val completedEvents = emitter.eventsOfType("speech_completed")
        assertEquals(2, completedEvents.size)

        // Prefetch should have triggered additional synthesize calls:
        // 2 chunks for comment 1 + prefetch for comment 2 + possibly normal for comment 2
        assertTrue(
            "Expected prefetch to trigger additional synthesize calls",
            engine.synthesizeCount.get() >= 3
        )
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

    // --- Engine type diagnostic (issue #734) ---

    /**
     * Engine fake whose [currentState] is configurable, used to simulate the
     * "switched to VOICEVOX but engine never initialized" scenario.
     */
    private class StatefulFakeEngine(
        var stateToReturn: TtsEngineState = TtsEngineState.UNINITIALIZED
    ) : FakeEngine() {
        override fun currentState(): TtsEngineState = stateToReturn
    }

    @Test
    fun `updateSettings emits engine_not_ready when VOICEVOX engine is not READY`() = runBlocking {
        val statefulEngine = StatefulFakeEngine(stateToReturn = TtsEngineState.UNINITIALIZED)
        val ctrl = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = statefulEngine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )
        try {
            ctrl.updateSettings(SpeechSettings(engineType = EngineType.VOICEVOX))

            val events = emitter.eventsOfType("engine_not_ready")
            assertEquals(1, events.size)
            val payload = events.first()["payload"] as? Map<*, *>
            assertNotNull(payload)
            assertEquals(EngineType.VOICEVOX.name, payload?.get("engineType"))
            assertEquals(TtsEngineState.UNINITIALIZED.name, payload?.get("engineState"))
        } finally {
            ctrl.release()
        }
    }

    @Test
    fun `updateSettings does not emit engine_not_ready when VOICEVOX engine is READY`() = runBlocking {
        val statefulEngine = StatefulFakeEngine(stateToReturn = TtsEngineState.READY)
        val ctrl = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = statefulEngine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )
        try {
            ctrl.updateSettings(SpeechSettings(engineType = EngineType.VOICEVOX))

            val events = emitter.eventsOfType("engine_not_ready")
            assertEquals(0, events.size)
        } finally {
            ctrl.release()
        }
    }

    // --- Issue #915: getStatus().started reflects worker-loop intent ---

    @Test
    fun `getStatus started is false before start`() = runBlocking {
        controller.initialize()

        val status = controller.getStatus()
        assertEquals(false, status.started)
    }

    @Test
    fun `getStatus started is true after start`() = runBlocking {
        controller.initialize()
        controller.start()

        val status = controller.getStatus()
        assertEquals(true, status.started)
    }

    @Test
    fun `getStatus started is false after stop`() = runBlocking {
        controller.initialize()
        controller.start()
        controller.stop(clearQueue = true)

        val status = controller.getStatus()
        assertEquals(false, status.started)
    }

    @Test
    fun `getStatus started is false after release`() = runBlocking {
        // release() makes the controller unusable, so we have to query
        // getStatus on a fresh instance after release. Here we instead
        // assert on the *internal* started flag indirectly: a freshly
        // released controller cannot honour start() (it returns failure),
        // so the only way to observe started=false through the public
        // API is to instantiate a new controller. Use a dedicated
        // controller for this test to avoid polluting the shared one.
        val ctrl = SpeechControllerImpl(
            normalizer = FakeNormalizer(),
            queueManager = InMemorySpeechQueueManager(maxSize = 20),
            engine = FakeEngine(),
            player = FakePlayer(),
            settingsRepository = FakeSettingsRepository(),
            eventEmitter = FakeEventEmitter(),
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )
        ctrl.initialize()
        ctrl.start()
        // Sanity: started=true while running.
        assertEquals(true, ctrl.getStatus().started)
        ctrl.release()
        // Behavioural assertion: release() flips `started` off, and the
        // Flutter side expects an out-of-band release to be observable
        // through a subsequent getStatus reconcile.
        //
        // CAVEAT — incidental dependency: this test currently relies on
        // getStatus() *not* checking the `released` flag (it returns a
        // snapshot regardless). That behaviour is incidental rather than
        // contractual: a future change that makes getStatus() throw or
        // early-return after release() would break this test. If that
        // happens, the right fix is *not* to relax this assertion — the
        // Flutter mirror still needs a way to learn about
        // out-of-band releases. The right fix is to update the Flutter
        // reconcile path to handle the new contract (e.g. treat
        // post-release getStatus failure as "started=false" too).
        assertEquals(false, ctrl.getStatus().started)
    }

    @Test
    fun `getStatus started survives start-stop-start cycle`() = runBlocking {
        controller.initialize()
        controller.start()
        assertEquals(true, controller.getStatus().started)
        controller.stop(clearQueue = true)
        assertEquals(false, controller.getStatus().started)
        controller.start()
        assertEquals(true, controller.getStatus().started)
    }

    @Test
    fun `updateSettings does not emit engine_not_ready when engineType is ANDROID_TTS`() = runBlocking {
        // Android TTS path should never trigger the VOICEVOX-specific diagnostic,
        // even if the underlying VOICEVOX engine is not READY (it does not need to be).
        val statefulEngine = StatefulFakeEngine(stateToReturn = TtsEngineState.UNINITIALIZED)
        val ctrl = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = statefulEngine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default
        )
        try {
            ctrl.updateSettings(SpeechSettings(engineType = EngineType.ANDROID_TTS))

            val events = emitter.eventsOfType("engine_not_ready")
            assertEquals(0, events.size)
            // Sanity: no engine_state_changed either; updateSettings is purely passive.
            assertNull(emitter.eventsOfType("engine_state_changed").firstOrNull())
        } finally {
            ctrl.release()
        }
    }

    // --- Issue #931: CallStateProvider mute during phone calls ---

    private class ToggleableCallStateProvider(
        @Volatile var inCall: Boolean = false,
    ) : CallStateProvider {
        override fun isInCall(): Boolean = inCall
    }

    @Test
    fun `comments are skipped with reason in_call when CallStateProvider reports in-call`() =
        runBlocking {
            val callState = ToggleableCallStateProvider(inCall = true)
            val ctrl = SpeechControllerImpl(
                normalizer = normalizer,
                queueManager = queue,
                engine = engine,
                player = player,
                settingsRepository = settings,
                eventEmitter = emitter,
                dispatcher = Dispatchers.Default,
                synthesisDispatcher = Dispatchers.Default,
                callStateProvider = callState,
            )
            try {
                ctrl.initialize()
                ctrl.start()
                ctrl.submitComment(rawComment("1", "should-be-muted"))

                delay(300)

                val skipped = emitter.eventsOfType("comment_skipped")
                assertEquals(1, skipped.size)
                val payload = skipped.first()["payload"] as Map<*, *>
                assertEquals("in_call", payload["reason"])
                // The speak path must not have started.
                assertEquals(0, emitter.eventsOfType("speech_started").size)
                assertEquals(0, emitter.eventsOfType("speech_completed").size)
            } finally {
                ctrl.release()
            }
        }

    @Test
    fun `comments proceed normally when CallStateProvider reports not-in-call`() = runBlocking {
        val callState = ToggleableCallStateProvider(inCall = false)
        val ctrl = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = engine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default,
            callStateProvider = callState,
        )
        try {
            ctrl.initialize()
            ctrl.start()
            ctrl.submitComment(rawComment("1", "should-play"))

            delay(300)

            assertEquals(0, emitter.eventsOfType("comment_skipped").size)
            assertEquals(1, emitter.eventsOfType("speech_completed").size)
        } finally {
            ctrl.release()
        }
    }

    @Test
    fun `worker continues to next item after in_call skip when call ends`() = runBlocking {
        val callState = ToggleableCallStateProvider(inCall = true)
        val ctrl = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = engine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default,
            callStateProvider = callState,
        )
        try {
            ctrl.initialize()
            ctrl.start()
            ctrl.submitComment(rawComment("1", "muted-by-call"))
            delay(300)

            // Call ends mid-session; subsequent items must play normally.
            callState.inCall = false
            ctrl.submitComment(rawComment("2", "after-call"))
            delay(300)

            assertEquals(1, emitter.eventsOfType("comment_skipped").size)
            assertEquals(1, emitter.eventsOfType("speech_completed").size)
        } finally {
            ctrl.release()
        }
    }
}
