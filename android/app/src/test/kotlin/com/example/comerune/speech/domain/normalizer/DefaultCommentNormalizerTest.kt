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
    fun `AC3 - repeated w is compressed to わらわら`() {
        val result = normalizer.normalize(raw("wwwww"), defaultSettings)
        assertEquals("わらわら", result.normalizedText)
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
    fun `two ws compress to わらわら - boundary of 2`() {
        val result = normalizer.normalize(raw("ww"), defaultSettings)
        assertEquals("わらわら", result.normalizedText)
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
        // "wwww" compresses to "わらわら", then no emoji to remove
        val result = normalizer.normalize(raw("wwww"), defaultSettings)
        assertEquals("わらわら", result.normalizedText)
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
        assertEquals("わらわら", result.normalizedText)
    }

    @Test
    fun `fullwidth ｗｗ is compressed to わらわら`() {
        val result = normalizer.normalize(raw("ｗｗ"), defaultSettings)
        assertEquals("わらわら", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `fullwidth ｗｗ in middle of text is also compressed`() {
        // 以前は PATTERN_W が `[wW]{2,}` のみで全角ｗ未対応だったため、
        // 中間の全角ｗｗがそのまま読み上げられていた。現在は `[wWｗＷ]{2,}`
        // で半角/全角を同時にカバーする。
        val result = normalizer.normalize(
            raw("おはようｗｗ やったね"),
            defaultSettings
        )
        assertEquals("おはようわらわら やったね", result.normalizedText)
    }

    @Test
    fun `fullwidth Ｗ is also compressed`() {
        val result = normalizer.normalize(raw("ＷＷＷＷ"), defaultSettings)
        assertEquals("わらわら", result.normalizedText)
    }

    @Test
    fun `mixed halfwidth and fullwidth w sequence is compressed`() {
        // キャラクタークラス `[wWｗＷ]` は順不同でマッチするので、
        // 半角小文字/大文字/全角小文字/全角大文字が混在するケースも 2 文字
        // 以上の笑いとして圧縮される。
        val cases = listOf(
            "おはようwｗ やったね",
            "おはようｗw やったね",
            "おはようwＷ やったね",
            "おはようｗWｗＷ やったね", // 4 種混在 + 3 文字以上
        )
        for (input in cases) {
            val result = normalizer.normalize(raw(input), defaultSettings)
            // JUnit 4 の assertEquals(message, expected, actual) 順で message を
            // 先頭に置くことで、失敗時にどの input で落ちたか特定しやすくする。
            assertEquals(
                "input=$input",
                "おはようわらわら やったね",
                result.normalizedText,
            )
        }
    }

    @Test
    fun `scheme-prefixed www-URL is still handled as URL`() {
        // `https://www.example.com` のように scheme 付き + www サブドメインの
        // URL で、拡張後の URL_PATTERN の first alternative (`https?://...`)
        // が優先的にマッチすることを確認する回帰テスト。bare URL 分岐と
        // 干渉しないこと。
        val result = normalizer.normalize(
            raw("https://www.example.com"),
            defaultSettings
        )
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `scheme-prefixed www-URL in mixed text is replaced with URL省略`() {
        val result = normalizer.normalize(
            raw("見て https://www.example.com/path です"),
            defaultSettings
        )
        assertEquals("見て URL省略 です", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `bare www-URL without scheme is skipped as url_only`() {
        val result = normalizer.normalize(raw("www.example.com"), defaultSettings)
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `bare www-URL surrounded by text is replaced with URL省略`() {
        val result = normalizer.normalize(
            raw("見て www.example.com です"),
            defaultSettings
        )
        assertEquals("見て URL省略 です", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `many w-URL such as wwww-example-com is replaced with URL省略`() {
        val result = normalizer.normalize(raw("wwww.example.com"), defaultSettings)
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `two w followed by dot-alnum is also replaced with URL省略`() {
        val result = normalizer.normalize(raw("ww.example.com"), defaultSettings)
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `uppercase WWW-URL is also replaced with URL省略`() {
        val result = normalizer.normalize(raw("WWW.EXAMPLE.COM"), defaultSettings)
        assertEquals("url_only", result.skipReason)
    }

    @Test
    fun `fullwidth wwww URL is also replaced with URL省略`() {
        val result = normalizer.normalize(
            raw("見て ｗｗｗ.example.com です"),
            defaultSettings
        )
        assertEquals("見て URL省略 です", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `bare www-URL is replaced with URL省略 even when skipUrlOnly is false`() {
        val settings = defaultSettings.copy(skipUrlOnly = false)
        val result = normalizer.normalize(raw("www.example.com"), settings)
        assertEquals("URL省略", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `bare www-URL with path and query is replaced with URL省略`() {
        val result = normalizer.normalize(
            raw("見て www.example.com/path?q=1&r=2 です"),
            defaultSettings
        )
        assertEquals("見て URL省略 です", result.normalizedText)
        assertNull(result.skipReason)
    }

    @Test
    fun `digit-prefixed www-URL is not treated as URL`() {
        // `(?<![a-zA-Z0-9])` lookbehind によって直前が数字の場合は bare URL
        // として扱わない（誤検出回避）。`123wwww.example.com` の `wwww` は
        // URL 検出対象外で、symbol compression 側の挙動に委ねられる。
        // (結果として `www.example.com` の部分が URL にマッチする余地が残るが、
        // lookbehind が数字を拒否するのでマッチしない。)
        val result = normalizer.normalize(
            raw("123wwww.example.com"),
            defaultSettings
        )
        // URL 検出されない → symbol compression で `wwww` が `わらわら` に
        // 変換される。
        assertEquals("123わらわら.example.com", result.normalizedText)
    }

    @Test
    fun `www followed by space is still laughter`() {
        // `www` の直後が空白の場合は URL ではないので通常の笑いとして変換する。
        val result = normalizer.normalize(raw("見て www やったね"), defaultSettings)
        assertEquals("見て わらわら やったね", result.normalizedText)
    }

    @Test
    fun `www followed by dot then end-of-string is still laughter`() {
        // `www.` の後に何も続かない場合は URL 判定しない。
        val result = normalizer.normalize(raw("すごい www."), defaultSettings)
        assertEquals("すごい わらわら.", result.normalizedText)
    }

    @Test
    fun `bare URL and trailing laughter coexist in one comment`() {
        // `www.example.com` は URL として置換、末尾の `wwww` は笑いとして変換。
        val result = normalizer.normalize(
            raw("www.example.com wwww"),
            defaultSettings
        )
        assertEquals("URL省略 わらわら", result.normalizedText)
    }

    @Test
    fun `letter-prefixed w sequence is still laughter`() {
        // `abwww` のように英字の直後に w が続く場合は URL 判定しない（bare URL
        // の lookbehind が英数字を除外する）。symbol compression で普通に
        // 「わらわら」に変換される。
        val result = normalizer.normalize(raw("abwwww"), defaultSettings)
        assertEquals("abわらわら", result.normalizedText)
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

    // --- NG Word Keyword Hack Resistance Tests ---

    @Test
    fun `NG word with space insertion is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("エ ロ動画"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with zero-width space is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("エ\u200Bロ動画"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with full-width katakana is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("ｴﾛ動画"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with hiragana variant is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("えろ動画"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with look-alike kanji is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("工口動画"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with repeated characters is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("エエエロロロ"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with symbol insertion is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("エ★ロ"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word with mixed evasion techniques is detected`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("工 \u200B口"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `NG word case-insensitive with normalization`() {
        val settings = defaultSettings.copy(ngWords = listOf("KILL"))
        val result = normalizer.normalize(raw("ｋｉｌｌ him"), settings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `clean text with similar-looking characters is not false positive`() {
        val settings = defaultSettings.copy(ngWords = listOf("エロ"))
        val result = normalizer.normalize(raw("工場見学"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `kanji 力士 is not false positive for カシ`() {
        val settings = defaultSettings.copy(ngWords = listOf("カス"))
        val result = normalizer.normalize(raw("力士の試合"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `kanji 八百屋 is not false positive`() {
        val settings = defaultSettings.copy(ngWords = listOf("ハゲ"))
        val result = normalizer.normalize(raw("八百屋さん"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `kanji 二千円 is not false positive`() {
        val settings = defaultSettings.copy(ngWords = listOf("ニート"))
        val result = normalizer.normalize(raw("二千円"), settings)
        assertNull(result.skipReason)
    }

    // --- Preset NG Word Tests ---

    @Test
    fun `preset NG words are checked`() {
        val normalizerWithPreset = DefaultCommentNormalizer(
            presetNgWords = listOf("テスト禁止語")
        )
        val result = normalizerWithPreset.normalize(raw("これはテスト禁止語です"), defaultSettings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `preset NG words apply normalization`() {
        val normalizerWithPreset = DefaultCommentNormalizer(
            presetNgWords = listOf("禁止ワード")
        )
        val result = normalizerWithPreset.normalize(raw("禁 止 ワ ー ド"), defaultSettings)
        assertEquals("ng_word", result.skipReason)
    }

    @Test
    fun `preset and user NG words are both checked`() {
        val normalizerWithPreset = DefaultCommentNormalizer(
            presetNgWords = listOf("プリセット語")
        )
        val settings = defaultSettings.copy(ngWords = listOf("ユーザー語"))
        val result1 = normalizerWithPreset.normalize(raw("これはユーザー語です"), settings)
        assertEquals("ng_word", result1.skipReason)
        val result2 = normalizerWithPreset.normalize(raw("これはプリセット語です"), settings)
        assertEquals("ng_word", result2.skipReason)
    }

    @Test
    fun `preset NG words do not cause false positive on clean text`() {
        val normalizerWithPreset = DefaultCommentNormalizer(
            presetNgWords = listOf("テスト禁止")
        )
        val result = normalizerWithPreset.normalize(raw("こんにちは"), defaultSettings)
        assertNull(result.skipReason)
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
