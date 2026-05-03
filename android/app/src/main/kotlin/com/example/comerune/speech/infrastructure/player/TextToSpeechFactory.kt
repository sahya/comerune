package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Thin seam around [android.speech.tts.TextToSpeech] so the Android
 * framework dependency can be swapped with a fake in JVM unit tests.
 *
 * Only the subset of the TextToSpeech API actually used by
 * [AndroidTtsSpeaker] is exposed. Adding methods here should remain a
 * trivial 1:1 delegation in the real adapter.
 */
interface TextToSpeechFactory {
    /**
     * Creates a new [TextToSpeechAdapter].  [onInit] is invoked with the
     * status code reported by the underlying engine
     * ([TextToSpeech.SUCCESS] or [TextToSpeech.ERROR]).
     */
    fun create(onInit: (Int) -> Unit): TextToSpeechAdapter
}

/**
 * Adapter over [android.speech.tts.TextToSpeech] that exposes the methods
 * used by [AndroidTtsSpeaker]. Mirrors the real API 1:1 so the production
 * implementation stays a trivial delegation.
 */
interface TextToSpeechAdapter {
    fun setLanguage(locale: Locale): Int

    fun setSpeechRate(rate: Float): Int

    fun setPitch(pitch: Float): Int

    /** Applies the shared speech audio-attributes profile to the engine. */
    fun setSpeechAudioAttributes(): Int

    fun speak(
        text: String,
        queueMode: Int,
        params: Bundle?,
        utteranceId: String,
    ): Int

    fun stop(): Int

    fun shutdown()

    fun setOnUtteranceProgressListener(listener: UtteranceProgressListener): Int
}

/** Default factory that delegates to the real Android [TextToSpeech]. */
class DefaultTextToSpeechFactory(private val context: Context) : TextToSpeechFactory {
    override fun create(onInit: (Int) -> Unit): TextToSpeechAdapter {
        val tts = TextToSpeech(context) { status -> onInit(status) }
        return RealTextToSpeechAdapter(tts)
    }
}

/**
 * Production adapter that forwards calls to the wrapped [TextToSpeech]
 * instance and lazily builds the shared speech audio profile only on
 * Android runtimes that can provide a concrete [AudioAttributes].
 */
private class RealTextToSpeechAdapter(
    private val tts: TextToSpeech,
) : TextToSpeechAdapter {
    override fun setLanguage(locale: Locale): Int = tts.setLanguage(locale)

    override fun setSpeechRate(rate: Float): Int = tts.setSpeechRate(rate)

    override fun setPitch(pitch: Float): Int = tts.setPitch(pitch)

    override fun setSpeechAudioAttributes(): Int {
        val attributes = try {
            AudioAttributes.Builder().apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setUsage(AudioAttributes.USAGE_ASSISTANT)
                } else {
                    setUsage(AudioAttributes.USAGE_MEDIA)
                }
                setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            }.build()
        } catch (_: RuntimeException) {
            return TextToSpeech.ERROR
        }
        return tts.setAudioAttributes(attributes)
    }

    override fun speak(
        text: String,
        queueMode: Int,
        params: Bundle?,
        utteranceId: String,
    ): Int = tts.speak(text, queueMode, params, utteranceId)

    override fun stop(): Int = tts.stop()

    override fun shutdown() {
        tts.shutdown()
    }

    override fun setOnUtteranceProgressListener(listener: UtteranceProgressListener): Int =
        tts.setOnUtteranceProgressListener(listener)
}
