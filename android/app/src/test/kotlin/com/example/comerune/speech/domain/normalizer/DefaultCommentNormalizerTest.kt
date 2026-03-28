package com.example.comerune.speech.domain.normalizer

import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.ReplaceRule
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

    // --- Blank/Empty Input Tests ---

    @Test
    fun `empty string is skipped with blank reason`() {
        val result = normalizer.normalize(raw(""), defaultSettings)
        assertEquals("blank", result.skipReason)
    }

    @Test
    fun `whitespace only is skipped with blank reason`() {
        val result = normalizer.normalize(raw("   "), defaultSettings)
        assertEquals("blank", result.skipReason)
    }

    @Test
    fun `tab and newline only is skipped with blank reason`() {
        val result = normalizer.normalize(raw("\t\n"), defaultSettings)
        assertEquals("blank", result.skipReason)
    }

    @Test
    fun `id field is passed through to NormalizedComment`() {
        val comment = RawComment(
            id = "custom-id-42",
            text = "hello",
            userId = "user1",
            postedAtEpochMs = 0L
        )
        val result = normalizer.normalize(comment, defaultSettings)
        assertEquals("custom-id-42", result.id)
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
    fun `two ws compress to わら - boundary of 2`() {
        val result = normalizer.normalize(raw("ww"), defaultSettings)
        assertEquals("わら", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `two 8s are not compressed - requires 3 or more`() {
        val result = normalizer.normalize(raw("88"), defaultSettings)
        assertEquals("88", result.normalizedText)
    }

    @Test
    fun `three 8s compress to はくしゅ - boundary of 3`() {
        val result = normalizer.normalize(raw("888"), defaultSettings)
        assertEquals("はくしゅ", result.normalizedText)
        assertNull(result.skipReason)
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

    // --- Text Length Truncation Tests ---

    @Test
    fun `AC1 - 50 char text is not truncated`() {
        val text = "あ".repeat(50)
        val result = normalizer.normalize(raw(text), defaultSettings)
        assertEquals(text, result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC2 - 51 char text is truncated to 50 chars plus suffix`() {
        val text = "あ".repeat(51)
        val result = normalizer.normalize(raw(text), defaultSettings)
        assertEquals("あ".repeat(50) + "、以下省略", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `truncation with custom maxTextLength and suffix`() {
        val settings = defaultSettings.copy(maxTextLength = 10, trimLongTextSuffix = "...")
        val text = "あ".repeat(15)
        val result = normalizer.normalize(raw(text), settings)
        assertEquals("あ".repeat(10) + "...", result.normalizedText)
    }

    @Test
    fun `maxTextLength coerced to at least 1`() {
        val settings = defaultSettings.copy(maxTextLength = 0)
        val text = "abc"
        val result = normalizer.normalize(raw(text), settings)
        assertEquals("a、以下省略", result.normalizedText)
    }

    // --- Dictionary Replacement Tests ---

    @Test
    fun `AC3 - dictionary rule replaces matching text`() {
        val settings = defaultSettings.copy(
            dictionaryRules = listOf(ReplaceRule(pattern = "初見", replacement = "しょけん"))
        )
        val result = normalizer.normalize(raw("初見です"), settings)
        assertEquals("しょけんです", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `AC4 - disabled dictionary rule is skipped`() {
        val settings = defaultSettings.copy(
            dictionaryRules = listOf(
                ReplaceRule(pattern = "初見", replacement = "しょけん", enabled = false)
            )
        )
        val result = normalizer.normalize(raw("初見です"), settings)
        assertEquals("初見です", result.normalizedText)
    }

    @Test
    fun `multiple dictionary rules applied in order`() {
        val settings = defaultSettings.copy(
            dictionaryRules = listOf(
                ReplaceRule(pattern = "ABC", replacement = "DEF"),
                ReplaceRule(pattern = "DEF", replacement = "GHI")
            )
        )
        val result = normalizer.normalize(raw("ABC"), settings)
        assertEquals("GHI", result.normalizedText)
    }

    @Test
    fun `AC7 - invalid regex in dictionary rule does not crash`() {
        val settings = defaultSettings.copy(
            dictionaryRules = listOf(
                ReplaceRule(pattern = "[invalid", replacement = "replaced")
            )
        )
        val result = normalizer.normalize(raw("test"), settings)
        assertEquals("test", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `empty dictionary rules list is no-op`() {
        val settings = defaultSettings.copy(dictionaryRules = emptyList())
        val result = normalizer.normalize(raw("テスト"), settings)
        assertEquals("テスト", result.normalizedText)
    }

    // --- NG Word Tests ---

    @Test
    fun `AC5 - NG word in comment results in ng_word skip`() {
        val settings = defaultSettings.copy(ngWords = listOf("NG例"))
        val result = normalizer.normalize(raw("これはNG例です"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `AC6 - NG word check is case-insensitive`() {
        val settings = defaultSettings.copy(ngWords = listOf("badword"))
        val result = normalizer.normalize(raw("This has BADWORD in it"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word partial match works`() {
        val settings = defaultSettings.copy(ngWords = listOf("spam"))
        val result = normalizer.normalize(raw("nospamhere"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `no NG word match returns no skip`() {
        val settings = defaultSettings.copy(ngWords = listOf("spam"))
        val result = normalizer.normalize(raw("clean text"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `empty NG word list means no check`() {
        val settings = defaultSettings.copy(ngWords = emptyList())
        val result = normalizer.normalize(raw("anything goes"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `NG word check happens before other transforms`() {
        // NG word should be checked on preprocessed text, not after URL/symbol/emoji processing
        val settings = defaultSettings.copy(ngWords = listOf("badsite"))
        val result = normalizer.normalize(raw("visit badsite https://example.com"), settings)
        assertEquals("ng_word", result.skipReason)
        // normalizedText should be the preprocessed text, not the URL-replaced text
        assertEquals("visit badsite https://example.com", result.normalizedText)
    }

    // --- Processing Order Tests ---

    @Test
    fun `dictionary replacement happens after emoji removal`() {
        val settings = defaultSettings.copy(
            dictionaryRules = listOf(ReplaceRule(pattern = "テスト", replacement = "test"))
        )
        val result = normalizer.normalize(raw("テスト\uD83D\uDE0A"), settings)
        assertEquals("test", result.normalizedText)
    }

    @Test
    fun `truncation happens after dictionary replacement`() {
        val settings = defaultSettings.copy(
            maxTextLength = 5,
            dictionaryRules = listOf(ReplaceRule(pattern = "AB", replacement = "ABCDEFGHIJ"))
        )
        val result = normalizer.normalize(raw("AB"), settings)
        assertEquals("ABCDE、以下省略", result.normalizedText)
    }
}
