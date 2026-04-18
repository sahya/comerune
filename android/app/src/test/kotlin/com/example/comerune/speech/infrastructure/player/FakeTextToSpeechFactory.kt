package com.example.comerune.speech.infrastructure.player

import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Test seam that lets unit tests observe how [AndroidTtsSpeaker] drives the
 * [TextToSpeechFactory] / [TextToSpeechAdapter] pair without pulling in the
 * Android framework. Each [create] call records the engine it produced so
 * tests can assert on init / shutdown ordering.
 *
 * The fake fires the init callback **asynchronously** via
 * [completePendingInit] / [completeAllPendingInits] so tests can interleave
 * actions between `factory.create(...)` and the init completion — matching
 * how the real `TextToSpeech` constructor defers its callback.
 */
class FakeTextToSpeechFactory(
    private val defaultLanguageResult: Int = TextToSpeech.LANG_AVAILABLE,
) : TextToSpeechFactory {

    val createdEngines: MutableList<FakeTextToSpeechAdapter> = CopyOnWriteArrayList()

    val createCount: Int get() = createdEngines.size

    /**
     * Engines whose init callback has not yet fired. Tests call
     * [completePendingInit] to drive them to SUCCESS (or other status).
     */
    private val pending: MutableList<PendingInit> = CopyOnWriteArrayList()

    private data class PendingInit(
        val engine: FakeTextToSpeechAdapter,
        val onInit: (Int) -> Unit,
    )

    override fun create(onInit: (Int) -> Unit): TextToSpeechAdapter {
        val engine = FakeTextToSpeechAdapter(defaultLanguageResult = defaultLanguageResult)
        createdEngines.add(engine)
        pending.add(PendingInit(engine, onInit))
        return engine
    }

    /**
     * Fires the init callback for the oldest still-pending engine.
     * Returns the engine whose init was completed, or `null` if none is
     * pending.
     */
    fun completePendingInit(status: Int = TextToSpeech.SUCCESS): FakeTextToSpeechAdapter? {
        if (pending.isEmpty()) return null
        val next = pending.removeAt(0)
        next.onInit(status)
        return next.engine
    }

    /** Fires init callbacks for every engine created so far. */
    fun completeAllPendingInits(status: Int = TextToSpeech.SUCCESS) {
        while (completePendingInit(status) != null) {
            // loop
        }
    }

    fun hasPendingInit(): Boolean = pending.isNotEmpty()
}

/**
 * Records every call the production code makes against the adapter so
 * tests can assert the exact sequence (setLanguage → setSpeechRate →
 * setPitch → setOnUtteranceProgressListener → …) as well as shutdown().
 */
class FakeTextToSpeechAdapter(
    private val defaultLanguageResult: Int = TextToSpeech.LANG_AVAILABLE,
) : TextToSpeechAdapter {

    private val shutdownCounter = AtomicInteger(0)
    private val stopCounter = AtomicInteger(0)
    private val setLanguageCalls: MutableList<Locale> = CopyOnWriteArrayList()
    private val setSpeechRateCalls: MutableList<Float> = CopyOnWriteArrayList()
    private val setPitchCalls: MutableList<Float> = CopyOnWriteArrayList()
    private val progressListeners: MutableList<UtteranceProgressListener> = CopyOnWriteArrayList()

    @Volatile
    private var pendingLanguageResult: Int = defaultLanguageResult

    val shutdownCount: Int get() = shutdownCounter.get()

    val stopCount: Int get() = stopCounter.get()

    val languages: List<Locale> get() = setLanguageCalls.toList()

    val speechRates: List<Float> get() = setSpeechRateCalls.toList()

    val pitches: List<Float> get() = setPitchCalls.toList()

    val registeredProgressListeners: List<UtteranceProgressListener>
        get() = progressListeners.toList()

    /** Overrides the value [setLanguage] returns on the next invocation. */
    fun setLanguageResultOverride(result: Int) {
        pendingLanguageResult = result
    }

    override fun setLanguage(locale: Locale): Int {
        setLanguageCalls.add(locale)
        return pendingLanguageResult
    }

    override fun setSpeechRate(rate: Float): Int {
        setSpeechRateCalls.add(rate)
        return TextToSpeech.SUCCESS
    }

    override fun setPitch(pitch: Float): Int {
        setPitchCalls.add(pitch)
        return TextToSpeech.SUCCESS
    }

    override fun speak(
        text: String,
        queueMode: Int,
        params: Bundle?,
        utteranceId: String,
    ): Int = TextToSpeech.SUCCESS

    override fun stop(): Int {
        stopCounter.incrementAndGet()
        return TextToSpeech.SUCCESS
    }

    override fun shutdown() {
        shutdownCounter.incrementAndGet()
    }

    override fun setOnUtteranceProgressListener(listener: UtteranceProgressListener): Int {
        progressListeners.add(listener)
        return TextToSpeech.SUCCESS
    }
}
