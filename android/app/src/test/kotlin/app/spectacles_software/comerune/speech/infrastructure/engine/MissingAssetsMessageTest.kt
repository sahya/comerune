package app.spectacles_software.comerune.speech.infrastructure.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MissingAssetsMessageTest {

    @Test
    fun `returns null when all required assets are present`() {
        val message = VoicevoxEngineImpl.buildMissingAssetsMessage(
            hasDict = true,
            hasAnyVvm = true
        )
        assertNull(message)
    }

    @Test
    fun `returns message for missing dictionary`() {
        val message = VoicevoxEngineImpl.buildMissingAssetsMessage(
            hasDict = false,
            hasAnyVvm = true
        )
        assertEquals(
            "VOICEVOXの初期化に必要なデータが未準備です（不足: open_jtalk 辞書）。話者ライブラリでモデルをダウンロードしてください。",
            message
        )
    }

    @Test
    fun `returns message for missing model`() {
        val message = VoicevoxEngineImpl.buildMissingAssetsMessage(
            hasDict = true,
            hasAnyVvm = false
        )
        assertEquals(
            "VOICEVOXの初期化に必要なデータが未準備です（不足: 音声モデル）。話者ライブラリでモデルをダウンロードしてください。",
            message
        )
    }

    @Test
    fun `returns message for missing dictionary and model`() {
        val message = VoicevoxEngineImpl.buildMissingAssetsMessage(
            hasDict = false,
            hasAnyVvm = false
        )
        assertEquals(
            "VOICEVOXの初期化に必要なデータが未準備です（不足: open_jtalk 辞書・音声モデル）。話者ライブラリでモデルをダウンロードしてください。",
            message
        )
    }
}
