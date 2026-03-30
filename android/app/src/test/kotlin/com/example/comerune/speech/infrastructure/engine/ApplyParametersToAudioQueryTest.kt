package com.example.comerune.speech.infrastructure.engine

import com.example.comerune.speech.domain.model.SpeechRequest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class ApplyParametersToAudioQueryTest {

    private fun createRequest(
        volumeScale: Float = 0.7f,
        speedScale: Float = 1.15f,
        pitchScale: Float = 0.0f,
        intonationScale: Float = 1.0f,
        prePhonemeLength: Float = 0.1f,
        postPhonemeLength: Float = 0.1f
    ) = SpeechRequest(
        text = "テスト",
        speakerId = 0,
        speedScale = speedScale,
        pitchScale = pitchScale,
        intonationScale = intonationScale,
        volumeScale = volumeScale,
        prePhonemeLength = prePhonemeLength,
        postPhonemeLength = postPhonemeLength
    )

    private fun applyParameters(json: String, request: SpeechRequest): String =
        VoicevoxEngineImpl.applyParametersToAudioQuery(json, request)

    @Test
    fun `volumeScale is applied to AudioQuery JSON`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(volumeScale = 0.7f)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.7, resultJson.getDouble("volumeScale"), 0.01)
    }

    @Test
    fun `all parameters are applied to AudioQuery JSON`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(
            volumeScale = 0.5f,
            speedScale = 1.5f,
            pitchScale = 0.2f,
            intonationScale = 1.3f,
            prePhonemeLength = 0.05f,
            postPhonemeLength = 0.15f
        )

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.5, resultJson.getDouble("volumeScale"), 0.01)
        assertEquals(1.5, resultJson.getDouble("speedScale"), 0.01)
        assertEquals(0.2, resultJson.getDouble("pitchScale"), 0.01)
        assertEquals(1.3, resultJson.getDouble("intonationScale"), 0.01)
        assertEquals(0.05, resultJson.getDouble("prePhonemeLength"), 0.01)
        assertEquals(0.15, resultJson.getDouble("postPhonemeLength"), 0.01)
    }

    @Test
    fun `existing AudioQuery fields are preserved`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1,"accent_phrases":[{"moras":[]}],"outputSamplingRate":24000}"""
        val request = createRequest(volumeScale = 0.7f)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(24000, resultJson.getInt("outputSamplingRate"))
        assertEquals(1, resultJson.getJSONArray("accent_phrases").length())
    }

    @Test(expected = org.json.JSONException::class)
    fun `invalid JSON throws JSONException`() {
        val invalidJson = "not valid json"
        val request = createRequest()

        applyParameters(invalidJson, request)
    }

    @Test
    fun `zero volumeScale is applied`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(volumeScale = 0.0f)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.0, resultJson.getDouble("volumeScale"), 0.01)
    }

    @Test
    fun `max volumeScale is applied`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(volumeScale = 2.0f)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(2.0, resultJson.getDouble("volumeScale"), 0.01)
    }

    @Test
    fun `NaN volumeScale falls back to default`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(volumeScale = Float.NaN)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.7, resultJson.getDouble("volumeScale"), 0.01)
    }

    @Test
    fun `Infinity speedScale falls back to default`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(speedScale = Float.POSITIVE_INFINITY)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(1.15, resultJson.getDouble("speedScale"), 0.01)
    }

    @Test
    fun `negative Infinity pitchScale falls back to default`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(pitchScale = Float.NEGATIVE_INFINITY)

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.0, resultJson.getDouble("pitchScale"), 0.01)
    }

    @Test
    fun `NaN values in all parameters fall back to defaults`() {
        val inputJson = """{"volumeScale":1.0,"speedScale":1.0,"pitchScale":0.0,"intonationScale":1.0,"prePhonemeLength":0.1,"postPhonemeLength":0.1}"""
        val request = createRequest(
            volumeScale = Float.NaN,
            speedScale = Float.NaN,
            pitchScale = Float.NaN,
            intonationScale = Float.NaN,
            prePhonemeLength = Float.NaN,
            postPhonemeLength = Float.NaN
        )

        val result = applyParameters(inputJson, request)
        val resultJson = JSONObject(result)

        assertEquals(0.7, resultJson.getDouble("volumeScale"), 0.01)
        assertEquals(1.15, resultJson.getDouble("speedScale"), 0.01)
        assertEquals(0.0, resultJson.getDouble("pitchScale"), 0.01)
        assertEquals(1.0, resultJson.getDouble("intonationScale"), 0.01)
        assertEquals(0.1, resultJson.getDouble("prePhonemeLength"), 0.01)
        assertEquals(0.1, resultJson.getDouble("postPhonemeLength"), 0.01)
    }
}
