package com.example.comerune.speech.domain.normalizer

import com.example.comerune.speech.domain.model.NormalizedComment
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechSettings

class DefaultCommentNormalizer : CommentNormalizer {

    override fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment {
        val preprocessed = preprocess(raw.text)

        val skipReason = detectSkipReason(preprocessed, settings)

        val priority = if (raw.isOwner) OWNER_PRIORITY else DEFAULT_PRIORITY

        return NormalizedComment(
            id = raw.id,
            originalText = raw.text,
            normalizedText = preprocessed,
            priority = priority,
            skipReason = skipReason
        )
    }

    /**
     * Preprocessing (spec Section 3.5.1):
     * 1. Replace newlines with space
     * 2. Replace tabs with space
     * 3. Remove control characters (chars below 0x20 except space)
     * 4. Collapse consecutive spaces to single space
     * 5. Trim leading/trailing whitespace
     */
    internal fun preprocess(text: String): String {
        return text
            .replace('\n', ' ')
            .replace('\r', ' ')
            .replace('\t', ' ')
            .filterNot { it < '\u0020' }
            .replace(CONSECUTIVE_SPACES, " ")
            .trim()
    }

    /**
     * Skip detection (spec Section 3.4):
     * - blank -> "blank"
     * - emoji only -> "emoji_only" (when settings.skipEmojiOnly)
     * - symbol only -> "symbol_only"
     */
    internal fun detectSkipReason(preprocessed: String, settings: SpeechSettings): String? {
        if (preprocessed.isEmpty()) {
            return SKIP_BLANK
        }

        if (settings.skipEmojiOnly && isEmojiOnly(preprocessed)) {
            return SKIP_EMOJI_ONLY
        }

        if (isSymbolOnly(preprocessed)) {
            return SKIP_SYMBOL_ONLY
        }

        return null
    }

    /**
     * Returns true if the text consists only of emoji characters and whitespace.
     * Covers common Unicode emoji ranges.
     */
    internal fun isEmojiOnly(text: String): Boolean {
        val stripped = text.replace(" ", "")
        if (stripped.isEmpty()) return false

        var i = 0
        while (i < stripped.length) {
            val codePoint = Character.codePointAt(stripped, i)
            if (!isEmojiCodePoint(codePoint)) {
                return false
            }
            i += Character.charCount(codePoint)
        }
        return true
    }

    /**
     * Returns true if the text has no letters, digits, or CJK characters.
     */
    internal fun isSymbolOnly(text: String): Boolean {
        val stripped = text.replace(" ", "")
        if (stripped.isEmpty()) return false

        var i = 0
        while (i < stripped.length) {
            val codePoint = Character.codePointAt(stripped, i)
            if (isReadableCodePoint(codePoint)) {
                return false
            }
            i += Character.charCount(codePoint)
        }
        return true
    }

    private fun isEmojiCodePoint(codePoint: Int): Boolean {
        return codePoint in 0x1F600..0x1F64F || // Emoticons
            codePoint in 0x1F300..0x1F5FF ||     // Misc Symbols and Pictographs
            codePoint in 0x1F680..0x1F6FF ||     // Transport and Map
            codePoint in 0x1F1E0..0x1F1FF ||     // Flags
            codePoint in 0x2600..0x26FF ||        // Misc symbols
            codePoint in 0x2700..0x27BF ||        // Dingbats
            codePoint in 0xFE00..0xFE0F ||        // Variation Selectors
            codePoint in 0x1F900..0x1F9FF ||     // Supplemental Symbols
            codePoint in 0x1FA00..0x1FA6F ||     // Chess Symbols / Extended-A
            codePoint in 0x1FA70..0x1FAFF ||     // Symbols Extended-A
            codePoint in 0x200D..0x200D ||        // ZWJ
            codePoint in 0x20E3..0x20E3 ||        // Combining Enclosing Keycap
            codePoint in 0xE0020..0xE007F         // Tags
    }

    private fun isReadableCodePoint(codePoint: Int): Boolean {
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

    companion object {
        private val CONSECUTIVE_SPACES = Regex(" {2,}")

        const val SKIP_BLANK = "blank"
        const val SKIP_EMOJI_ONLY = "emoji_only"
        const val SKIP_SYMBOL_ONLY = "symbol_only"

        private const val OWNER_PRIORITY = 10
        private const val DEFAULT_PRIORITY = 0
    }
}
