package com.example.comerune.speech.domain.engine

import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult

interface VoicevoxEngine {
    suspend fun initialize(): Result<Unit>
    suspend fun prepareForModelDownload(): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult>
    fun isReady(): Boolean

    /** Returns the current internal state of the TTS engine. */
    fun currentState(): TtsEngineState

    /** Load a VVM model file into the engine at runtime. */
    suspend fun loadModel(modelPath: String): Result<Unit>

    /**
     * Clear the loaded-model tracking for [modelId] so that a subsequent
     * [loadModel] call will not skip the native load.
     *
     * This does **not** unload the model from the native synthesizer (VOICEVOX
     * Core has no unload API). It only invalidates the skip-optimization cache.
     */
    fun clearLoadedModel(modelId: String)

    fun release()
}
