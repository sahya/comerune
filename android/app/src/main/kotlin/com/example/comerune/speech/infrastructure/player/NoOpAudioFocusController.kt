package com.example.comerune.speech.infrastructure.player

import android.media.AudioManager

/**
 * [AudioFocusController] that never actually requests focus from the
 * platform.
 *
 * Issue #931: comerune mixes its TTS with concurrent media (music,
 * video, navigation) instead of ducking them. Skipping the focus
 * request entirely is the simplest way to achieve mixing — the
 * platform sees no claim from us, so other apps keep their full
 * volume and we keep ours.
 *
 * Trade-off: comerune no longer receives platform focus-loss
 * callbacks during phone calls. That auto-silence path is replaced
 * by [com.example.comerune.speech.domain.audio.CallStateProvider]
 * checks at speak-dispatch time inside
 * [com.example.comerune.speech.domain.controller.SpeechControllerImpl].
 *
 * Returns [AudioManager.AUDIOFOCUS_REQUEST_GRANTED] so
 * [AndroidAudioFocusGuard] treats the request as immediately
 * successful and its surrounding wiring (listener registration,
 * scheduled release, idempotent acquire) keeps behaving consistently.
 */
internal class NoOpAudioFocusController : AudioFocusController {

    override fun request(): Int = AudioManager.AUDIOFOCUS_REQUEST_GRANTED

    override fun abandon(): Int = AudioManager.AUDIOFOCUS_REQUEST_GRANTED

    override fun setFocusChangeListener(listener: AudioFocusListener) {
        // No-op: we never registered with the platform AudioManager, so
        // no native focus callbacks can fire. Existing consumers (TTS
        // speaker, WAV players) still subscribe to AndroidAudioFocusGuard's
        // FocusChangeListener; those callbacks remain wired but are
        // never invoked because the guard has nothing to forward.
    }
}
