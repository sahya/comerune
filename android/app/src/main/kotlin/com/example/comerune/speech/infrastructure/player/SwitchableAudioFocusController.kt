package com.example.comerune.speech.infrastructure.player

import android.media.AudioManager
import com.example.comerune.speech.domain.player.AudioFocusGuard

/**
 * [AudioFocusController] that picks, per request, whether comerune claims
 * audio focus from the platform or plays without claiming it.
 *
 * Issue #1014 (follow-up to #931): users choose between two modes from
 * the speech settings screen.
 * - `duckOtherAudio = false` (default): delegate to [mixController]
 *   (a [NoOpAudioFocusController]). Other media keeps its full volume and
 *   comerune's speech plays on top of it — the v1.3.0 behaviour.
 * - `duckOtherAudio = true`: delegate to [duckController] (a
 *   [RealAudioFocusController] on API 26+). When [AndroidAudioFocusGuard]
 *   acquires focus it requests `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK` and
 *   keeps the token across the release grace period, so other media is
 *   ducked or paused while comerune speaks — the pre-#931 behaviour.
 *
 * The delegate that served the last successful request is remembered so
 * [abandon] always goes to the same delegate, even if the mode changed
 * while focus was held. Without this, switching modes mid-session could
 * leave a real focus token on the platform that nothing ever abandons.
 *
 * Threading: [AndroidAudioFocusGuard] calls [request] / [abandon] under
 * its own lock. [setDuckOtherAudio] and [notifyFocusRestored] are called
 * from the main thread, where the platform also delivers focus callbacks.
 */
internal class SwitchableAudioFocusController(
    private val duckController: AudioFocusController,
    private val mixController: AudioFocusController = NoOpAudioFocusController(),
    initialDuckOtherAudio: Boolean = false,
) : AudioFocusController {

    @Volatile
    private var duckOtherAudio: Boolean = initialDuckOtherAudio

    /** Delegate that granted the currently held focus; null if none. */
    @Volatile
    private var grantedBy: AudioFocusController? = null

    /** The guard's listener, kept so [notifyFocusRestored] can reach it. */
    @Volatile
    private var listener: AudioFocusListener? = null

    /**
     * True while consumers may be waiting for `AUDIOFOCUS_GAIN`: after a
     * transient loss, or while a DELAYED request is pending. Only then is a
     * synthetic GAIN safe — at other times a WAV player can be between
     * `shouldBePlaying = true` and `prepare()`, and a stray GAIN would start
     * it too early and drop that utterance.
     */
    @Volatile
    private var awaitingGain: Boolean = false

    /** Sits between the delegates and the guard to track [awaitingGain]. */
    private val trackingListener = object : AudioFocusListener {
        override fun onFocusChange(rawFocusChange: Int) {
            when (rawFocusChange) {
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> awaitingGain = true
                AudioManager.AUDIOFOCUS_GAIN,
                AudioManager.AUDIOFOCUS_LOSS -> awaitingGain = false
            }
            listener?.onFocusChange(rawFocusChange)
        }
    }

    /** The configured mode (not whether other audio is ducked right now). */
    val duckOtherAudioEnabled: Boolean get() = duckOtherAudio

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

    /**
     * Deliver a synthetic `AUDIOFOCUS_GAIN` to the guard if consumers may be
     * waiting for one. Returns true when a GAIN was delivered.
     *
     * Used when leaving duck mode: a WAV player paused by a transient loss
     * waits for GAIN, but after the real token is abandoned the platform
     * never sends one. In mix mode comerune ignores focus, so it is safe to
     * let those consumers resume. A DELAYED acquire still waiting is
     * completed the same way.
     */
    fun notifyFocusRestored(): Boolean {
        if (!awaitingGain) return false
        trackingListener.onFocusChange(AudioManager.AUDIOFOCUS_GAIN)
        return true
    }

    override fun request(): Int {
        val delegate = if (duckOtherAudio) duckController else mixController
        val response = delegate.request()
        when (response) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> grantedBy = delegate
            AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> {
                grantedBy = delegate
                awaitingGain = true
            }
        }
        return response
    }

    override fun abandon(): Int {
        awaitingGain = false
        val delegate = grantedBy ?: return AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        grantedBy = null
        return delegate.abandon()
    }

    override fun setFocusChangeListener(listener: AudioFocusListener) {
        this.listener = listener
        // Only the real controller can actually deliver callbacks, and only
        // while it holds a platform focus token.
        duckController.setFocusChangeListener(trackingListener)
        mixController.setFocusChangeListener(trackingListener)
    }
}

/**
 * Apply a "duck other audio" setting to [controller] and [guard].
 *
 * Returns true when the mode changed. On a change, any focus held under the
 * previous mode is released right away so the next utterance requests
 * focus (or skips it) under the new mode instead of reusing a stale token
 * for up to the release grace period.
 *
 * When leaving duck mode, consumers waiting for focus are told it is back
 * *before* the real token is abandoned, so a player paused by a transient
 * loss resumes instead of waiting forever for a GAIN that will never arrive.
 */
internal fun applyDuckOtherAudioMode(
    controller: SwitchableAudioFocusController,
    guard: AudioFocusGuard,
    enabled: Boolean,
): Boolean {
    if (!controller.setDuckOtherAudio(enabled)) return false
    if (!enabled) controller.notifyFocusRestored()
    guard.release()
    return true
}
