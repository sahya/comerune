package com.example.comerune.speech.infrastructure.player

import android.content.Context
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
 * Production adapter that forwards every call to the wrapped
 * [TextToSpeech] instance. Intentionally kept free of conditional logic
 * so it stays obviously correct by inspection.
 */
private class RealTextToSpeechAdapter(
    private val tts: TextToSpeech,
) : TextToSpeechAdapter {
    override fun setLanguage(locale: Locale): Int = tts.setLanguage(locale)

    override fun setSpeechRate(rate: Float): Int = tts.setSpeechRate(rate)

    override fun setPitch(pitch: Float): Int = tts.setPitch(pitch)

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
