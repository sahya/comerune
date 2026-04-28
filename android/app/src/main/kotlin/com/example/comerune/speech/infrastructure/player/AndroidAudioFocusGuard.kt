package com.example.comerune.speech.infrastructure.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import com.example.comerune.speech.domain.player.AudioFocusGuard
import com.example.comerune.speech.domain.player.AudioFocusGuard.FocusChangeListener
import com.example.comerune.speech.domain.player.AudioFocusGuard.FocusEvent
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.coroutines.resume

/**
 * Internal seam over the platform [AudioManager] calls actually used by
 * [AndroidAudioFocusGuard].
 *
 * Owning the [AudioFocusRequest] inside the controller lets [AndroidAudioFocusGuard]
 * stay framework-method-call-free in unit tests (the test fake does not
 * need to fabricate a real `AudioFocusRequest`).
 */
internal interface AudioFocusController {
    /** Returns one of `AUDIOFOCUS_REQUEST_*` codes. */
    fun request(): Int

    /** Returns one of `AUDIOFOCUS_REQUEST_*` codes. Best-effort. */
    fun abandon(): Int

    /** Sets the focus-change callback. Called once during construction. */
    fun setFocusChangeListener(listener: AudioFocusListener)
}

/**
 * Subset of [android.media.AudioManager.OnAudioFocusChangeListener] used
 * by the guard. Mapping happens inside the controller so tests do not
 * need to know about Android focus-code constants.
 */
internal interface AudioFocusListener {
    fun onFocusChange(rawFocusChange: Int)
}

@RequiresApi(Build.VERSION_CODES.O)
internal class RealAudioFocusController(
    private val audioManager: AudioManager,
) : AudioFocusController {

    private val audioAttributes: AudioAttributes =
        AudioAttributes.Builder().apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setUsage(AudioAttributes.USAGE_ASSISTANT)
            } else {
                setUsage(AudioAttributes.USAGE_MEDIA)
            }
            setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        }.build()

    @Volatile
    private var listener: AudioFocusListener? = null

    private val nativeListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        listener?.onFocusChange(focusChange)
    }

    private val request: AudioFocusRequest by lazy {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(audioAttributes)
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener(nativeListener)
            .build()
    }

    override fun request(): Int = audioManager.requestAudioFocus(request)

    override fun abandon(): Int = audioManager.abandonAudioFocusRequest(request)

    override fun setFocusChangeListener(listener: AudioFocusListener) {
        this.listener = listener
    }
}

/**
 * Tiny scheduler seam used by [AndroidAudioFocusGuard.scheduleRelease].
 * In production this is backed by an Android [Handler] on the main
 * looper. Tests inject a fake that runs the runnable inline (or holds
 * it for manual triggering) so they need no Android runtime.
 */
internal interface DelayedRunner {
    fun postDelayed(runnable: Runnable, delayMs: Long)
    fun cancel(runnable: Runnable)
}

internal class HandlerDelayedRunner(
    private val handler: Handler,
) : DelayedRunner {
    override fun postDelayed(runnable: Runnable, delayMs: Long) {
        handler.postDelayed(runnable, delayMs)
    }

    override fun cancel(runnable: Runnable) {
        handler.removeCallbacks(runnable)
    }
}

/**
 * Default Android implementation of [AudioFocusGuard].
 *
 * Owns a single shared focus session, reused across all callers. This is
 * how Android expects a long-running media session to behave: one
 * request per app, regrabbed only after a release has settled.
 *
 * Threading:
 * - All state mutation happens under [lock].
 * - Focus change callbacks are routed to listeners synchronously; the
 *   platform delivers them on the main thread already.
 * - Scheduled release uses a [DelayedRunner] (Android [Handler] in prod)
 *   to avoid spawning a coroutine scope inside infrastructure code.
 */
@RequiresApi(Build.VERSION_CODES.O)
class AndroidAudioFocusGuard internal constructor(
    private val controller: AudioFocusController,
    private val delayedRunner: DelayedRunner,
) : AudioFocusGuard {

    constructor(context: Context) : this(
        controller = RealAudioFocusController(
            context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager,
        ),
        delayedRunner = HandlerDelayedRunner(Handler(Looper.getMainLooper())),
    )

    private val lock = Any()

    private val listeners: MutableList<FocusChangeListener> = CopyOnWriteArrayList()

    /**
     * Held = the underlying focus request has been granted (or is
     * pending via DELAYED). Reset to false inside
     * [release] / [doImmediateRelease].
     */
    @Volatile
    private var held: Boolean = false

    /**
     * The continuation waiting for a DELAYED → GAIN transition. Resumed
     * exactly once with success (on GAIN) or failure (on terminal loss
     * or explicit release before GAIN).
     */
    private var pendingAcquire: CancellableContinuation<Result<Unit>>? = null

    /**
     * Additional callers that arrived while [pendingAcquire] was already
     * set. They share the same DELAYED→GAIN handshake instead of issuing
     * a duplicate request that would overwrite the original continuation.
     */
    private val pendingWaiters: MutableList<CancellableContinuation<Result<Unit>>> =
        mutableListOf()

    /** Token currently scheduled via [delayedRunner]; null if no release pending. */
    private var pendingReleaseRunnable: Runnable? = null

    init {
        controller.setFocusChangeListener(object : AudioFocusListener {
            override fun onFocusChange(rawFocusChange: Int) {
                when (rawFocusChange) {
                    AudioManager.AUDIOFOCUS_GAIN -> handleGain()
                    AudioManager.AUDIOFOCUS_LOSS -> handleLoss(FocusEvent.LOSS)
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT ->
                        handleLoss(FocusEvent.LOSS_TRANSIENT)
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK ->
                        handleLoss(FocusEvent.LOSS_TRANSIENT_CAN_DUCK)
                }
            }
        })
    }

    override val isHeld: Boolean get() = held

    override suspend fun acquire(): Result<Unit> {
        // Cancel any deferred release first so a re-acquire short-circuits.
        synchronized(lock) {
            cancelPendingReleaseLocked()
            if (held && pendingAcquire == null) {
                return Result.success(Unit)
            }
        }

        return suspendCancellableCoroutine { cont ->
            val resultNow: Result<Unit>?
            // Take the lock BEFORE asking the platform. Android delivers
            // focus callbacks on a Handler thread, so the listener will
            // block waiting for our lock until we have stored the
            // pending continuation — closing the race where a
            // synchronous GAIN would resolve before pendingAcquire is
            // assigned. requestAudioFocus is itself non-blocking, so
            // holding the lock briefly across it is safe.
            synchronized(lock) {
                resultNow = when {
                    held && pendingAcquire == null -> {
                        // Another caller already secured focus.
                        Result.success(Unit)
                    }
                    pendingAcquire != null -> {
                        // Another caller is already waiting for the
                        // DELAYED→GAIN handshake. Piggyback on it instead
                        // of re-requesting, otherwise we would overwrite
                        // the existing continuation and leak it.
                        pendingWaiters.add(cont)
                        null
                    }
                    else -> when (val response = controller.request()) {
                        AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> {
                            held = true
                            Result.success(Unit)
                        }
                        AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> {
                            held = true
                            pendingAcquire = cont
                            null
                        }
                        else -> Result.failure(
                            IllegalStateException(
                                "Audio focus request denied (response=$response)",
                            ),
                        )
                    }
                }
            }
            if (resultNow != null && cont.isActive) {
                cont.resume(resultNow)
            }
            cont.invokeOnCancellation {
                synchronized(lock) {
                    if (pendingAcquire === cont) {
                        pendingAcquire = null
                    }
                    pendingWaiters.remove(cont)
                }
            }
        }
    }

    override fun release() {
        doImmediateRelease(notifyPending = true)
    }

    override fun scheduleRelease(graceMs: Long) {
        // Build the runnable outside the lock so its identity can be
        // captured cleanly. The runnable itself takes the lock when it
        // fires to verify it is still the active scheduled release.
        lateinit var runnable: Runnable
        runnable = Runnable {
            val shouldRelease: Boolean
            synchronized(lock) {
                shouldRelease = pendingReleaseRunnable === runnable
                if (shouldRelease) {
                    pendingReleaseRunnable = null
                }
            }
            if (shouldRelease) {
                doImmediateRelease(notifyPending = true)
            }
        }
        synchronized(lock) {
            if (!held) return
            cancelPendingReleaseLocked()
            pendingReleaseRunnable = runnable
        }
        delayedRunner.postDelayed(runnable, graceMs)
    }

    override fun addListener(listener: FocusChangeListener) {
        listeners.add(listener)
    }

    override fun removeListener(listener: FocusChangeListener) {
        listeners.remove(listener)
    }

    private fun cancelPendingReleaseLocked() {
        pendingReleaseRunnable?.let { delayedRunner.cancel(it) }
        pendingReleaseRunnable = null
    }

    private fun doImmediateRelease(notifyPending: Boolean) {
        val pendingToFail: CancellableContinuation<Result<Unit>>?
        val waitersToFail: List<CancellableContinuation<Result<Unit>>>
        synchronized(lock) {
            cancelPendingReleaseLocked()
            pendingToFail = pendingAcquire
            pendingAcquire = null
            waitersToFail = pendingWaiters.toList()
            pendingWaiters.clear()
            if (held) {
                try {
                    controller.abandon()
                } catch (_: Exception) {
                    // best-effort
                }
                held = false
            }
        }
        if (notifyPending) {
            val failure = Result.failure<Unit>(
                IllegalStateException("Audio focus released before grant"),
            )
            if (pendingToFail != null && pendingToFail.isActive) {
                pendingToFail.resume(failure)
            }
            for (waiter in waitersToFail) {
                if (waiter.isActive) waiter.resume(failure)
            }
        }
    }

    private fun handleGain() {
        val pending: CancellableContinuation<Result<Unit>>?
        val waiters: List<CancellableContinuation<Result<Unit>>>
        synchronized(lock) {
            held = true
            pending = pendingAcquire
            pendingAcquire = null
            waiters = pendingWaiters.toList()
            pendingWaiters.clear()
        }
        val success = Result.success(Unit)
        if (pending != null && pending.isActive) {
            pending.resume(success)
        }
        for (waiter in waiters) {
            if (waiter.isActive) waiter.resume(success)
        }
        notifyListeners(FocusEvent.GAIN)
    }

    private fun handleLoss(event: FocusEvent) {
        val pendingToFail: CancellableContinuation<Result<Unit>>?
        val waitersToFail: List<CancellableContinuation<Result<Unit>>>
        synchronized(lock) {
            if (event == FocusEvent.LOSS) {
                // Permanent loss — drop our token so the next acquire()
                // makes a fresh request, and fail any in-flight acquire
                // that was waiting for DELAYED→GAIN.
                pendingToFail = pendingAcquire
                pendingAcquire = null
                waitersToFail = pendingWaiters.toList()
                pendingWaiters.clear()
                held = false
                cancelPendingReleaseLocked()
            } else {
                // Transient loss leaves any DELAYED acquire alone — a
                // subsequent GAIN may still complete it. Clearing the
                // continuation here would deadlock the caller.
                pendingToFail = null
                waitersToFail = emptyList()
            }
        }
        val failure = Result.failure<Unit>(
            IllegalStateException("Audio focus permanently lost"),
        )
        if (pendingToFail != null && pendingToFail.isActive) {
            pendingToFail.resume(failure)
        }
        for (waiter in waitersToFail) {
            if (waiter.isActive) waiter.resume(failure)
        }
        notifyListeners(event)
    }

    private fun notifyListeners(event: FocusEvent) {
        // listeners is CopyOnWriteArrayList — safe to iterate without lock.
        for (listener in listeners) {
            try {
                listener.onFocusChange(event)
            } catch (_: Exception) {
                // Listeners must not throw; swallow to keep the focus
                // pipeline robust.
            }
        }
    }
}
