package com.example.comerune.speech.domain.model

object VoicevoxModelManifest {
    private const val VVM_BASE_URL =
        "https://github.com/VOICEVOX/voicevox_vvm/releases/download/0.16.2/"

    // File sizes are approximate estimates for UI display.
    // Actual download progress uses HTTP Content-Length from the server.
    val models: List<VoicevoxModelInfo> = listOf(
        VoicevoxModelInfo(
            modelId = "n0",
            displayName = "VOICEVOX Nemo",
            speakerIds = listOf(10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10008),
            vvmFileName = "n0.vvm",
            downloadUrl = "${VVM_BASE_URL}n0.vvm",
            fileSizeBytes = 52_000_000L,
            isBundled = false
        )
    )

    fun findByModelId(modelId: String): VoicevoxModelInfo? =
        models.find { it.modelId == modelId }

    fun findBySpeakerId(speakerId: Int): VoicevoxModelInfo? =
        models.find { speakerId in it.speakerIds }
}
