package com.example.comerune.speech.domain.splitter

/**
 * Splits text into chunks for pipelined TTS synthesis.
 *
 * Implementations decide where to split based on language-specific
 * rules (e.g. conjunctive particles in Japanese).
 */
interface TextSplitter {
    /**
     * Split [text] into one or more chunks.
     *
     * Concatenating the returned chunks must reproduce the original [text].
     *
     * @return List of text chunks (never empty).
     */
    fun split(text: String): List<String>
}
