package app.spectacles_software.comerune.speech.domain.controller

import app.spectacles_software.comerune.speech.domain.model.RawComment
import app.spectacles_software.comerune.speech.domain.model.SpeechRuntimeStatus
import app.spectacles_software.comerune.speech.domain.model.SpeechSettings
import app.spectacles_software.comerune.speech.domain.model.SubmitResult

interface SpeechController {
    suspend fun initialize(): Result<Unit>
    suspend fun start(): Result<Unit>
    suspend fun stop(clearQueue: Boolean = false): Result<Unit>
    suspend fun skip(): Result<Unit>
    suspend fun clearQueue(): Result<Unit>
    suspend fun submitComment(rawComment: RawComment): Result<SubmitResult>
    suspend fun updateSettings(settings: SpeechSettings): Result<Unit>
    suspend fun getStatus(): SpeechRuntimeStatus
    fun release()
}
