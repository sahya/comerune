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

    // ── Issue #970 follow-up: atomic soft-cancel counter reset ──────────
    //
    // Documentation-only test (no shared engine instance to drive here —
    // synthesize() and initialize() both depend on the Android Context and
    // the JNI bridge, so a true integration test runs on the device CI).
    //
    // Race the fix prevents:
    //   1. synthesize #1 in flight: activeSynthesisCount=1, state=SYNTHESIZING
    //   2. dispose triggers initialize() → PROCEED path. If the counter reset
    //      ran BEFORE the state flip, the in-flight synthesize()'s `finally`
    //      could decrement (1 → 0), then the reset would clobber it to 0,
    //      then a stale decrement could push it to -1. With the counter ever
    //      negative, later synthesize() / decrementAndGet() pairs never
    //      observe `== 0` and the READY restore never fires, leaving the
    //      engine wedged at SYNTHESIZING — the original #970 symptom.
    //   3. Fix: state flip + activeSynthesisCount.set(0) under a single
    //      synchronized(stateLock) block, paired with synthesize()'s entry
    //      block that takes the same lock. The stale finally observes
    //      state == INITIALIZING (or later state) and skips the restore.
    //
    // The runtime invariant is verified at code-review level by inspecting
    // initialize()'s synchronized(stateLock) block and synthesize()'s
    // finally block in VoicevoxEngineImpl.kt.

    @Test
    fun `soft cancel recovery is documented to be atomic under stateLock`() {
        // Marker test: documents that both SYNTHESIZING and INITIALIZING
        // are treated as recoverable states whose counter reset MUST be
        // performed under stateLock together with the state flip.
        val recoverableStates = listOf(
            TtsEngineState.SYNTHESIZING,
            TtsEngineState.INITIALIZING
        )
        recoverableStates.forEach { state ->
            assertEquals(
                "Recoverable state $state must PROCEED via soft cancel",
                VoicevoxEngineImpl.InitializeStartDecision.PROCEED,
                VoicevoxEngineImpl.evaluateInitializeStartState(state)
            )
        }
    }

    // ── Issue #979: evaluateNativeInitializePlan ────────────────────────
    //
    // PR #974 (Issue #970) routed SYNTHESIZING and INITIALIZING to the
    // PROCEED path so the screen could reopen without a PlatformException.
    // But the native synthesizer was still alive and its model cache was
    // still populated, so the PROCEED path's unconditional
    // `nativeInitialize` + `nativeLoadModel(*.vvm)` re-run caused the
    // second `nativeLoadModel` to return false:
    // "Failed to load voice model: n0.vvm".
    //
    // The fix introduces a plan: SKIP_NATIVE_INIT when soft cancel
    // recovery has tracked-loaded models; FULL_INIT otherwise. The plan
    // gates clearing of [loadedModelPaths] / [loadedModelIds], the
    // `nativeInitialize` call, and the VVM load loop's per-model
    // idempotent skip.

    @Test
    fun `evaluateNativeInitializePlan SKIP_NATIVE_INIT for SYNTHESIZING with loaded models`() {
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.SKIP_NATIVE_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.SYNTHESIZING,
                hasLoadedModels = true
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan SKIP_NATIVE_INIT for INITIALIZING with loaded models`() {
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.SKIP_NATIVE_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.INITIALIZING,
                hasLoadedModels = true
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan FULL_INIT for SYNTHESIZING when no models tracked`() {
        // Soft cancel without recorded models — the native side may not
        // hold a usable model cache, so a full re-init is the safe path.
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.SYNTHESIZING,
                hasLoadedModels = false
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan FULL_INIT for INITIALIZING when no models tracked`() {
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.INITIALIZING,
                hasLoadedModels = false
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan FULL_INIT for UNINITIALIZED regardless of models`() {
        // AC4: fresh init must not degenerate into a skip.
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.UNINITIALIZED,
                hasLoadedModels = false
            )
        )
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.UNINITIALIZED,
                hasLoadedModels = true
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan FULL_INIT for ERROR regardless of models`() {
        // ERROR recovery cannot trust prior tracking — always do a clean
        // native re-init.
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.ERROR,
                hasLoadedModels = false
            )
        )
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.ERROR,
                hasLoadedModels = true
            )
        )
    }

    @Test
    fun `evaluateNativeInitializePlan FULL_INIT for READY fallback`() {
        // READY is normally handled by evaluateInitializeStartState (it
        // returns ALREADY_READY before this helper is reached). The
        // fallback guards against future callers and must not silently
        // skip a real re-init.
        assertEquals(
            VoicevoxEngineImpl.NativeInitializePlan.FULL_INIT,
            VoicevoxEngineImpl.evaluateNativeInitializePlan(
                previousState = TtsEngineState.READY,
                hasLoadedModels = true
            )
        )
    }
}
