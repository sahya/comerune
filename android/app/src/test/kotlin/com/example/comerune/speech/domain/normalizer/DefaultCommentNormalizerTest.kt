package com.example.comerune.speech.domain.normalizer

import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class DefaultCommentNormalizerTest {

    private lateinit var normalizer: DefaultCommentNormalizer
    private lateinit var defaultSettings: SpeechSettings

    @Before
    fun setUp() {
        normalizer = DefaultCommentNormalizer()
        defaultSettings = SpeechSettings()
    }

    private fun raw(text: String) = RawComment(
        id = "test-id",
        text = text,
        userId = "user1",
        postedAtEpochMs = 0L
    )

    // --- Acceptance Criteria Tests ---

    @Test
    fun `AC1 - URL-only comment is skipped with url_only reason`() {
        val result = normalizer.normalize(raw("https://example.com/test"), defaultSettings)
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `AC2 - mixed text with URL replaces URL with placeholder`() {
        val result = normalizer.normalize(raw("これ見て https://example.com/test"), defaultSettings)
        assertEquals("これ見て URL省略", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC3 - repeated w is compressed to わら`() {
        val result = normalizer.normalize(raw("wwwww"), defaultSettings)
        assertEquals("わら", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC4 - repeated 草 is compressed to くさ`() {
        val result = normalizer.normalize(raw("草草草"), defaultSettings)
        assertEquals("くさ", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC5 - repeated 8 is compressed to はくしゅ`() {
        val result = normalizer.normalize(raw("888888"), defaultSettings)
        assertEquals("はくしゅ", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC6 - repeated exclamation is compressed to びっくり`() {
        val result = normalizer.normalize(raw("!!!!!!"), defaultSettings)
        assertEquals("びっくり", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC7 - repeated question mark is compressed to はてな`() {
        val result = normalizer.normalize(raw("?????"), defaultSettings)
        assertEquals("はてな", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC8 - repeated prolonged sound mark is compressed to のばし`() {
        val result = normalizer.normalize(raw("ーーーー"), defaultSettings)
        assertEquals("のばし", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC9 - emoji-only comment is skipped with emoji_only reason`() {
        val result = normalizer.normalize(raw("\uD83D\uDE0A\uD83D\uDE0A\uD83D\uDE0A"), defaultSettings)
        assertEquals("emoji_only", result.skipReason)
    }

    @Test
    fun `AC10 - emoji in mixed text is removed`() {
        val result = normalizer.normalize(raw("ありがとう\uD83D\uDE0A"), defaultSettings)
        assertEquals("ありがとう", result.normalizedText)
        assertNull(result.skipReason)
    }

    // --- Edge Case Tests ---

    @Test
    fun `single w is not compressed`() {
        val result = normalizer.normalize(raw("w"), defaultSettings)
        assertEquals("w", result.normalizedText)
    }

    @Test
    fun `single exclamation is not compressed`() {
        val result = normalizer.normalize(raw("!"), defaultSettings)
        assertEquals("!", result.normalizedText)
    }

    @Test
    fun `two 8s are not compressed - requires 3 or more`() {
        val result = normalizer.normalize(raw("88"), defaultSettings)
        assertEquals("88", result.normalizedText)
    }

    @Test
    fun `two prolonged marks are not compressed - requires 3 or more`() {
        val result = normalizer.normalize(raw("ーー"), defaultSettings)
        assertEquals("ーー", result.normalizedText)
    }

    @Test
    fun `full-width exclamation marks are compressed`() {
        val result = normalizer.normalize(raw("！！！"), defaultSettings)
        assertEquals("びっくり", result.normalizedText)
    }

    @Test
    fun `full-width question marks are compressed`() {
        val result = normalizer.normalize(raw("？？？"), defaultSettings)
        assertEquals("はてな", result.normalizedText)
    }

    @Test
    fun `full-width 8 is compressed`() {
        val result = normalizer.normalize(raw("８８８"), defaultSettings)
        assertEquals("はくしゅ", result.normalizedText)
    }

    @Test
    fun `mixed symbols in text with readable content`() {
        val result = normalizer.normalize(raw("すごい!!!!"), defaultSettings)
        assertEquals("すごいびっくり", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `URL-only skip is disabled when skipUrlOnly is false`() {
        val settings = defaultSettings.copy(skipUrlOnly = false)
        val result = normalizer.normalize(raw("https://example.com/test"), settings)
        assertEquals("URL省略", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `multiple URLs in text are all replaced`() {
        val result = normalizer.normalize(
            raw("見て https://a.com と https://b.com"),
            defaultSettings
        )
        assertEquals("見て URL省略 と URL省略", result.normalizedText)
    }

    @Test
    fun `symbol compression followed by emoji does not result in blank skip`() {
        // "wwww" compresses to "わら", then no emoji to remove
        val result = normalizer.normalize(raw("wwww"), defaultSettings)
        assertEquals("わら", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `tilde variants are compressed as prolonged sound`() {
        val result = normalizer.normalize(raw("～～～"), defaultSettings)
        assertEquals("のばし", result.normalizedText)
    }

    @Test
    fun `uppercase W is also compressed`() {
        val result = normalizer.normalize(raw("WWWW"), defaultSettings)
        assertEquals("わら", result.normalizedText)
    }
}
