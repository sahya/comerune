package app.spectacles_software.comerune.speech.domain.model

/**
 * Single source of truth for available VOICEVOX models on Android.
 *
 * **Important:** The Dart constants `supportedVoicevoxModelIds` and
 * `supportedVoicevoxSpeakerNames` in `voicevox_model_info.dart` must be
 * kept in sync with this manifest. When adding or removing models, update
 * both files. The test in `voicevox_model_info_test.dart` validates
 * consistency automatically.
 */
object VoicevoxModelManifest {
    private const val VVM_BASE_URL =
        "https://github.com/VOICEVOX/voicevox_vvm/releases/download/0.16.2/"

    // File sizes are measured values from VOICEVOX VVM 0.16.2 release.
    // Actual download progress uses HTTP Content-Length from the server.
    //
    // VVM バージョンアップ時は公式 README と照合すること:
    // https://github.com/VOICEVOX/voicevox_vvm/blob/main/README.md
    //
    // VVM 0.16.2 ファイル構成:
    //   0.vvm = 四国めたん(0-3) + ずんだもん(4-7) + 春日部つむぎ(8) + 雨晴はう(10)
    //   1.vvm = 冥鳴ひまり (サポート対象外)
    //   2.vvm = 九州そら(15-18) + 中国うさぎ(61-64) (サポート対象外)
    //   3.vvm = 波音リツ(9,65)
    //   n0.vvm = VOICEVOX Nemo(10000-10008)
    val models: List<VoicevoxModelInfo> = listOf(
        VoicevoxModelInfo(
            modelId = "0",
            displayName = "春日部つむぎ",
            speakerIds = listOf(0, 1, 2, 3, 4, 5, 6, 7, 8, 10),
            vvmFileName = "0.vvm",
            downloadUrl = "${VVM_BASE_URL}0.vvm",
            fileSizeBytes = 58_214_379L,
            isBundled = false
        ),
        VoicevoxModelInfo(
            modelId = "3",
            displayName = "波音リツ",
            speakerIds = listOf(9, 65),
            vvmFileName = "3.vvm",
            downloadUrl = "${VVM_BASE_URL}3.vvm",
            fileSizeBytes = 61_730_024L,
            isBundled = false
        ),
        VoicevoxModelInfo(
            modelId = "n0",
            displayName = "VOICEVOX Nemo",
            speakerIds = listOf(10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10008),
            vvmFileName = "n0.vvm",
            downloadUrl = "${VVM_BASE_URL}n0.vvm",
            fileSizeBytes = 73_074_437L,
            isBundled = false
        )
    )

    fun findByModelId(modelId: String): VoicevoxModelInfo? =
        models.find { it.modelId == modelId }

    fun findBySpeakerId(speakerId: Int): VoicevoxModelInfo? =
        models.find { speakerId in it.speakerIds }
}
