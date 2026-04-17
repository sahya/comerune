package app.spectacles_software.comerune.speech.domain.splitter

/**
 * A [TextSplitter] that does not split — returns the text as a single chunk.
 *
 * Used as the default when no language-specific splitter is configured.
 */
class NoOpTextSplitter : TextSplitter {
    override fun split(text: String): List<String> = listOf(text)
}
