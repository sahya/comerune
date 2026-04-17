package app.spectacles_software.comerune.speech.domain.repository

import app.spectacles_software.comerune.speech.domain.model.VoicevoxModelInfo

interface VoicevoxModelRepository {
    fun getAvailableModels(): List<VoicevoxModelInfo>
    suspend fun downloadModel(
        modelId: String,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)? = null
    ): Result<Unit>
    fun deleteModel(modelId: String): Result<Unit>
    fun isModelDownloaded(modelId: String): Boolean
    fun getModelFile(modelId: String): java.io.File?

    /** Ensure a bundled model is copied from assets to the file system (if any). */
    fun ensureBundledModel(modelInfo: VoicevoxModelInfo)

    fun cancelDownload(modelId: String)
}
