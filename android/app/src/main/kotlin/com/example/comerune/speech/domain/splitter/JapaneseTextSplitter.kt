package com.example.comerune.speech.domain.splitter

/**
 * Splits Japanese text at conjunctive particle (接続助詞) boundaries
 * to reduce time-to-first-audio in TTS pipelines.
 *
 * Only conjunctive particles that mark clause boundaries are used as
 * split points. Case particles and adverbial particles are excluded
 * to avoid over-fragmentation.
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
        const val MAX_CHUNKS_DEFAULT = 3

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
        private val PARTICLE_PATTERN = Regex(
            "(?<=[\\p{InHiragana}\\p{InKatakana}\\p{InCJKUnifiedIdeographs}ー])" +
                "(けれども|けれど|だけど|だから|けど|ので|のに|たら|ても|でも|って|から|し)" +
                "(?=.)"
        )
    }

    /**
     * Split [text] at conjunctive particle boundaries.
     *
     * Returns a list containing one or more chunks. The original text
     * is always fully represented by concatenating the returned chunks.
     *
     * @param text Normalized comment text to split.
     * @return List of text chunks (never empty).
     */
    fun split(text: String): List<String> {
        if (text.codePointCount(0, text.length) <= minTextLength) {
            return listOf(text)
        }

        val candidates = findSplitPoints(text)
        if (candidates.isEmpty()) {
            return listOf(text)
        }

        val chunks = splitAtPoints(text, candidates)
        val merged = mergeShortChunks(chunks)

        return limitChunks(merged)
    }

    /**
     * Find character indices where the text can be split.
     * Each index points to the character immediately after the particle.
     */
    internal fun findSplitPoints(text: String): List<Int> {
        val points = mutableListOf<Int>()
        val matches = PARTICLE_PATTERN.findAll(text)
        for (match in matches) {
            // Split point is after the particle
            points.add(match.range.last + 1)
        }
        return points
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
