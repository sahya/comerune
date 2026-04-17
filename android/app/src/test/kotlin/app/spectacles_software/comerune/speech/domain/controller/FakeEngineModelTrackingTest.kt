package app.spectacles_software.comerune.speech.domain.controller

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Tests for [FakeEngine] model tracking, verifying that the fake
 * accurately simulates the stale-tracking → reload scenario fixed
 * in VoicevoxEngineImpl.
 *
 * These tests ensure the FakeEngine is a faithful stand-in for
 * integration-level testing of the load/clear/reload lifecycle.
 */
class FakeEngineModelTrackingTest {

    private lateinit var engine: FakeEngine

    @Before
    fun setUp() {
        engine = FakeEngine()
        // Enable model tracking (off by default for backward compatibility)
        engine.trackedLoadedModels = mutableSetOf()
    }

    @Test
    fun `loadModel tracks model as loaded`() = runBlocking {
        val result = engine.loadModel("/models/model_2.vvm")
        assertTrue(result.isSuccess)
        assertTrue(engine.isModelTracked("model_2"))
        assertEquals(listOf("model_2"), engine.loadModelCalls.toList())
    }

    @Test
    fun `clearLoadedModel removes model from tracking`() = runBlocking {
        engine.loadModel("/models/model_2.vvm")
        assertTrue(engine.isModelTracked("model_2"))

        engine.clearLoadedModel("model_2")
        assertFalse(engine.isModelTracked("model_2"))
        assertEquals(listOf("model_2"), engine.clearLoadedModelCalls.toList())
    }

    @Test
    fun `loadModel after clearLoadedModel reloads the model`() = runBlocking {
        // Simulate: model loaded → deleted → re-downloaded → loadModel again
        engine.loadModel("/models/model_2.vvm")
        engine.clearLoadedModel("model_2")
        assertFalse(engine.isModelTracked("model_2"))

        val result = engine.loadModel("/models/model_2.vvm")
        assertTrue(result.isSuccess)
        assertTrue(engine.isModelTracked("model_2"))
        // loadModel should have been called twice
        assertEquals(2, engine.loadModelCalls.size)
    }

    @Test
    fun `clearLoadedModel for unknown model is no-op`() {
        engine.clearLoadedModel("nonexistent")
        assertEquals(listOf("nonexistent"), engine.clearLoadedModelCalls.toList())
        // No crash, no side effect on other models
    }

    @Test
    fun `loadModel with failure does not track model`() = runBlocking {
        engine.failOnLoadModel = true
        val result = engine.loadModel("/models/model_2.vvm")
        assertTrue(result.isFailure)
        assertFalse(engine.isModelTracked("model_2"))
        // The call was still recorded
        assertEquals(listOf("model_2"), engine.loadModelCalls.toList())
    }

    @Test
    fun `tracking disabled by default returns true for any model`() {
        val defaultEngine = FakeEngine()
        // trackedLoadedModels is null by default
        assertTrue(defaultEngine.isModelTracked("any_model"))
    }

    @Test
    fun `loadModel extracts model ID from path without extension`() = runBlocking {
        engine.loadModel("/data/voicevox/voicevox_models/3.vvm")
        assertTrue(engine.isModelTracked("3"))
        assertEquals(listOf("3"), engine.loadModelCalls.toList())
    }

    @Test
    fun `loadModel with bare filename extracts ID correctly`() = runBlocking {
        engine.loadModel("model_5.vvm")
        assertTrue(engine.isModelTracked("model_5"))
    }

    @Test
    fun `multiple models tracked independently`() = runBlocking {
        engine.loadModel("/models/model_1.vvm")
        engine.loadModel("/models/model_2.vvm")
        engine.loadModel("/models/model_3.vvm")

        assertTrue(engine.isModelTracked("model_1"))
        assertTrue(engine.isModelTracked("model_2"))
        assertTrue(engine.isModelTracked("model_3"))

        engine.clearLoadedModel("model_2")

        assertTrue(engine.isModelTracked("model_1"))
        assertFalse(engine.isModelTracked("model_2"))
        assertTrue(engine.isModelTracked("model_3"))
    }
}
