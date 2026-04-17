package com.example.comerune.speech.domain.normalizer

import org.junit.Assert.assertEquals
import org.junit.Test

class NgWordTextNormalizerTest {

    // --- NFKC Normalization ---

    @Test
    fun `full-width katakana is normalized`() {
        // ｴﾛ (half-width katakana) → エロ → えろ (after katakana→hiragana + lowercase)
        assertEquals("えろ", NgWordTextNormalizer.normalize("ｴﾛ"))
    }

    @Test
    fun `full-width alphanumeric is normalized`() {
        // Ａ Ｂ Ｃ → abc
        assertEquals("abc", NgWordTextNormalizer.normalize("ＡＢＣ"))
    }

    // --- Zero-width / Control Character Removal ---

    @Test
    fun `zero-width space is removed`() {
        val input = "エ\u200Bロ" // エ + ZWS + ロ
        assertEquals("えろ", NgWordTextNormalizer.normalize(input))
    }

    @Test
    fun `zero-width joiner is removed`() {
        val input = "エ\u200Dロ" // エ + ZWJ + ロ
        assertEquals("えろ", NgWordTextNormalizer.normalize(input))
    }

    @Test
    fun `zero-width non-joiner is removed`() {
        val input = "エ\u200Cロ" // エ + ZWNJ + ロ
        assertEquals("えろ", NgWordTextNormalizer.normalize(input))
    }

    @Test
    fun `soft hyphen is removed`() {
        val input = "エ\u00ADロ"
        assertEquals("えろ", NgWordTextNormalizer.normalize(input))
    }

    @Test
    fun `variation selectors are removed`() {
        val input = "エ\uFE0Fロ"
        assertEquals("えろ", NgWordTextNormalizer.normalize(input))
    }

    // --- Space Insertion ---

    @Test
    fun `spaces between characters are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ ロ"))
    }

    @Test
    fun `multiple spaces between characters are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ   ロ"))
    }

    @Test
    fun `tabs and mixed whitespace are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ\tロ"))
    }

    // --- Katakana / Hiragana Unification ---

    @Test
    fun `katakana is converted to hiragana`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エロ"))
    }

    @Test
    fun `hiragana stays as hiragana`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("えろ"))
    }

    @Test
    fun `mixed katakana and hiragana is unified`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エろ"))
    }

    // --- Look-alike Character Substitution ---

    @Test
    fun `kanji 工口 is normalized to えろ`() {
        // 工 → エ → え, 口 → ロ → ろ
        assertEquals("えろ", NgWordTextNormalizer.normalize("工口"))
    }

    @Test
    fun `kanji 力 is normalized to か`() {
        assertEquals("か", NgWordTextNormalizer.normalize("力"))
    }

    @Test
    fun `kanji 夕 is normalized to た`() {
        assertEquals("た", NgWordTextNormalizer.normalize("夕"))
    }

    @Test
    fun `kanji 二 is normalized to に`() {
        assertEquals("に", NgWordTextNormalizer.normalize("二"))
    }

    @Test
    fun `kanji 卜 is normalized to と`() {
        assertEquals("と", NgWordTextNormalizer.normalize("卜"))
    }

    @Test
    fun `kanji 八 is normalized to は`() {
        assertEquals("は", NgWordTextNormalizer.normalize("八"))
    }

    @Test
    fun `kanji 千 is normalized to ち`() {
        assertEquals("ち", NgWordTextNormalizer.normalize("千"))
    }

    // --- Symbol Insertion ---

    @Test
    fun `symbols between characters are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ★ロ"))
    }

    @Test
    fun `dots between characters are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ.ロ"))
    }

    @Test
    fun `mixed symbols are removed`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ※ロ"))
    }

    // --- Consecutive Duplicate Character Compression ---

    @Test
    fun `three or more same characters are compressed to two`() {
        // エエエロロロ → ええろろ (3→2 each, katakana→hiragana)
        assertEquals("ええろろ", NgWordTextNormalizer.normalize("エエエロロロ"))
    }

    @Test
    fun `two same characters are not compressed`() {
        assertEquals("ええ", NgWordTextNormalizer.normalize("エエ"))
    }

    @Test
    fun `five same characters are compressed to two`() {
        assertEquals("ああ", NgWordTextNormalizer.normalize("アアアアア"))
    }

    // --- Combined Evasion Techniques ---

    @Test
    fun `space insertion with katakana`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("エ ロ"))
    }

    @Test
    fun `look-alike kanji with spaces`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("工 口"))
    }

    @Test
    fun `zero-width chars with look-alike kanji`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("工\u200B口"))
    }

    @Test
    fun `full-width katakana with symbols`() {
        assertEquals("えろ", NgWordTextNormalizer.normalize("ｴ★ﾛ"))
    }

    @Test
    fun `mixed evasion - full-width, spaces, look-alike, repeated`() {
        // 工工工 口口口 with spaces → エエエ ロロロ → えええ ろろろ → えええろろろ → ええろろ
        assertEquals("ええろろ", NgWordTextNormalizer.normalize("工工工 口口口"))
    }

    // --- Case Insensitivity ---

    @Test
    fun `uppercase ASCII is lowercased`() {
        assertEquals("kill", NgWordTextNormalizer.normalize("KILL"))
    }

    @Test
    fun `mixed case ASCII is lowercased`() {
        assertEquals("kill", NgWordTextNormalizer.normalize("KiLl"))
    }

    // --- Edge Cases ---

    @Test
    fun `empty string returns empty`() {
        assertEquals("", NgWordTextNormalizer.normalize(""))
    }

    @Test
    fun `plain hiragana text is mostly unchanged`() {
        assertEquals("こんにちは", NgWordTextNormalizer.normalize("こんにちは"))
    }

    @Test
    fun `normal text with no evasion is preserved`() {
        assertEquals("ありがとう", NgWordTextNormalizer.normalize("ありがとう"))
    }

    @Test
    fun `digits are preserved`() {
        assertEquals("12345", NgWordTextNormalizer.normalize("12345"))
    }

    @Test
    fun `full-width digits are normalized to half-width`() {
        assertEquals("12345", NgWordTextNormalizer.normalize("１２３４５"))
    }

    // --- Individual Method Tests ---

    @Test
    fun `removeControlChars preserves normal text`() {
        assertEquals("テスト", NgWordTextNormalizer.removeControlChars("テスト"))
    }

    @Test
    fun `removeControlChars removes BOM`() {
        assertEquals("テスト", NgWordTextNormalizer.removeControlChars("\uFEFFテスト"))
    }

    @Test
    fun `applyLookAlikeTable maps all known characters`() {
        assertEquals("エ", NgWordTextNormalizer.applyLookAlikeTable("工"))
        assertEquals("ロ", NgWordTextNormalizer.applyLookAlikeTable("口"))
        assertEquals("カ", NgWordTextNormalizer.applyLookAlikeTable("力"))
        assertEquals("タ", NgWordTextNormalizer.applyLookAlikeTable("夕"))
        assertEquals("ニ", NgWordTextNormalizer.applyLookAlikeTable("二"))
        assertEquals("ト", NgWordTextNormalizer.applyLookAlikeTable("卜"))
        assertEquals("ハ", NgWordTextNormalizer.applyLookAlikeTable("八"))
        assertEquals("チ", NgWordTextNormalizer.applyLookAlikeTable("千"))
    }

    @Test
    fun `applyLookAlikeTable does not affect normal katakana`() {
        assertEquals("エロ", NgWordTextNormalizer.applyLookAlikeTable("エロ"))
    }

    @Test
    fun `katakanaToHiragana converts standard range`() {
        assertEquals("あいうえおかきくけこ",
            NgWordTextNormalizer.katakanaToHiragana("アイウエオカキクケコ"))
    }

    @Test
    fun `katakanaToHiragana preserves hiragana`() {
        assertEquals("あいうえお",
            NgWordTextNormalizer.katakanaToHiragana("あいうえお"))
    }

    @Test
    fun `removeSpacesAndSymbols keeps letters and digits`() {
        assertEquals("テスト123",
            NgWordTextNormalizer.removeSpacesAndSymbols("テスト 123"))
    }

    @Test
    fun `removeSpacesAndSymbols removes various symbols`() {
        assertEquals("テスト",
            NgWordTextNormalizer.removeSpacesAndSymbols("テ★ス※ト"))
    }

    @Test
    fun `compressDuplicates compresses runs of 3+`() {
        assertEquals("ああ", NgWordTextNormalizer.compressDuplicates("ああああ"))
    }

    @Test
    fun `compressDuplicates keeps runs of 2`() {
        assertEquals("ああ", NgWordTextNormalizer.compressDuplicates("ああ"))
    }

    @Test
    fun `compressDuplicates keeps single characters`() {
        assertEquals("あ", NgWordTextNormalizer.compressDuplicates("あ"))
    }

    @Test
    fun `compressDuplicates handles mixed runs`() {
        assertEquals("ああいい", NgWordTextNormalizer.compressDuplicates("ああああいいいい"))
    }
}
