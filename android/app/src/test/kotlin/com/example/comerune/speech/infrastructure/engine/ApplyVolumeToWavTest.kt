package com.example.comerune.speech.infrastructure.engine

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ApplyVolumeToWavTest {

    /**
     * Build a minimal 16-bit mono PCM WAV with given samples.
     */
    private fun buildWav(samples: ShortArray, sampleRate: Int = 44100): ByteArray {
        val dataSize = samples.size * 2
        val buf = ByteBuffer.allocate(44 + dataSize).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray(Charsets.US_ASCII))
        buf.putInt(36 + dataSize)
        buf.put("WAVE".toByteArray(Charsets.US_ASCII))
        buf.put("fmt ".toByteArray(Charsets.US_ASCII))
        buf.putInt(16) // fmt chunk size
        buf.putShort(1) // PCM
        buf.putShort(1) // mono
        buf.putInt(sampleRate)
        buf.putInt(sampleRate * 2) // byte rate
        buf.putShort(2) // block align
        buf.putShort(16) // bits per sample
        buf.put("data".toByteArray(Charsets.US_ASCII))
        buf.putInt(dataSize)
        for (s in samples) buf.putShort(s)
        return buf.array()
    }

    private fun readSamples(wav: ByteArray, offset: Int = 44): ShortArray {
        val count = (wav.size - offset) / 2
        val result = ShortArray(count)
        val buf = ByteBuffer.wrap(wav, offset, wav.size - offset).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until count) result[i] = buf.getShort()
        return result
    }

    @Test
    fun `volumeScale 0_5 halves sample values`() {
        val wav = buildWav(shortArrayOf(1000, -1000, 2000, -2000))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 0.5f)
        val samples = readSamples(result)
        assertEquals(500, samples[0].toInt())
        assertEquals(-500, samples[1].toInt())
        assertEquals(1000, samples[2].toInt())
        assertEquals(-1000, samples[3].toInt())
    }

    @Test
    fun `volumeScale 1_0 returns original array without copy`() {
        val wav = buildWav(shortArrayOf(100, 200))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 1.0f)
        assertSame(wav, result) // no copy
    }

    @Test
    fun `volumeScale 0_999 returns original array (within epsilon)`() {
        val wav = buildWav(shortArrayOf(100))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 0.9995f)
        assertSame(wav, result)
    }

    @Test
    fun `volumeScale 2_0 clamps to 32767`() {
        val wav = buildWav(shortArrayOf(20000, -20000))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 2.0f)
        val samples = readSamples(result)
        assertEquals(32767, samples[0].toInt()) // 40000 clamped
        assertEquals(-32768, samples[1].toInt()) // -40000 clamped
    }

    @Test
    fun `volumeScale 0 produces silence`() {
        val wav = buildWav(shortArrayOf(10000, -10000, 5000))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 0.0f)
        val samples = readSamples(result)
        for (s in samples) assertEquals(0, s.toInt())
    }

    @Test
    fun `small wav (less than 44 bytes) returns original`() {
        val tiny = ByteArray(20)
        val result = VoicevoxEngineImpl.applyVolumeToWav(tiny, 0.5f)
        assertSame(tiny, result)
    }

    @Test
    fun `negative volumeScale is clamped to 0`() {
        val wav = buildWav(shortArrayOf(1000))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, -1.0f)
        val samples = readSamples(result)
        assertEquals(0, samples[0].toInt())
    }

    @Test
    fun `volumeScale above 2 is clamped to 2`() {
        val wav = buildWav(shortArrayOf(10000))
        val result = VoicevoxEngineImpl.applyVolumeToWav(wav, 5.0f)
        val samples = readSamples(result)
        assertEquals(20000, samples[0].toInt()) // clamped to 2.0 × 10000
    }
}
