package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.event.SpeechEventEmitter
import com.example.comerune.speech.domain.model.NormalizedComment
import com.example.comerune.speech.domain.model.PlayerState
import com.example.comerune.speech.domain.model.QueueOfferResult
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechQueueItem
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult
import com.example.comerune.speech.domain.normalizer.CommentNormalizer
import com.example.comerune.speech.domain.player.TtsSpeakException
import com.example.comerune.speech.domain.player.TtsSpeaker
import com.example.comerune.speech.domain.player.WavPlayer
import com.example.comerune.speech.domain.queue.SpeechQueueManager
import com.example.comerune.speech.domain.settings.SettingsRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Shared test fakes for SpeechController tests. */

open class FakeNormalizer : CommentNormalizer {
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

open class FakeEngine : VoicevoxEngine {
    val wavHeader: ByteArray = "RIFF".toByteArray(Charsets.US_ASCII) + ByteArray(40)
    val synthesizeCount = AtomicInteger(0)
    val synthesizedTexts = CopyOnWriteArrayList<String>()
    var throwOnSynthesize = false
    var failOnEvenCalls = false
    /** When set to N > 0, the N-th call to synthesize() will throw. */
    var failOnNthSynthesize = 0

    /**
     * Tracks model IDs that are considered "loaded" by this fake engine.
     * When non-null, [loadModel] and [clearLoadedModel] track state,
     * and [synthesize] checks that the model for the speaker is loaded.
     * When null (default), tracking is disabled for backward compatibility.
     */
    var trackedLoadedModels: MutableSet<String>? = null

    /** Records all modelIds passed to [loadModel], including duplicates. */
    val loadModelCalls = CopyOnWriteArrayList<String>()

    /** Records all modelIds passed to [clearLoadedModel]. */
    val clearLoadedModelCalls = CopyOnWriteArrayList<String>()

    /** When true, [loadModel] returns failure. */
    var failOnLoadModel = false

    override suspend fun initialize(): Result<Unit> = Result.success(Unit)

    override suspend fun prepareForModelDownload(): Result<Unit> = Result.success(Unit)

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
        val callNumber = synthesizeCount.incrementAndGet()
        if (throwOnSynthesize) {
            throwOnSynthesize = false
            throw RuntimeException("Unexpected engine error")
        }
        if (failOnNthSynthesize > 0 && callNumber == failOnNthSynthesize) {
            throw RuntimeException("Synthesis failed on call #$callNumber")
        }
        if (failOnEvenCalls && callNumber % 2 == 0) {
            throw RuntimeException("Simulated synthesis failure on call #$callNumber")
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

    override suspend fun loadModel(modelPath: String): Result<Unit> {
        // Extract a simple model ID from the path (filename without extension)
        val modelId = modelPath.substringAfterLast("/").substringBeforeLast(".")
            .ifBlank { modelPath }
        loadModelCalls.add(modelId)
        if (failOnLoadModel) {
            failOnLoadModel = false
            return Result.failure(RuntimeException("Failed to load model: $modelPath"))
        }
        trackedLoadedModels?.add(modelId)
        return Result.success(Unit)
    }

    override fun clearLoadedModel(modelId: String) {
        clearLoadedModelCalls.add(modelId)
        trackedLoadedModels?.remove(modelId)
    }

    /** Check whether a model is tracked as loaded. Returns true if tracking is disabled (null). */
    fun isModelTracked(modelId: String): Boolean =
        trackedLoadedModels?.contains(modelId) ?: true

    override fun isReady(): Boolean = true
    override fun currentState(): TtsEngineState = TtsEngineState.READY
    override fun release() {}
}

open class FakePlayer : WavPlayer {
    var failOnPlay = false
    var playLatch: CountDownLatch? = null
    private var state = PlayerState.IDLE

    @Volatile
    private var shouldBePlayingFlag: Boolean = false

    override suspend fun play(wavBytes: ByteArray): Result<Unit> {
        playLatch?.await(5, TimeUnit.SECONDS)
        return if (failOnPlay) {
            failOnPlay = false
            shouldBePlayingFlag = false
            Result.failure(IOException("Playback interrupted"))
        } else {
            shouldBePlayingFlag = true
            state = PlayerState.PLAYING
            delay(10)
            state = PlayerState.IDLE
            shouldBePlayingFlag = false
            Result.success(Unit)
        }
    }

    override suspend fun stop(): Result<Unit> {
        shouldBePlayingFlag = false
        state = PlayerState.STOPPED
        return Result.success(Unit)
    }

    override fun isPlaying(): Boolean = state == PlayerState.PLAYING
    override fun currentState(): PlayerState = state
    override fun shouldBePlaying(): Boolean = shouldBePlayingFlag
    override fun release() {
        state = PlayerState.IDLE
        shouldBePlayingFlag = false
    }
}

open class FakeSettingsRepository : SettingsRepository {
    private var settings = SpeechSettings()

    override fun get(): SpeechSettings = settings
    override fun save(settings: SpeechSettings) { this.settings = settings }
}

open class FakeEventEmitter : SpeechEventEmitter {
    val events = CopyOnWriteArrayList<Map<String, Any?>>()

    override fun emit(event: Map<String, Any?>) {
        events.add(event)
    }

    fun eventsOfType(type: String): List<Map<String, Any?>> =
        events.filter { (it["payload"] as? Map<*, *>) != null && it["type"] == type }
}

/**
 * Delegating [SpeechQueueManager] that counts peek() calls and can
 * return null on a specific peek invocation to simulate race conditions.
 */
class PeekCountingQueueManager(
    private val delegate: SpeechQueueManager
) : SpeechQueueManager {
    val peekCount = AtomicInteger(0)

    /** When set to N > 0, the N-th call to [peek] returns null. */
    var returnNullOnNthPeek = 0

    override fun offer(item: SpeechQueueItem): QueueOfferResult = delegate.offer(item)
    override fun poll(): SpeechQueueItem? = delegate.poll()
    override fun peek(): SpeechQueueItem? {
        val call = peekCount.incrementAndGet()
        if (returnNullOnNthPeek > 0 && call == returnNullOnNthPeek) {
            return null
        }
        return delegate.peek()
    }
    override fun clear() = delegate.clear()
    override fun size(): Int = delegate.size()
    override fun isEmpty(): Boolean = delegate.isEmpty()
    override fun updateMaxSize(newMaxSize: Int) = delegate.updateMaxSize(newMaxSize)
}

fun rawComment(id: String, text: String) = RawComment(
    id = id,
    text = text,
    userId = null,
    postedAtEpochMs = System.currentTimeMillis()
)

/**
 * Fake [TtsSpeaker] used by the Android-TTS contract tests to drive each
 * failure path in [SpeechControllerImpl.processWithAndroidTts]:
 *   * [readyOverride] — when set to false, simulates the not-ready branch
 *     (matches `speaker.isReady() == false` in production).
 *   * [throwOnSetSpeechRate] / [throwOnSetPitch] / [throwOnSetVolume] —
 *     when true, the corresponding setter throws, which forces the outer
 *     catch path inside `processWithAndroidTts` (`android_tts_failed:` prefix).
 *   * [failOnSpeak] — when true, [speak] returns [Result.failure] which
 *     forces the inner Result-wrapped failure path
 *     (also `android_tts_failed:` prefix).
 *   * [throwOnSpeak] — when true, [speak] throws which the inner try-catch
 *     converts to [Result.failure] (same prefix path as [failOnSpeak]).
 */
open class FakeTtsSpeaker : TtsSpeaker {
    var readyOverride: Boolean = true
    var throwOnSetSpeechRate: Boolean = false
    var throwOnSetPitch: Boolean = false
    var throwOnSetVolume: Boolean = false
    var failOnSpeak: Boolean = false
    var throwOnSpeak: Boolean = false

    /**
     * Issue #966 / #968: when set, [speak] returns
     * [Result.failure] with this sealed sub-type so the controller's
     * UserStopped suppression path can be tested without driving a real
     * stop() race. Takes precedence over [failOnSpeak] / [throwOnSpeak].
     *
     * `internal` because `TtsSpeakException` itself is `internal` and a
     * public property cannot expose an internal type.
     */
    internal var speakFailureOverride: TtsSpeakException? = null
    val speakCalls = AtomicInteger(0)
    // Issue #962: hooks for the stop-interrupts-in-flight-speak regression
    // test. `suspendOnSpeak` makes speak() suspend until stop() releases it;
    // `stopCalls` records that the controller propagated stop() to the
    // speaker.
    val stopCalls = AtomicInteger(0)
    var suspendOnSpeak: Boolean = false
    private val speakResumed = CompletableDeferred<Result<Unit>>()

    override suspend fun initialize(): Result<Unit> = Result.success(Unit)

    override suspend fun speak(text: String, utteranceId: String): Result<Unit> {
        speakCalls.incrementAndGet()
        speakFailureOverride?.let { return Result.failure(it) }
        if (throwOnSpeak) throw RuntimeException("simulated speak throw")
        if (failOnSpeak) return Result.failure(IOException("simulated speak failure"))
        if (suspendOnSpeak) return speakResumed.await()
        return Result.success(Unit)
    }

    override suspend fun stop(): Result<Unit> {
        stopCalls.incrementAndGet()
        if (suspendOnSpeak && !speakResumed.isCompleted) {
            speakResumed.complete(
                Result.failure(RuntimeException("simulated stop interrupt")),
            )
        }
        return Result.success(Unit)
    }

    override fun isReady(): Boolean = readyOverride
    override fun isSpeaking(): Boolean = suspendOnSpeak && !speakResumed.isCompleted
    override fun currentState(): PlayerState = PlayerState.IDLE

    override fun setSpeechRate(rate: Float) {
        if (throwOnSetSpeechRate) throw RuntimeException("simulated setSpeechRate throw")
    }
    override fun setPitch(pitch: Float) {
        if (throwOnSetPitch) throw RuntimeException("simulated setPitch throw")
    }
    override fun setVolume(volume: Float) {
        if (throwOnSetVolume) throw RuntimeException("simulated setVolume throw")
    }

    override fun release() {}
}
