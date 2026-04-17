package app.spectacles_software.comerune.speech.domain.normalizer

import app.spectacles_software.comerune.speech.domain.model.NormalizedComment
import app.spectacles_software.comerune.speech.domain.model.RawComment
import app.spectacles_software.comerune.speech.domain.model.SpeechSettings

interface CommentNormalizer {
    fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment

    /**
     * Clears any cached regex patterns. Default no-op for implementations
     * that do not use a cache.
     */
    fun clearRegexCache() {}
}
