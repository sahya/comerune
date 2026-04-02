package com.example.comerune.speech.infrastructure.engine

import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult

/**
 * Stub implementation of [VoicevoxEngine] that returns failure for all operations.
 *
 * This class is intended for testing and as a fallback when the real engine
 * ([VoicevoxEngineImpl]) is not available. It should not be used in production.
 */
class StubVoicevoxEngine : VoicevoxEngine {

    @Volatile
    private var ready = false

    override suspend fun initialize(): Result<Unit> {
        return Result.failure(
            UnsupportedOperationException(
                "VoicevoxEngine JNI not yet available. See issue #42."
            )
        )
    }

    override suspend fun prepareForModelDownload(): Result<Unit> {
        return Result.failure(
            UnsupportedOperationException(
                "VoicevoxEngine JNI not yet available. See issue #42."
            )
        )
    }

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
        return Result.failure(
            UnsupportedOperationException(
                "VoicevoxEngine JNI not yet available. See issue #42."
            )
        )
    }

    override suspend fun loadModel(modelPath: String): Result<Unit> {
        return Result.failure(
            UnsupportedOperationException(
                "VoicevoxEngine JNI not yet available. See issue #42."
            )
        )
    }

    override fun isReady(): Boolean = ready

    override fun currentState(): TtsEngineState =
        if (ready) TtsEngineState.READY else TtsEngineState.UNINITIALIZED

    override fun release() {
        ready = false
    }
}
