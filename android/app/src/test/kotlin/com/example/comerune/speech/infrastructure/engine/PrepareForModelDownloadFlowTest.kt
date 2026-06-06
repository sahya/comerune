package com.example.comerune.speech.infrastructure.engine

import com.example.comerune.speech.domain.model.TtsEngineState
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Unit tests for pure state-transition helpers on [VoicevoxEngineImpl].
 *
 * Originally focused on `runPrepareForModelDownload`; also exercises
 * `evaluateInitializeStartState` (added for Issue #970 — VOICEVOX dispose race).
 */
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

    // ── Issue #970: evaluateInitializeStartState ────────────────────────
    //
    // VOICEVOX synthesis cannot be interrupted at the JNI layer. If the
    // user disposes the comment screen during synthesis, the engine state
    // stays at SYNTHESIZING. The next call to initialize() must recover
    // via soft cancel rather than rejecting with "Cannot initialize from
    // state: SYNTHESIZING" (visible as a PlatformException dialog).

    @Test
    fun `evaluateInitializeStartState returns ALREADY_READY for READY`() {
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.ALREADY_READY,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.READY)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns PROCEED for UNINITIALIZED`() {
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.PROCEED,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.UNINITIALIZED)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns PROCEED for ERROR (recovery path)`() {
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.PROCEED,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.ERROR)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns PROCEED for SYNTHESIZING (Issue 970)`() {
        // Regression for Issue #970: dispose during synthesis must be
        // recoverable. Before the fix this returned REJECT and surfaced
        // as "Cannot initialize from state: SYNTHESIZING".
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.PROCEED,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.SYNTHESIZING)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns PROCEED for INITIALIZING (cancelled prior init)`() {
        // A prior initialize() coroutine that was cancelled before it could
        // publish READY or ERROR leaves the engine in INITIALIZING. The
        // next initialize() should be able to resume rather than wedge.
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.PROCEED,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.INITIALIZING)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns REJECT for DOWNLOADING`() {
        // Asset download in progress — must not race with initialization.
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.REJECT,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.DOWNLOADING)
        )
    }

    @Test
    fun `evaluateInitializeStartState returns REJECT for EXTRACTING`() {
        // Asset extraction in progress — must not race with initialization.
        assertEquals(
            VoicevoxEngineImpl.InitializeStartDecision.REJECT,
            VoicevoxEngineImpl.evaluateInitializeStartState(TtsEngineState.EXTRACTING)
        )
    }
}
