package com.example.comerune.speech.domain.model

object VoicevoxModelManifest {
    private const val VVM_BASE_URL =
        "https://github.com/VOICEVOX/voicevox_vvm/releases/download/0.16.2/"

    // File sizes are approximate estimates for UI display.
    // Actual download progress uses HTTP Content-Length from the server.
    val models: List<VoicevoxModelInfo> = listOf(
        VoicevoxModelInfo(
            modelId = "0",
            displayName = "四国めたん",
            speakerIds = listOf(0, 1, 2, 3),
            vvmFileName = "0.vvm",
            downloadUrl = "${VVM_BASE_URL}0.vvm",
            fileSizeBytes = 52_000_000L,
            // APK同梱せず、初回起動時にダウンロードする。
            isBundled = false
        ),
        VoicevoxModelInfo(
            modelId = "1",
            displayName = "ずんだもん",
            speakerIds = listOf(4, 5, 6, 7),
            vvmFileName = "1.vvm",
            downloadUrl = "${VVM_BASE_URL}1.vvm",
            fileSizeBytes = 52_000_000L,
            isBundled = false
        ),
        VoicevoxModelInfo(
            modelId = "2",
            displayName = "春日部つむぎ",
            speakerIds = listOf(8),
            vvmFileName = "2.vvm",
            downloadUrl = "${VVM_BASE_URL}2.vvm",
            fileSizeBytes = 52_000_000L,
            isBundled = false
        ),
        VoicevoxModelInfo(
            modelId = "3",
            displayName = "波音リツ",
            speakerIds = listOf(9, 65),
            vvmFileName = "3.vvm",
            downloadUrl = "${VVM_BASE_URL}3.vvm",
            fileSizeBytes = 52_000_000L,
            isBundled = false
        ),
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
