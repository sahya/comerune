package com.example.comerune.speech.infrastructure.audio

import android.content.Context
import android.media.AudioManager
import com.example.comerune.speech.domain.audio.CallStateProvider

/**
 * AudioManager.mode-based call detector.
 *
 * Returns true for MODE_IN_CALL (cellular), MODE_IN_COMMUNICATION
 * (VoIP / IP telephony) and MODE_RINGTONE (incoming ring). Covering
 * the ring state lets the caller mute TTS the moment the device
 * starts ringing instead of waiting for the user to answer.
 *
 * AudioManager.mode is preferred over TelephonyManager.callState
 * because it works for both cellular and VoIP and does NOT require
 * the READ_PHONE_STATE runtime permission. Some OEMs flip mode a
 * few hundred milliseconds after the ringtone starts; for comerune's
 * comment-reading use case that latency is acceptable since the
 * user is unlikely to miss a comment under the ringtone.
 */
class AndroidCallStateProvider(
    private val audioManager: AudioManager,
) : CallStateProvider {

    constructor(context: Context) : this(
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager,
    )

    override fun isInCall(): Boolean {
        val mode = audioManager.mode
        return mode == AudioManager.MODE_IN_CALL ||
            mode == AudioManager.MODE_IN_COMMUNICATION ||
            mode == AudioManager.MODE_RINGTONE
    }
}
