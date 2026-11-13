package com.example.comerune.speech.infrastructure.player

import android.media.AudioManager

/**
 * [AudioFocusController] that picks, per request, whether comerune claims
 * audio focus from the platform or plays without claiming it.
 *
 * Issue #1014 (follow-up to #931): users choose between two modes from
 * the speech settings screen.
 * - `duckOtherAudio = false` (default): delegate to [mixController]
 *   (a [NoOpAudioFocusController]). Other media keeps its full volume and
 *   comerune's speech plays on top of it — the v1.3.0 behaviour.
 * - `duckOtherAudio = true`: delegate to [focusController] (a
 *   [RealAudioFocusController]). Each utterance requests
 *   `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`, so other media is ducked or
 *   paused while comerune speaks — the pre-#931 behaviour.
 *
 * The delegate that served the last successful request is remembered so
 * [abandon] always goes to the same delegate, even if the mode changed
 * while focus was held. Without this, switching modes mid-session could
 * leave a real focus token on the platform that nothing ever abandons.
 *
 * Threading: [AndroidAudioFocusGuard] calls [request] / [abandon] under
 * its own lock. [setDuckOtherAudio] may be called from any thread; the
 * mode is read once per [request].
 */
internal class SwitchableAudioFocusController(
    private val focusController: AudioFocusController,
    private val mixController: AudioFocusController = NoOpAudioFocusController(),
    initialDuckOtherAudio: Boolean = false,
) : AudioFocusController {

    @Volatile
    private var duckOtherAudio: Boolean = initialDuckOtherAudio

    /** Delegate that granted the currently held focus; null if none. */
    @Volatile
    private var grantedBy: AudioFocusController? = null

    val isDuckingOtherAudio: Boolean get() = duckOtherAudio

    /**
     * Switch the mode used by the next [request].
     *
     * Returns true when the mode actually changed, so the caller knows it
     * should release any focus held under the previous mode.
     */
    fun setDuckOtherAudio(enabled: Boolean): Boolean {
        if (duckOtherAudio == enabled) return false
        duckOtherAudio = enabled
        return true
    }

    override fun request(): Int {
        val delegate = if (duckOtherAudio) focusController else mixController
        val response = delegate.request()
        if (response == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ||
            response == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
        ) {
            grantedBy = delegate
        }
        return response
    }

    override fun abandon(): Int {
        val delegate = grantedBy ?: return AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        grantedBy = null
        return delegate.abandon()
    }

    override fun setFocusChangeListener(listener: AudioFocusListener) {
        // Both delegates forward to the same guard listener. Only the real
        // controller can actually deliver callbacks, and only while it
        // holds a platform focus token.
        focusController.setFocusChangeListener(listener)
        mixController.setFocusChangeListener(listener)
    }
}
