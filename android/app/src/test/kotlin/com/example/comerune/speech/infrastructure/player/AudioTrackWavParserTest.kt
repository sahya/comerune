package com.example.comerune.speech.infrastructure.player

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder

class AudioTrackWavParserTest {

    /**
     * Builds a standard 44-byte PCM WAV header followed by [dataBytes] of silence.
     *
     * Layout (little-endian unless noted):
     *   0..3   "RIFF"  (big-endian ASCII)
     *   4..7   file size - 8
     *   8..11  "WAVE"  (big-endian ASCII)
     *  12..15  "fmt "  (big-endian ASCII)
     *  16..19  fmt chunk size (16 for PCM)
     *  20..21  audio format (1 = PCM)
     *  22..23  channels
     *  24..27  sample rate
     *  28..31  byte rate
     *  32..33  block align
     *  34..35  bits per sample
     *  36..39  "data"  (big-endian ASCII)
     *  40..43  data chunk size
     *  44..    PCM data
     */
    private fun buildStandardWav(
        sampleRate: Int = 44100,
        channels: Int = 1,
        bitsPerSample: Int = 16,
        dataBytes: Int = 100
    ): ByteArray {
        val bytesPerSample = bitsPerSample / 8
        val blockAlign = channels * bytesPerSample
        val byteRate = sampleRate * blockAlign
        val fileSize = 36 + dataBytes  // total file size minus 8 bytes for RIFF header

        val buffer = ByteBuffer.allocate(44 + dataBytes).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(fileSize)
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)                          // fmt chunk size
        buffer.putShort(1)                         // audio format = PCM
        buffer.putShort(channels.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataBytes)
        // Fill PCM data with zeros (silence)
        buffer.put(ByteArray(dataBytes))
        return buffer.array()
    }

    /**
     * Builds a WAV with an extra chunk (e.g. "LIST") inserted between "fmt " and "data".
     */
    private fun buildWavWithExtraChunk(
        sampleRate: Int = 44100,
        channels: Int = 1,
        bitsPerSample: Int = 16,
        dataBytes: Int = 100,
        extraChunkId: String = "LIST",
        extraChunkPayload: ByteArray = ByteArray(24)
    ): ByteArray {
        val bytesPerSample = bitsPerSample / 8
        val blockAlign = channels * bytesPerSample
        val byteRate = sampleRate * blockAlign
        val extraChunkTotalSize = 8 + extraChunkPayload.size  // id(4) + size(4) + payload
        val fileSize = 36 + extraChunkTotalSize + dataBytes

        val totalSize = 44 + extraChunkTotalSize + dataBytes
        val buffer = ByteBuffer.allocate(totalSize).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII))
        buffer.putInt(fileSize)
        buffer.put("WAVE".toByteArray(Charsets.US_ASCII))
        // fmt chunk
        buffer.put("fmt ".toByteArray(Charsets.US_ASCII))
        buffer.putInt(16)
        buffer.putShort(1)
        buffer.putShort(channels.toShort())
        buffer.putInt(sampleRate)
        buffer.putInt(byteRate)
        buffer.putShort(blockAlign.toShort())
        buffer.putShort(bitsPerSample.toShort())
        // extra chunk
        buffer.put(extraChunkId.toByteArray(Charsets.US_ASCII))
        buffer.putInt(extraChunkPayload.size)
        buffer.put(extraChunkPayload)
        // data chunk
        buffer.put("data".toByteArray(Charsets.US_ASCII))
        buffer.putInt(dataBytes)
        buffer.put(ByteArray(dataBytes))
        return buffer.array()
    }

    // --- Tests ---

    @Test
    fun `parse standard 44-byte WAV header`() {
        val wav = buildStandardWav(sampleRate = 22050, channels = 1, bitsPerSample = 16, dataBytes = 200)
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(22050, info.sampleRate)
        assertEquals(1, info.channels)
        assertEquals(16, info.bitsPerSample)
        assertEquals(44, info.dataOffset)
        assertEquals(200, info.dataSize)
    }

    @Test
    fun `parse WAV with extra chunks between fmt and data`() {
        val extraPayload = ByteArray(32) { it.toByte() }
        val wav = buildWavWithExtraChunk(
            sampleRate = 48000,
            channels = 2,
            bitsPerSample = 16,
            dataBytes = 512,
            extraChunkId = "LIST",
            extraChunkPayload = extraPayload
        )
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(48000, info.sampleRate)
        assertEquals(2, info.channels)
        assertEquals(16, info.bitsPerSample)
        // dataOffset should be after RIFF(12) + fmt(8+16) + LIST(8+32) + data header(8)
        // = 12 + 24 + 40 + 8 = 84, but dataOffset points to start of PCM data (after "data" + size)
        val expectedDataOffset = 12 + 24 + 8 + extraPayload.size + 8
        assertEquals(expectedDataOffset, info.dataOffset)
        assertEquals(512, info.dataSize)
    }

    @Test
    fun `reject non-PCM audio format`() {
        // Build a standard WAV but patch audioFormat to 3 (IEEE float)
        val wav = buildStandardWav()
        // audioFormat is at bytes 20-21 (little-endian)
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putShort(20, 3)  // IEEE float format

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for non-PCM format")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("Unsupported audio format"))
        }
    }

    @Test
    fun `reject WAV with zero channels`() {
        val wav = buildStandardWav()
        // channels field is at bytes 22-23
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putShort(22, 0)

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for zero channels")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("Incomplete WAV header"))
        }
    }

    @Test
    fun `reject WAV with zero sample rate`() {
        val wav = buildStandardWav()
        // sampleRate field is at bytes 24-27
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(24, 0)

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for zero sample rate")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("Incomplete WAV header"))
        }
    }

    @Test
    fun `data size is clamped when it exceeds available bytes`() {
        val actualDataBytes = 100
        val wav = buildStandardWav(dataBytes = actualDataBytes)

        // Patch the data chunk size to a value larger than the actual data present
        // data chunk size is at bytes 40-43
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(40, 9999)

        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        // dataSize should be clamped to available bytes (total size - data offset)
        val expectedClamped = wav.size - info.dataOffset
        assertEquals(expectedClamped, info.dataSize)
    }

    @Test
    fun `reject WAV with missing data chunk`() {
        // Build a WAV that has fmt chunk but no data chunk
        // Replace "data" chunk id with something else
        val wav = buildStandardWav(dataBytes = 100)
        // "data" is at bytes 36-39
        wav[36] = 'n'.code.toByte()
        wav[37] = 'o'.code.toByte()
        wav[38] = 'p'.code.toByte()
        wav[39] = 'e'.code.toByte()

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for missing data chunk")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("data chunk not found"))
        }
    }

    @Test
    fun `reject WAV with invalid chunk size beyond buffer`() {
        // Build a WAV with an extra chunk whose size exceeds the buffer
        val wav = buildStandardWav(dataBytes = 100)

        // Insert a fake chunk by patching: replace "data" at 36 with a custom chunk
        // that has a size pointing past the end of the buffer
        wav[36] = 'X'.code.toByte()
        wav[37] = 'X'.code.toByte()
        wav[38] = 'X'.code.toByte()
        wav[39] = 'X'.code.toByte()
        // The chunk size at bytes 40-43 is currently 100 (the data size).
        // Set it to a value that exceeds the remaining buffer.
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(40, 99999)

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for invalid chunk size")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("Invalid chunk"))
        }
    }

    @Test
    fun `reject WAV with negative chunk size`() {
        val wav = buildStandardWav(dataBytes = 100)

        // Replace "data" chunk with a custom chunk that has a negative size
        wav[36] = 'Y'.code.toByte()
        wav[37] = 'Y'.code.toByte()
        wav[38] = 'Y'.code.toByte()
        wav[39] = 'Y'.code.toByte()
        val buffer = ByteBuffer.wrap(wav).order(ByteOrder.LITTLE_ENDIAN)
        buffer.putInt(40, -1)

        try {
            AudioTrackWavPlayer.parseWavHeader(wav)
            fail("Expected IllegalArgumentException for negative chunk size")
        } catch (e: IllegalArgumentException) {
            assertEquals(true, e.message?.contains("Invalid chunk"))
        }
    }

    @Test
    fun `parse stereo 8-bit WAV`() {
        val wav = buildStandardWav(sampleRate = 8000, channels = 2, bitsPerSample = 8, dataBytes = 64)
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(8000, info.sampleRate)
        assertEquals(2, info.channels)
        assertEquals(8, info.bitsPerSample)
        assertEquals(44, info.dataOffset)
        assertEquals(64, info.dataSize)
    }

    @Test
    fun `parse multiple extra chunks before data`() {
        // Build manually: RIFF + WAVE + fmt + LIST + fact + data
        val sampleRate = 44100
        val channels = 1
        val bitsPerSample = 16
        val blockAlign = channels * (bitsPerSample / 8)
        val byteRate = sampleRate * blockAlign
        val dataBytes = 50

        val listPayload = ByteArray(10)
        val factPayload = ByteArray(4)
        val totalExtraSize = (8 + listPayload.size) + (8 + factPayload.size)
        val fileSize = 36 + totalExtraSize + dataBytes

        val buf = ByteBuffer.allocate(44 + totalExtraSize + dataBytes).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray(Charsets.US_ASCII))
        buf.putInt(fileSize)
        buf.put("WAVE".toByteArray(Charsets.US_ASCII))
        // fmt
        buf.put("fmt ".toByteArray(Charsets.US_ASCII))
        buf.putInt(16)
        buf.putShort(1)
        buf.putShort(channels.toShort())
        buf.putInt(sampleRate)
        buf.putInt(byteRate)
        buf.putShort(blockAlign.toShort())
        buf.putShort(bitsPerSample.toShort())
        // LIST chunk
        buf.put("LIST".toByteArray(Charsets.US_ASCII))
        buf.putInt(listPayload.size)
        buf.put(listPayload)
        // fact chunk
        buf.put("fact".toByteArray(Charsets.US_ASCII))
        buf.putInt(factPayload.size)
        buf.put(factPayload)
        // data chunk
        buf.put("data".toByteArray(Charsets.US_ASCII))
        buf.putInt(dataBytes)
        buf.put(ByteArray(dataBytes))

        val wav = buf.array()
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(44100, info.sampleRate)
        assertEquals(1, info.channels)
        assertEquals(16, info.bitsPerSample)
        assertEquals(50, info.dataSize)
        // Verify dataOffset is past all extra chunks
        val expectedOffset = 12 + 24 + 8 + listPayload.size + 8 + factPayload.size + 8
        assertEquals(expectedOffset, info.dataOffset)
    }

    @Test
    fun `parse WAV with zero data bytes`() {
        val wav = buildStandardWav(dataBytes = 0)
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(44100, info.sampleRate)
        assertEquals(1, info.channels)
        assertEquals(16, info.bitsPerSample)
        assertEquals(44, info.dataOffset)
        assertEquals(0, info.dataSize)
    }

    @Test
    fun `parse WAV with extended fmt chunk (cbSize field)`() {
        // Extended fmt chunk: 16 standard bytes + 2 extra bytes (cbSize = 0)
        val sampleRate = 44100
        val channels = 1
        val bitsPerSample = 16
        val blockAlign = channels * (bitsPerSample / 8)
        val byteRate = sampleRate * blockAlign
        val fmtChunkSize = 18 // 16 standard + 2 extra (cbSize)
        val dataBytes = 100
        val fileSize = 4 + (8 + fmtChunkSize) + (8 + dataBytes)

        val totalSize = 12 + (8 + fmtChunkSize) + (8 + dataBytes)
        val buf = ByteBuffer.allocate(totalSize).order(ByteOrder.LITTLE_ENDIAN)
        buf.put("RIFF".toByteArray(Charsets.US_ASCII))
        buf.putInt(fileSize)
        buf.put("WAVE".toByteArray(Charsets.US_ASCII))
        // fmt chunk with extended size
        buf.put("fmt ".toByteArray(Charsets.US_ASCII))
        buf.putInt(fmtChunkSize)
        buf.putShort(1) // PCM
        buf.putShort(channels.toShort())
        buf.putInt(sampleRate)
        buf.putInt(byteRate)
        buf.putShort(blockAlign.toShort())
        buf.putShort(bitsPerSample.toShort())
        buf.putShort(0) // cbSize = 0 (extra bytes in extended fmt)
        // data chunk
        buf.put("data".toByteArray(Charsets.US_ASCII))
        buf.putInt(dataBytes)
        buf.put(ByteArray(dataBytes))

        val wav = buf.array()
        val info = AudioTrackWavPlayer.parseWavHeader(wav)

        assertEquals(44100, info.sampleRate)
        assertEquals(1, info.channels)
        assertEquals(16, info.bitsPerSample)
        assertEquals(100, info.dataSize)
        // dataOffset = 12 (RIFF header) + 8 (fmt id+size) + 18 (fmt body) + 8 (data id+size)
        assertEquals(12 + 8 + fmtChunkSize + 8, info.dataOffset)
    }
}
