package com.example.comerune.speech.domain.repository

import com.example.comerune.speech.domain.model.VoicevoxModelInfo

interface VoicevoxModelRepository {
    fun getAvailableModels(): List<VoicevoxModelInfo>
    suspend fun downloadModel(
        modelId: String,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)? = null
    ): Result<Unit>
    fun deleteModel(modelId: String): Result<Unit>
    fun isModelDownloaded(modelId: String): Boolean
    fun getModelFile(modelId: String): java.io.File?

    /** Ensure a bundled model is copied from assets to the file system. */
    fun ensureBundledModel(modelInfo: VoicevoxModelInfo)

    fun cancelDownload(modelId: String)
}
