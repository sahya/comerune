package com.example.comerune.speech.domain.audio

/**
 * Reports whether the device is currently engaged in a phone call.
 *
 * Issue #931 removed the per-utterance AudioFocus request so comerune
 * mixes its TTS with concurrent media (music, video, navigation)
 * instead of ducking them. The previous design relied on the platform
 * delivering AUDIOFOCUS_LOSS_TRANSIENT when telephony took focus to
 * automatically silence the speaker; with no focus request, that
 * signal no longer arrives, so call-mute is implemented by checking
 * this provider at speak-dispatch time and skipping the utterance.
 */
interface CallStateProvider {
    fun isInCall(): Boolean
}
