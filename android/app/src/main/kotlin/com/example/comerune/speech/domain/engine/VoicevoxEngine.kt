package com.example.comerune.speech.domain.engine

import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.VoicevoxConfig
import com.example.comerune.speech.domain.model.WavSynthesisResult

interface VoicevoxEngine {
    suspend fun initialize(config: VoicevoxConfig): Result<Unit>
    suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult>
    fun isReady(): Boolean
    fun release()
}
