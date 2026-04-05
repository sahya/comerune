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
import com.example.comerune.speech.domain.settings.SettingsRepository
import kotlinx.coroutines.delay
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
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
    var throwOnSynthesize = false
    var failOnEvenCalls = false

    override suspend fun initialize(): Result<Unit> = Result.success(Unit)

    override suspend fun prepareForModelDownload(): Result<Unit> = Result.success(Unit)

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
        val callNumber = synthesizeCount.incrementAndGet()
        if (throwOnSynthesize) {
            throwOnSynthesize = false
            throw RuntimeException("Unexpected engine error")
        }
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

open class FakePlayer : WavPlayer {
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

fun rawComment(id: String, text: String) = RawComment(
    id = id,
    text = text,
    userId = null,
    postedAtEpochMs = System.currentTimeMillis()
)
