package com.example.comerune.speech.domain.splitter

/**
 * Splits Japanese text at conjunctive particle (接続助詞) boundaries
 * to reduce time-to-first-audio in TTS pipelines.
 *
 * Only conjunctive particles that mark clause boundaries are used as
 * split points. Case particles and adverbial particles are excluded
 * to avoid over-fragmentation.
 *
 * When a particle is followed by punctuation (「、」「。」), the split
 * point is treated as high-priority. When the number of split points
 * exceeds [maxChunks], high-priority (punctuation-backed) points are
 * preferred over particle-only points.
 */
class JapaneseTextSplitter(
    private val minChunkLength: Int = MIN_CHUNK_LENGTH_DEFAULT,
    private val minTextLength: Int = MIN_TEXT_LENGTH_DEFAULT,
    private val maxChunks: Int = MAX_CHUNKS_DEFAULT
) : TextSplitter {

    companion object {
        /** Minimum chunk length in code points. Shorter chunks are merged. */
        const val MIN_CHUNK_LENGTH_DEFAULT = 5

        /** Texts shorter than this (in code points) are not split. */
        const val MIN_TEXT_LENGTH_DEFAULT = 15

        /** Maximum number of chunks produced from a single text. */
        const val MAX_CHUNKS_DEFAULT = 5

        /**
         * Regex matching conjunctive particles at clause boundaries.
         *
         * Target particles (接続助詞):
         *   けれども、けれど、けど、だけど、だから、から、ので、のに、
         *   たら、ても、でも、って、し
         *
         * Excluded: 「が」 — listed in the Issue as both a conjunctive
         * particle (接続) and a case particle (主格). Disambiguating
         * the two usages requires morphological analysis, which is out
         * of scope for this regex-based approach. Including 「が」 would
         * cause excessive splitting on the very common subject-marker
         * usage, degrading audio quality.
         *
         * The pattern matches these particles when they appear after
         * hiragana/katakana/kanji characters (to reduce false positives).
         *
         * Ordering matters: longer alternatives must precede shorter ones
         * (e.g. けれども before けれど before けど).
         */
        /**
         * Main pattern for multi-character particles.
         *
         * Optionally followed by a punctuation mark (、。) which is
         * included in the match so the split point falls after the
         * punctuation — keeping "から、" together in the first chunk.
         */
        private val MULTI_CHAR_PATTERN = Regex(
            "(?<=[\\p{InHiragana}\\p{InKatakana}\\p{InCJKUnifiedIdeographs}ー])" +
                "(けれども|けれど|だけど|だから|けど|ので|のに|たら|ても|でも|って|から)" +
                "[、。]?" +
                "(?=.)"
        )

        /**
         * Pattern for the single-character particle 「し」.
         *
         * To avoid false matches on い-adjective stems (楽しい, 美しい, 嬉しい),
         * 「し」 is only matched when preceded by characters that typically
         * end a clause before the conjunctive し (e.g. いし, だし, でし, たし,
         * もし) and NOT followed by い-adjective inflections (い, く, さ, か, っ).
         *
         * Optionally followed by punctuation (、。).
         */
        private val SHI_PARTICLE_PATTERN = Regex(
            "(?<=[いだでもた])し(?![いくさかっ])[、。]?(?=.)"
        )

        private const val PUNCTUATION_CHARS = "、。"
    }

    /**
     * A candidate split point with its character index and whether
     * it was confirmed by trailing punctuation.
     */
    internal data class SplitCandidate(
        val index: Int,
        val hasPunctuation: Boolean
    )

    /**
     * Split [text] at conjunctive particle boundaries.
     *
     * Returns a list containing one or more chunks. The original text
     * is always fully represented by concatenating the returned chunks.
     *
     * @param text Normalized comment text to split.
     * @return List of text chunks (never empty).
     */
    override fun split(text: String): List<String> {
        if (text.codePointCount(0, text.length) <= minTextLength) {
            return listOf(text)
        }

        val candidates = findSplitCandidates(text)
        if (candidates.isEmpty()) {
            return listOf(text)
        }

        val selected = selectSplitPoints(candidates)
        val chunks = splitAtPoints(text, selected)
        val merged = mergeShortChunks(chunks)

        return limitChunks(merged)
    }

    /**
     * Find character indices where the text can be split.
     * Each index points to the character immediately after the particle
     * (and its optional trailing punctuation).
     */
    internal fun findSplitCandidates(text: String): List<SplitCandidate> {
        val candidateMap = mutableMapOf<Int, Boolean>()

        for (match in MULTI_CHAR_PATTERN.findAll(text)) {
            val index = match.range.last + 1
            val matchedText = match.value
            val hasPunct = matchedText.last() in PUNCTUATION_CHARS
            // If same index already exists, keep the one with punctuation
            candidateMap[index] = candidateMap.getOrDefault(index, false) || hasPunct
        }
        for (match in SHI_PARTICLE_PATTERN.findAll(text)) {
            val index = match.range.last + 1
            val matchedText = match.value
            val hasPunct = matchedText.last() in PUNCTUATION_CHARS
            candidateMap[index] = candidateMap.getOrDefault(index, false) || hasPunct
        }

        return candidateMap.entries
            .map { SplitCandidate(it.key, it.value) }
            .sortedBy { it.index }
    }

    /**
     * Backward-compatible alias for tests that only need indices.
     */
    internal fun findSplitPoints(text: String): List<Int> =
        findSplitCandidates(text).map { it.index }

    /**
     * Select which split points to use. When there are more candidates
     * than [maxChunks] - 1 allows, prefer punctuation-backed candidates.
     */
    private fun selectSplitPoints(candidates: List<SplitCandidate>): List<Int> {
        val maxSplits = maxChunks - 1
        if (candidates.size <= maxSplits) {
            return candidates.map { it.index }
        }

        // Separate into high-priority (punctuation) and low-priority (particle only)
        val withPunct = candidates.filter { it.hasPunctuation }
        val withoutPunct = candidates.filter { !it.hasPunctuation }

        val selected = mutableListOf<SplitCandidate>()

        // Take punctuation-backed candidates first
        selected.addAll(withPunct.take(maxSplits))

        // Fill remaining slots with particle-only candidates
        val remaining = maxSplits - selected.size
        if (remaining > 0) {
            selected.addAll(withoutPunct.take(remaining))
        }

        // Return sorted by position to maintain text order
        return selected.sortedBy { it.index }.map { it.index }
    }

    private fun splitAtPoints(text: String, points: List<Int>): List<String> {
        val chunks = mutableListOf<String>()
        var start = 0
        for (point in points) {
            if (point > start && point < text.length) {
                chunks.add(text.substring(start, point))
                start = point
            }
        }
        // Add the remaining text
        if (start < text.length) {
            chunks.add(text.substring(start))
        }
        return chunks
    }

    /**
     * Merge chunks that are shorter than [minChunkLength] code points
     * into adjacent chunks.
     */
    private fun mergeShortChunks(chunks: List<String>): List<String> {
        if (chunks.size <= 1) return chunks

        val result = mutableListOf<String>()
        var buffer = chunks[0]

        for (i in 1 until chunks.size) {
            val chunk = chunks[i]
            if (buffer.codePointCount(0, buffer.length) < minChunkLength) {
                // Current buffer is too short — merge with next chunk
                buffer += chunk
            } else if (chunk.codePointCount(0, chunk.length) < minChunkLength) {
                // Next chunk is too short — merge into current buffer
                buffer += chunk
            } else {
                result.add(buffer)
                buffer = chunk
            }
        }
        result.add(buffer)
        return result
    }

    /**
     * If there are more chunks than [maxChunks], merge trailing chunks
     * into the last allowed chunk.
     */
    private fun limitChunks(chunks: List<String>): List<String> {
        if (chunks.size <= maxChunks) return chunks

        val limited = chunks.take(maxChunks - 1).toMutableList()
        limited.add(chunks.drop(maxChunks - 1).joinToString(""))
        return limited
    }
}
