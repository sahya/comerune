package com.example.comerune.speech.domain.model

enum class ModelDownloadState {
    NOT_DOWNLOADED,
    DOWNLOADING,
    DOWNLOADED,
    ERROR
}

data class VoicevoxModelInfo(
    val modelId: String,
    val displayName: String,
    val speakerIds: List<Int>,
    val vvmFileName: String,
    val downloadUrl: String,
    val fileSizeBytes: Long,
    /** Expected SHA-256 (hex) of the file at [downloadUrl]; checked before use. */
    val sha256: String,
    val isBundled: Boolean,
    val downloadState: ModelDownloadState = if (isBundled) ModelDownloadState.DOWNLOADED else ModelDownloadState.NOT_DOWNLOADED
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "modelId" to modelId,
        "displayName" to displayName,
        "speakerIds" to speakerIds,
        "vvmFileName" to vvmFileName,
        "fileSizeBytes" to fileSizeBytes,
        "isBundled" to isBundled,
        "downloadState" to downloadState.name
    )
}
