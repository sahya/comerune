package com.example.comerune.speech.infrastructure.player

import android.media.AudioManager
import com.example.comerune.speech.domain.player.AudioFocusGuard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

/**
 * Unit tests for [AndroidAudioFocusGuard]. Use the internal seams
 * ([AudioFocusController] + [DelayedRunner]) to inject fakes so the
 * tests run on the pure JVM class path — no Robolectric, no instrumented
 * device.
 */
class AudioFocusGuardTest {

    private class FakeAudioFocusController(
        @Volatile var nextRequestResult: Int = AudioManager.AUDIOFOCUS_REQUEST_GRANTED,
    ) : AudioFocusController {
        val requestCount = AtomicInteger(0)
        val abandonCount = AtomicInteger(0)
        var listener: AudioFocusListener? = null

        override fun request(): Int {
            requestCount.incrementAndGet()
            return nextRequestResult
        }

        override fun abandon(): Int {
            abandonCount.incrementAndGet()
            return AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }

        override fun setFocusChangeListener(listener: AudioFocusListener) {
            this.listener = listener
        }
    }

    private class FakeDelayedRunner : DelayedRunner {
        private val pending: MutableList<Pending> = CopyOnWriteArrayList()

        data class Pending(val runnable: Runnable, val delayMs: Long)

        val pendingCount: Int get() = pending.size

        override fun postDelayed(runnable: Runnable, delayMs: Long) {
            pending.add(Pending(runnable, delayMs))
        }

        override fun cancel(runnable: Runnable) {
            pending.removeAll { it.runnable === runnable }
        }

        /** Fire all currently-scheduled runnables. */
        fun fireAll() {
            val snapshot = pending.toList()
            pending.clear()
            for (p in snapshot) p.runnable.run()
        }
    }

    private fun newGuard(
        controller: AudioFocusController,
        runner: DelayedRunner,
    ): AndroidAudioFocusGuard = AndroidAudioFocusGuard(controller, runner)

    @Test
    fun `acquire returns success when GRANTED`() = runBlocking {
        val controller = FakeAudioFocusController(
            nextRequestResult = AudioManager.AUDIOFOCUS_REQUEST_GRANTED,
        )
        val guard = newGuard(controller, FakeDelayedRunner())

        val result = guard.acquire()

        assertTrue("GRANTED must produce success", result.isSuccess)
        assertTrue("guard must report held after GRANTED", guard.isHeld)
        assertEquals(1, controller.requestCount.get())
    }

    @Test
    fun `acquire fails immediately on FAILED response`() = runBlocking {
        val controller = FakeAudioFocusController(
            nextRequestResult = AudioManager.AUDIOFOCUS_REQUEST_FAILED,
        )
        val guard = newGuard(controller, FakeDelayedRunner())

        val result = guard.acquire()

        assertTrue("FAILED must produce failure", result.isFailure)
        assertFalse("guard must not be held after FAILED", guard.isHeld)
    }

    @Test
    fun `DELAYED suspends until GAIN arrives, then succeeds`() = runBlocking {
        val controller = FakeAudioFocusController(
            nextRequestResult = AudioManager.AUDIOFOCUS_REQUEST_DELAYED,
        )
        val guard = newGuard(controller, FakeDelayedRunner())

        val deferred = async(Dispatchers.Default) { guard.acquire() }
        // Let the async coroutine reach the suspend point.
        waitUntil("acquire must reach pending state") { guard.isHeld }
        assertFalse("acquire must not complete before GAIN", deferred.isCompleted)

        // Simulate the platform delivering AUDIOFOCUS_GAIN.
        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_GAIN)

        val result = deferred.await()
        assertTrue("DELAYED→GAIN must produce success", result.isSuccess)
        assertTrue("guard must be held after GAIN", guard.isHeld)
    }

    @Test
    fun `DELAYED then permanent LOSS yields failure`() = runBlocking {
        val controller = FakeAudioFocusController(
            nextRequestResult = AudioManager.AUDIOFOCUS_REQUEST_DELAYED,
        )
        val guard = newGuard(controller, FakeDelayedRunner())

        val deferred = async(Dispatchers.Default) { guard.acquire() }
        waitUntil("acquire must reach pending state") { guard.isHeld }

        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_LOSS)

        val result = deferred.await()
        assertTrue("permanent loss before GAIN must fail acquire", result.isFailure)
        assertFalse("guard must drop held flag on permanent loss", guard.isHeld)
    }

    @Test
    fun `acquire is idempotent when already held`() = runBlocking {
        val controller = FakeAudioFocusController()
        val guard = newGuard(controller, FakeDelayedRunner())

        guard.acquire()
        val secondCount = controller.requestCount.get()
        assertEquals(1, secondCount)

        val secondResult = guard.acquire()
        assertTrue(secondResult.isSuccess)
        assertEquals(
            "second acquire on a held guard must not hit the platform",
            1,
            controller.requestCount.get(),
        )
    }

    @Test
    fun `scheduleRelease defers abandon until grace expires`() = runBlocking {
        val controller = FakeAudioFocusController()
        val runner = FakeDelayedRunner()
        val guard = newGuard(controller, runner)
        guard.acquire()

        guard.scheduleRelease()
        assertEquals(0, controller.abandonCount.get())
        assertTrue("guard stays held during grace period", guard.isHeld)
        assertEquals(1, runner.pendingCount)

        runner.fireAll()
        assertEquals("scheduled release must abandon", 1, controller.abandonCount.get())
        assertFalse(guard.isHeld)
    }

    @Test
    fun `re-acquire during grace cancels scheduled release`() = runBlocking {
        val controller = FakeAudioFocusController()
        val runner = FakeDelayedRunner()
        val guard = newGuard(controller, runner)
        guard.acquire()
        guard.scheduleRelease()
        assertEquals(1, runner.pendingCount)

        // Re-acquire before the runner fires.
        val secondResult = guard.acquire()
        assertTrue(secondResult.isSuccess)
        assertEquals(
            "re-acquire must cancel the pending release",
            0,
            runner.pendingCount,
        )
        assertEquals(
            "re-acquire on held guard must not re-request from platform",
            1,
            controller.requestCount.get(),
        )

        // Even firing leftover runnables now must not abandon.
        runner.fireAll()
        assertEquals(0, controller.abandonCount.get())
        assertTrue(guard.isHeld)
    }

    @Test
    fun `release cancels pending release and abandons immediately`() = runBlocking {
        val controller = FakeAudioFocusController()
        val runner = FakeDelayedRunner()
        val guard = newGuard(controller, runner)
        guard.acquire()
        guard.scheduleRelease()
        assertEquals(1, runner.pendingCount)

        guard.release()
        assertEquals(1, controller.abandonCount.get())
        assertEquals(0, runner.pendingCount)
        assertFalse(guard.isHeld)
    }

    @Test
    fun `focus change events are forwarded to all listeners`() {
        val controller = FakeAudioFocusController()
        val guard = newGuard(controller, FakeDelayedRunner())

        val received1 = CopyOnWriteArrayList<AudioFocusGuard.FocusEvent>()
        val received2 = CopyOnWriteArrayList<AudioFocusGuard.FocusEvent>()
        guard.addListener { received1.add(it) }
        guard.addListener { received2.add(it) }

        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_GAIN)

        assertEquals(
            listOf(AudioFocusGuard.FocusEvent.LOSS_TRANSIENT, AudioFocusGuard.FocusEvent.GAIN),
            received1,
        )
        assertEquals(received1, received2)
    }

    @Test
    fun `removeListener stops further notifications`() {
        val controller = FakeAudioFocusController()
        val guard = newGuard(controller, FakeDelayedRunner())
        val received = CopyOnWriteArrayList<AudioFocusGuard.FocusEvent>()
        val listener = AudioFocusGuard.FocusChangeListener { received.add(it) }
        guard.addListener(listener)
        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)
        assertEquals(1, received.size)

        guard.removeListener(listener)
        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        assertEquals(
            "removeListener must prevent further callbacks",
            1,
            received.size,
        )
    }

    @Test
    fun `acquire after permanent LOSS performs a fresh request`() = runBlocking {
        val controller = FakeAudioFocusController()
        val guard = newGuard(controller, FakeDelayedRunner())
        guard.acquire()
        assertEquals(1, controller.requestCount.get())

        // Platform reports permanent loss.
        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_LOSS)
        assertFalse(guard.isHeld)

        guard.acquire()
        assertEquals(
            "after permanent loss, the next acquire must hit the platform again",
            2,
            controller.requestCount.get(),
        )
    }

    @Test
    fun `concurrent DELAYED acquires share the same handshake`() = runBlocking {
        val controller = FakeAudioFocusController(
            nextRequestResult = AudioManager.AUDIOFOCUS_REQUEST_DELAYED,
        )
        val guard = newGuard(controller, FakeDelayedRunner())

        val first = async(Dispatchers.Default) { guard.acquire() }
        // Wait until the first acquire has started the DELAYED state.
        waitUntil("first acquire must reach pending state") { guard.isHeld }

        val second = async(Dispatchers.Default) { guard.acquire() }
        // Give the second coroutine a chance to register as a waiter.
        delay(20)

        // Only one platform request must have been made.
        assertEquals(
            "the second concurrent acquire must piggyback on the first",
            1,
            controller.requestCount.get(),
        )

        controller.listener?.onFocusChange(AudioManager.AUDIOFOCUS_GAIN)

        assertTrue(first.await().isSuccess)
        assertTrue(second.await().isSuccess)
    }

    @Test
    fun `release on idle guard is a no-op`() {
        val controller = FakeAudioFocusController()
        val guard = newGuard(controller, FakeDelayedRunner())
        // Guard registers its focus listener on construction.
        assertNotNull(controller.listener)
        guard.release()
        assertEquals(
            "release without prior acquire must not call abandon",
            0,
            controller.abandonCount.get(),
        )
        assertFalse(guard.isHeld)
    }
}

private suspend fun waitUntil(
    reason: String,
    timeoutMs: Long = 1000,
    predicate: () -> Boolean,
) {
    val deadline = System.currentTimeMillis() + timeoutMs
    while (!predicate()) {
        if (System.currentTimeMillis() > deadline) {
            throw AssertionError("$reason (timed out after ${timeoutMs}ms)")
        }
        delay(1)
    }
}
