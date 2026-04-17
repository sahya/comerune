package com.example.comerune.speech.infrastructure.engine

import com.example.comerune.speech.domain.model.TtsEngineState
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class PrepareForModelDownloadFlowTest {

    @Test
    fun `cancellation is rethrown and cancellation restore state is emitted`() {
        val transitions = mutableListOf<Pair<TtsEngineState, String>>()

        try {
            runBlocking {
                VoicevoxEngineImpl.runPrepareForModelDownload(
                    previousState = TtsEngineState.READY,
                    updateEngineState = { state, reason -> transitions += state to reason },
                    prepareAction = { throw CancellationException("cancelled") }
                )
            }
            fail("Expected CancellationException to be rethrown")
        } catch (e: CancellationException) {
            assertEquals("cancelled", e.message)
        }

        assertEquals(
            listOf(TtsEngineState.READY to "prepare_download_cancelled_restore"),
            transitions
        )
    }

    @Test
    fun `exception returns failure and failed restore state is emitted`() = runBlocking {
        val transitions = mutableListOf<Pair<TtsEngineState, String>>()

        val result = VoicevoxEngineImpl.runPrepareForModelDownload(
            previousState = TtsEngineState.READY,
            updateEngineState = { state, reason -> transitions += state to reason },
            prepareAction = { throw IOException("timeout") }
        )

        assertTrue(result.isFailure)
        assertEquals(
            "VOICEVOX辞書のダウンロードに失敗しました。ネットワーク接続を確認してください。",
            result.exceptionOrNull()?.message
        )
        assertEquals(
            listOf(TtsEngineState.READY to "prepare_download_failed_restore"),
            transitions
        )
    }

    @Test
    fun `success returns success and completed state is emitted`() = runBlocking {
        val transitions = mutableListOf<Pair<TtsEngineState, String>>()

        val result = VoicevoxEngineImpl.runPrepareForModelDownload(
            previousState = TtsEngineState.ERROR,
            updateEngineState = { state, reason -> transitions += state to reason },
            prepareAction = {}
        )

        assertTrue(result.isSuccess)
        assertEquals(
            listOf(TtsEngineState.ERROR to "prepare_download_completed"),
            transitions
        )
    }
}
