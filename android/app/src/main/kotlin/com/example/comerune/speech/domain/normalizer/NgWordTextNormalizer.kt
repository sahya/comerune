package com.example.comerune.speech.domain.normalizer

import java.text.Normalizer

/**
 * NG word detection-specific text normalizer.
 *
 * Normalizes input text to defeat common keyword hack techniques used in
 * live streaming comments (e.g., space insertion, full-width/half-width mixing,
 * katakana/hiragana swapping, look-alike kanji substitution).
 *
 * This normalization is used ONLY for NG word matching — it does NOT affect
 * the text sent to the TTS engine.
 */
object NgWordTextNormalizer {

    /**
     * Normalize text for NG word comparison.
     *
     * Processing order:
     * 1. NFKC normalization (full-width → half-width, etc.)
     * 2. Zero-width / control character removal
     * 3. Look-alike character substitution (漢字 → カタカナ)
     * 4. Katakana → hiragana conversion
     * 5. Lowercase
     * 6. Space and symbol removal
     * 7. Consecutive duplicate character compression
     */
    fun normalize(text: String): String {
        var result = text

        // 1. NFKC normalization
        result = Normalizer.normalize(result, Normalizer.Form.NFKC)

        // 2. Remove zero-width and control characters
        result = removeControlChars(result)

        // 3. Look-alike character substitution
        result = applyLookAlikeTable(result)

        // 4. Katakana → hiragana
        result = katakanaToHiragana(result)

        // 5. Lowercase
        result = result.lowercase()

        // 6. Remove spaces and symbols
        result = removeSpacesAndSymbols(result)

        // 7. Compress consecutive duplicate characters
        result = compressDuplicates(result)

        return result
    }

    /**
     * Remove zero-width characters, control characters, and variation selectors.
     */
    internal fun removeControlChars(text: String): String {
        val sb = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = Character.codePointAt(text, i)
            val charCount = Character.charCount(cp)
            if (!isControlOrInvisible(cp)) {
                sb.appendCodePoint(cp)
            }
            i += charCount
        }
        return sb.toString()
    }

    private fun isControlOrInvisible(codePoint: Int): Boolean {
        // Zero-width characters
        if (codePoint == 0x200B || // Zero Width Space
            codePoint == 0x200C || // Zero Width Non-Joiner
            codePoint == 0x200D || // Zero Width Joiner
            codePoint == 0xFEFF || // BOM / Zero Width No-Break Space
            codePoint == 0x00AD    // Soft Hyphen
        ) return true

        // Variation selectors (U+FE00..U+FE0F, U+E0100..U+E01EF)
        if (codePoint in 0xFE00..0xFE0F) return true
        if (codePoint in 0xE0100..0xE01EF) return true

        // C0/C1 control characters (except standard whitespace handled later)
        if (codePoint in 0x0000..0x001F && codePoint != 0x0020) return true
        if (codePoint in 0x007F..0x009F) return true

        return false
    }

    /**
     * Replace look-alike kanji with their katakana equivalents.
     * These are commonly used on Niconico to bypass keyword filters.
     */
    internal fun applyLookAlikeTable(text: String): String {
        val sb = StringBuilder(text.length)
        for (ch in text) {
            sb.append(LOOK_ALIKE_TABLE.getOrDefault(ch, ch))
        }
        return sb.toString()
    }

    /**
     * Convert katakana characters to hiragana.
     * Covers the standard katakana range (U+30A1..U+30F6) and
     * common katakana marks.
     */
    internal fun katakanaToHiragana(text: String): String {
        val sb = StringBuilder(text.length)
        for (ch in text) {
            if (ch in '\u30A1'..'\u30F6') {
                // Standard katakana → hiragana (offset 0x60)
                sb.append(ch - 0x60)
            } else if (ch == '\u30F7') {
                // ヷ → わ (no direct hiragana, map to わ)
                sb.append('わ')
            } else if (ch == '\u30F8') {
                // ヸ → ゐ
                sb.append('ゐ')
            } else if (ch == '\u30F9') {
                // ヹ → ゑ
                sb.append('ゑ')
            } else if (ch == '\u30FA') {
                // ヺ → を
                sb.append('を')
            } else if (ch == '\u30FC') {
                // ー (katakana prolonged sound mark) → keep as-is for matching
                sb.append(ch)
            } else {
                sb.append(ch)
            }
        }
        return sb.toString()
    }

    /**
     * Remove whitespace, punctuation, and symbol characters.
     * Retains letters (including CJK), digits.
     */
    internal fun removeSpacesAndSymbols(text: String): String {
        val sb = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = Character.codePointAt(text, i)
            val charCount = Character.charCount(cp)
            if (isLetterOrDigit(cp)) {
                sb.appendCodePoint(cp)
            }
            i += charCount
        }
        return sb.toString()
    }

    private fun isLetterOrDigit(codePoint: Int): Boolean {
        val type = Character.getType(codePoint)
        return type == Character.UPPERCASE_LETTER.toInt() ||
            type == Character.LOWERCASE_LETTER.toInt() ||
            type == Character.TITLECASE_LETTER.toInt() ||
            type == Character.MODIFIER_LETTER.toInt() ||
            type == Character.OTHER_LETTER.toInt() ||
            type == Character.DECIMAL_DIGIT_NUMBER.toInt() ||
            type == Character.LETTER_NUMBER.toInt() ||
            type == Character.OTHER_NUMBER.toInt()
    }

    /**
     * Compress runs of 3+ identical characters to 2.
     * This handles evasion like "エエエロロロ" → "エエロロ" which still matches "エロ".
     *
     * We compress to 2 (not 1) to avoid false positives where repeated
     * characters are legitimate (e.g., "おおきい").
     */
    internal fun compressDuplicates(text: String): String {
        if (text.length < 3) return text
        val sb = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            val cp = Character.codePointAt(text, i)
            val charCount = Character.charCount(cp)

            // Count consecutive occurrences of this code point
            var count = 1
            var j = i + charCount
            while (j < text.length) {
                val nextCp = Character.codePointAt(text, j)
                if (nextCp != cp) break
                count++
                j += Character.charCount(nextCp)
            }

            // Output at most 2 copies
            val output = count.coerceAtMost(2)
            repeat(output) { sb.appendCodePoint(cp) }
            i = j
        }
        return sb.toString()
    }

    /**
     * Look-alike character mapping table.
     * Maps kanji/symbols that visually resemble katakana to their katakana form.
     * The katakana→hiragana step then unifies everything.
     */
    private val LOOK_ALIKE_TABLE: Map<Char, Char> = mapOf(
        '工' to 'エ',
        '口' to 'ロ',
        '力' to 'カ',
        '夕' to 'タ',
        '二' to 'ニ',
        '卜' to 'ト',
        '八' to 'ハ',
        '千' to 'チ',
        '十' to 'ジ',
        '人' to 'ヒ',
        '入' to 'イ',
        '匕' to 'ヒ',
        '乃' to 'ノ',
        '又' to 'マ',
        '丁' to 'テ',
        '己' to 'コ',
        '巳' to 'ミ',
        '也' to 'ヤ',
        '刀' to 'カ',
    )
}
