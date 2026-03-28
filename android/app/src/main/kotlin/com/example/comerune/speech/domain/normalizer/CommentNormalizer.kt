package com.example.comerune.speech.domain.normalizer

import com.example.comerune.speech.domain.model.NormalizedComment
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechSettings

interface CommentNormalizer {
    fun normalize(raw: RawComment, settings: SpeechSettings): NormalizedComment
}
