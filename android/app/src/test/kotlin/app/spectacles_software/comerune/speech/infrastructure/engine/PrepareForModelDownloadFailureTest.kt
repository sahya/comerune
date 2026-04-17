package app.spectacles_software.comerune.speech.infrastructure.engine

import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class PrepareForModelDownloadFailureTest {

    @Test
    fun `io exception maps to network guidance message`() {
        val exception = IOException("timeout")

        val failure = VoicevoxEngineImpl.buildPrepareForModelDownloadFailure(exception)

        assertEquals(
            "VOICEVOX辞書のダウンロードに失敗しました。ネットワーク接続を確認してください。",
            failure.message
        )
        assertSame(exception, failure.cause)
    }

    @Test
    fun `non io exception keeps original message`() {
        val exception = IllegalStateException("storage unavailable")

        val failure = VoicevoxEngineImpl.buildPrepareForModelDownloadFailure(exception)

        assertEquals("storage unavailable", failure.message)
        assertSame(exception, failure.cause)
    }

    @Test
    fun `non io exception with null message uses fallback message`() {
        val exception = IllegalStateException()

        val failure = VoicevoxEngineImpl.buildPrepareForModelDownloadFailure(exception)

        assertEquals("Unknown dictionary download error", failure.message)
        assertSame(exception, failure.cause)
    }
}
