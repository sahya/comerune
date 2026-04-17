package app.spectacles_software.comerune.speech.domain.normalizer

import app.spectacles_software.comerune.speech.domain.model.NormalizedComment
import app.spectacles_software.comerune.speech.domain.model.RawComment
import app.spectacles_software.comerune.speech.domain.model.SpeechSettings

class DefaultCommentNormalizer(
    private val duplicateDetector: DuplicateDetector? = null,
    private val timeProvider: () -> Long = System::currentTimeMillis,
    private val presetNgWords: List<String> = emptyList()
) : CommentNormalizer {

    /** Pre-normalized preset NG words, computed once at construction time. */
    private val normalizedPresetNgWords: List<String> =
        presetNgWords.filter { it.isNotBlank() }.map { NgWordTextNormalizer.normalize(it) }

    /** Cache for user NG words normalization. Invalidated when the source list changes. */
    @Volatile
    private var cachedUserNgWordsSource: List<String> = emptyList()
    @Volatile
    private var cachedNormalizedUserNgWords: List<String> = emptyList()

    /** Cache of compiled Regex objects keyed by pattern string. Max 100 entries. */
    private val regexCache = java.util.concurrent.ConcurrentHashMap<String, Regex>()
    private val INVALID_REGEX_SENTINEL = Regex("(?!)")
    /** Shared executor for regex timeout scheduling. Single daemon thread, reused across calls. */
    private val regexTimeoutExecutor = java.util.concurrent.Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "regex-timeout").apply { isDaemon = true }
    }

    override fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment {
        // Step 1: Preprocessing (existing)
        val preprocessed = preprocess(raw.text)

        // Step 2: NG word check (on preprocessed text, before other transforms)
        val ngSkipReason = detectNgWord(preprocessed, settings)
        if (ngSkipReason != null) {
            val priority = if (raw.isOwner) OWNER_PRIORITY else DEFAULT_PRIORITY
            return NormalizedComment(
                id = raw.id,
                originalText = raw.text,
                normalizedText = preprocessed,
                priority = priority,
                skipReason = ngSkipReason
            )
        }

        // Step 3: URL processing
        val urlSkipReason = detectUrlSkipReason(preprocessed, settings)
        if (urlSkipReason != null) {
            val priority = if (raw.isOwner) OWNER_PRIORITY else DEFAULT_PRIORITY
            return NormalizedComment(
                id = raw.id,
                originalText = raw.text,
                normalizedText = preprocessed,
                priority = priority,
                skipReason = urlSkipReason
            )
        }
        val afterUrl = replaceUrls(preprocessed, settings)

        // Step 4: Symbol compression
        val afterSymbol = compressSymbols(afterUrl)

        // Step 5: Emoji processing
        val afterEmoji = removeEmoji(afterSymbol)

        // Step 6: Dictionary replacement
        val afterDict = applyDictionaryRules(afterEmoji, settings)

        // Step 7: Text length truncation
        val afterTruncate = truncateText(afterDict, settings)

        // Step 8: Skip detection
        // If symbol compression produced readable text but emoji removal left it blank,
        // use the post-symbol text instead.
        val finalText = if (afterTruncate.isBlank() && afterSymbol.isNotBlank()) {
            truncateText(applyDictionaryRules(afterSymbol, settings), settings)
        } else {
            afterTruncate
        }

        val skipReason = detectSkipReason(finalText, settings)

        val priority = if (raw.isOwner) OWNER_PRIORITY else DEFAULT_PRIORITY

        // Step 9: Duplicate detection (atomic check-and-record)
        if (duplicateDetector != null && skipReason == null) {
            val now = timeProvider()
            val isDup = duplicateDetector.checkAndRecord(finalText, raw.userId, now)
            if (isDup) {
                return NormalizedComment(
                    id = raw.id,
                    originalText = raw.text,
                    normalizedText = finalText,
                    priority = priority,
                    skipReason = SKIP_DUPLICATE
                )
            }
        }

        return NormalizedComment(
            id = raw.id,
            originalText = raw.text,
            normalizedText = finalText,
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

    /**
     * URL processing (spec Section 3.5.2):
     * Returns "url_only" skip reason if the entire comment is a URL and settings.skipUrlOnly is true.
     */
    internal fun detectUrlSkipReason(text: String, settings: SpeechSettings): String? {
        if (settings.skipUrlOnly && URL_PATTERN.matches(text)) {
            return SKIP_URL_ONLY
        }
        return null
    }

    /**
     * Replaces URLs in mixed text with settings.replaceUrlWith.
     */
    internal fun replaceUrls(text: String, settings: SpeechSettings): String {
        return URL_PATTERN.replace(text, settings.replaceUrlWith).trim()
    }

    /**
     * Symbol compression (spec Section 3.5.3):
     * Compresses repeated symbols into speech-friendly words.
     */
    internal fun compressSymbols(text: String): String {
        var result = text
        result = PATTERN_W.replace(result, "わらわら")
        result = PATTERN_KUSA.replace(result, "くさ")
        result = PATTERN_EIGHT.replace(result, "はくしゅ")
        result = PATTERN_EXCLAMATION.replace(result, "びっくり")
        result = PATTERN_QUESTION.replace(result, "はてな")
        result = PATTERN_PROLONGED.replace(result, "のばし")
        return result
    }

    /**
     * Emoji processing (spec Section 3.5.4):
     * Removes emoji characters from mixed text.
     */
    internal fun removeEmoji(text: String): String {
        val sb = StringBuilder()
        var i = 0
        while (i < text.length) {
            val codePoint = Character.codePointAt(text, i)
            val charCount = Character.charCount(codePoint)
            if (!isEmojiCodePoint(codePoint)) {
                sb.appendCodePoint(codePoint)
            }
            i += charCount
        }
        return sb.toString().trim()
    }

    /**
     * NG word check (spec Section 3.5.5):
     * Checks if preprocessed text contains any NG word (partial match, case-insensitive).
     * Returns "ng_word" skip reason if match found, null otherwise.
     *
     * Applies keyword-hack-resistant normalization via [NgWordTextNormalizer] to
     * defeat evasion techniques (space insertion, full/half-width mixing,
     * katakana/hiragana swapping, look-alike kanji, etc.).
     *
     * Both user-configured NG words and preset NG words are checked.
     */
    internal fun detectNgWord(text: String, settings: SpeechSettings): String? {
        // Build normalized user NG words with caching
        val userNgWords = if (settings.ngWords === cachedUserNgWordsSource || settings.ngWords == cachedUserNgWordsSource) {
            cachedNormalizedUserNgWords
        } else {
            val normalized = settings.ngWords.filter { it.isNotBlank() }.map { NgWordTextNormalizer.normalize(it) }
            cachedUserNgWordsSource = settings.ngWords
            cachedNormalizedUserNgWords = normalized
            normalized
        }

        val allNormalized = normalizedPresetNgWords + userNgWords
        if (allNormalized.isEmpty()) return null

        val normalizedText = NgWordTextNormalizer.normalize(text)

        return if (allNormalized.any { normalizedText.contains(it) }) {
            SKIP_NG_WORD
        } else {
            null
        }
    }

    /**
     * Dictionary replacement (spec Section 3.5.6):
     * Applies enabled dictionary rules in order. Each rule is a regex pattern → replacement.
     * Invalid regex patterns are silently skipped.
     */
    /**
     * Clears the compiled regex cache. Call this when dictionary rules change
     * to avoid stale entries accumulating.
     */
    override fun clearRegexCache() {
        regexCache.clear()
    }

    internal fun applyDictionaryRules(text: String, settings: SpeechSettings): String {
        if (settings.dictionaryRules.isEmpty()) return text
        var result = text
        for (rule in settings.dictionaryRules) {
            if (!rule.enabled) continue
            val regex = regexCache.getOrPut(rule.pattern) {
                if (regexCache.size >= MAX_REGEX_CACHE_SIZE) {
                    regexCache.clear()
                }
                runCatching { Regex(rule.pattern) }.getOrDefault(INVALID_REGEX_SENTINEL)
            }
            if (regex === INVALID_REGEX_SENTINEL) continue
            val safeReplacement = Regex.escapeReplacement(rule.replacement)
            result = try {
                // Use an interruptible CharSequence to guard against ReDoS.
                // If the regex takes longer than REGEX_TIMEOUT_MS, the thread is
                // interrupted and the replacement is skipped for this rule.
                val interruptible = InterruptibleCharSequence(result)
                val thread = Thread.currentThread()
                val timeoutFuture = regexTimeoutExecutor.schedule({
                    thread.interrupt()
                }, REGEX_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
                try {
                    regex.replace(interruptible, safeReplacement)
                } finally {
                    timeoutFuture.cancel(false)
                    Thread.interrupted() // Clear interrupt flag
                }
            } catch (_: RuntimeException) {
                // Catches interrupt-based timeout from InterruptibleCharSequence
                result
            } catch (_: StackOverflowError) {
                // Catches deeply nested regex backtracking
                result
            }
        }
        return result
    }

    /** CharSequence wrapper that throws on access when the thread is interrupted. */
    private class InterruptibleCharSequence(private val inner: CharSequence) : CharSequence {
        override val length: Int get() = inner.length
        override fun get(index: Int): Char {
            if (Thread.currentThread().isInterrupted) {
                throw RuntimeException("Regex execution timed out")
            }
            return inner[index]
        }
        override fun subSequence(startIndex: Int, endIndex: Int): CharSequence =
            InterruptibleCharSequence(inner.subSequence(startIndex, endIndex))
        override fun toString(): String = inner.toString()
    }

    /**
     * Text length truncation (spec Section 3.5.7):
     * If text exceeds maxTextLength, truncates and appends trimLongTextSuffix.
     */
    internal fun truncateText(text: String, settings: SpeechSettings): String {
        val maxLen = settings.maxTextLength.coerceAtLeast(1)
        val codePointCount = text.codePointCount(0, text.length)
        return if (codePointCount > maxLen) {
            val endIndex = text.offsetByCodePoints(0, maxLen)
            text.substring(0, endIndex) + settings.trimLongTextSuffix
        } else {
            text
        }
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
        private const val MAX_REGEX_CACHE_SIZE = 100
        /** Timeout for a single dictionary regex replacement (milliseconds). */
        private const val REGEX_TIMEOUT_MS = 500L

        private val CONSECUTIVE_SPACES = Regex(" {2,}")

        // URL pattern (spec Section 3.5.2)
        //
        // スキーム付き URL (`https?://...`) に加えて、スキーム無しの
        // bare URL (`www.example.com` / `ｗｗｗ.example.com` 等) もここで検出して
        // `URL省略` に置き換える。後段の symbol compression (`PATTERN_W`) が
        // `www` を「わらわら」に変換する前に URL 部分を潰すことで、
        // `www.google.com` が「わらわらエグザンプル…」のように読まれるのを
        // 防ぐ。
        //
        // bare URL 部分は 2 文字以上の半角/全角 `w` + `.` + URL 本体 (ASCII
        // 英数字・記号) の形。直前が英数字の場合（例: `abwww.com` のような
        // 語尾に w が偶然続くケース）は URL として扱わず、そのまま symbol
        // compression に流す。
        internal val URL_PATTERN = Regex(
            """(?:https?://|(?<![a-zA-Z0-9])[wWｗＷ]{2,}\.)[\w/:%#$&?()~.=+\-]+""",
        )

        // Symbol compression patterns (spec Section 3.5.3)
        // PATTERN_W は半角 w/W に加えて全角 ｗ/Ｗ もカバーする。これにより
        // `おはようｗｗ やったね` のように全角ｗが文中にある場合も「わらわら」
        // に圧縮される（URL_PATTERN と同じキャラクタークラス）。
        private val PATTERN_W = Regex("""[wWｗＷ]{2,}""")
        private val PATTERN_KUSA = Regex("""草{2,}""")
        private val PATTERN_EIGHT = Regex("""[8８]{3,}""")
        private val PATTERN_EXCLAMATION = Regex("""[!！]{2,}""")
        private val PATTERN_QUESTION = Regex("""[?？]{2,}""")
        private val PATTERN_PROLONGED = Regex("""[ー～〜]{3,}""")

        const val SKIP_BLANK = "blank"
        const val SKIP_EMOJI_ONLY = "emoji_only"
        const val SKIP_SYMBOL_ONLY = "symbol_only"
        const val SKIP_URL_ONLY = "url_only"
        const val SKIP_DUPLICATE = "duplicate"
        const val SKIP_NG_WORD = "ng_word"

        private const val OWNER_PRIORITY = 10
        private const val DEFAULT_PRIORITY = 0
    }
}
