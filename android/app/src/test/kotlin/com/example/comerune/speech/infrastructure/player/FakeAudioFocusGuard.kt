package com.example.comerune.speech.infrastructure.player

import com.example.comerune.speech.domain.player.AudioFocusGuard
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Deterministic [AudioFocusGuard] used by WAV player and TTS speaker
 * unit tests.
 *
 * Tracks acquire / scheduleRelease / release counts so tests can assert
 * the exact focus pattern (one acquire per utterance, deferred release
 * afterwards, no per-utterance churn). Listeners can be driven manually
 * via [emit] to exercise focus-loss / focus-gain code paths without an
 * Android runtime.
 */
class FakeAudioFocusGuard(
    /** Result returned by [acquire]. Default = success. */
    var acquireResult: Result<Unit> = Result.success(Unit),
) : AudioFocusGuard {

    private val acquireCounter = AtomicInteger(0)
    private val scheduleReleaseCounter = AtomicInteger(0)
    private val releaseCounter = AtomicInteger(0)
    private val listeners: MutableList<AudioFocusGuard.FocusChangeListener> =
        CopyOnWriteArrayList()

    @Volatile
    private var heldInternal: Boolean = false

    val acquireCount: Int get() = acquireCounter.get()
    val scheduleReleaseCount: Int get() = scheduleReleaseCounter.get()
    val releaseCount: Int get() = releaseCounter.get()
    val listenerCount: Int get() = listeners.size

    override val isHeld: Boolean get() = heldInternal

    override suspend fun acquire(): Result<Unit> {
        acquireCounter.incrementAndGet()
        if (acquireResult.isSuccess) {
            heldInternal = true
        }
        return acquireResult
    }

    override fun release() {
        releaseCounter.incrementAndGet()
        heldInternal = false
    }

    override fun scheduleRelease(graceMs: Long) {
        scheduleReleaseCounter.incrementAndGet()
        // Stay held: scheduleRelease defers, so heldInternal stays true
        // until the grace window elapses or the next acquire is made.
    }

    override fun addListener(listener: AudioFocusGuard.FocusChangeListener) {
        listeners.add(listener)
    }

    override fun removeListener(listener: AudioFocusGuard.FocusChangeListener) {
        listeners.remove(listener)
    }

    /** Drive a focus change to all subscribers. */
    fun emit(event: AudioFocusGuard.FocusEvent) {
        for (listener in listeners) {
            listener.onFocusChange(event)
        }
    }
}
