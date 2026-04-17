package app.spectacles_software.comerune.speech.domain.splitter

import org.junit.Assert.assertEquals
import org.junit.Test

class NoOpTextSplitterTest {

    private val splitter = NoOpTextSplitter()

    @Test
    fun `returns single-element list with original text`() {
        val result = splitter.split("こんにちは")
        assertEquals(listOf("こんにちは"), result)
    }

    @Test
    fun `returns single-element list for empty string`() {
        val result = splitter.split("")
        assertEquals(listOf(""), result)
    }

    @Test
    fun `returns single-element list for text with particles`() {
        val result = splitter.split("でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ")
        assertEquals(1, result.size)
        assertEquals("でも岩国は今豪雨らしいからこれぐらいの雨でまだよかったよ", result[0])
    }
}
