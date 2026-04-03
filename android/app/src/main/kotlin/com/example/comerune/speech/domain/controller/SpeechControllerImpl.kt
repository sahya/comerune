package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.event.SpeechEventEmitter
import com.example.comerune.speech.domain.event.SpeechEvents
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechQueueItem
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.SpeechRuntimeStatus
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.SubmitResult
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.normalizer.CommentNormalizer
import com.example.comerune.speech.domain.normalizer.DuplicateDetector
import com.example.comerune.speech.domain.player.WavPlayer
import com.example.comerune.speech.domain.queue.SpeechQueueManager
import com.example.comerune.speech.domain.settings.SettingsRepository
import com.example.comerune.speech.domain.model.WavSynthesisResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.CloseableCoroutineDispatcher
import kotlinx.coroutines.newSingleThreadContext
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class SpeechControllerImpl(
    private val normalizer: CommentNormalizer,
    private val queueManager: SpeechQueueManager,
    private val engine: VoicevoxEngine,
    private val player: WavPlayer,
    private val settingsRepository: SettingsRepository,
    private val eventEmitter: SpeechEventEmitter,
    dispatcher: CoroutineDispatcher = Dispatchers.Default,
    synthesisDispatcher: CoroutineDispatcher? = null,
    private val timeProvider: () -> Long = System::currentTimeMillis,
    private val duplicateDetector: DuplicateDetector? = null
) : SpeechController {

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private val synthDispatcher: CoroutineDispatcher = synthesisDispatcher
        ?: newSingleThreadContext("voicevox-synth")
    private val ownsSynthDispatcher = synthesisDispatcher == null
    private val processingMutex = Mutex()
    private val workerMutex = Mutex()

    private data class PrefetchState(
        val commentId: String,
        val wavResult: WavSynthesisResult
    )

    @Volatile
    private var prefetched: PrefetchState? = null

    @Volatile
    private var activePrefetchJob: Job? = null

    @Volatile
    private var started = false

    @Volatile
    private var released = false

    @Volatile
    private var currentCommentId: String? = null

    @Volatile
    private var currentText: String? = null

    private var workerJob: Job? = null

    override suspend fun initialize(): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        val result = engine.initialize()
        if (result.isSuccess) {
            eventEmitter.emit(
                SpeechEvents.engineStateChanged(TtsEngineState.READY.name)
            )
        } else {
            eventEmitter.emit(
                SpeechEvents.engineStateChanged(TtsEngineState.ERROR.name)
            )
        }
        return result
    }

    override suspend fun start(): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        started = true
        startWorkerIfNeeded()
        return Result.success(Unit)
    }

    override suspend fun stop(clearQueue: Boolean): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        started = false
        player.stop()
        activePrefetchJob?.cancel()
        activePrefetchJob = null
        prefetched = null
        if (clearQueue) {
            queueManager.clear()
            eventEmitter.emit(SpeechEvents.queueUpdated(0))
        }
        return Result.success(Unit)
    }

    override suspend fun skip(): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        activePrefetchJob?.cancel()
        activePrefetchJob = null
        prefetched = null
        player.stop()
        return Result.success(Unit)
    }

    override suspend fun clearQueue(): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        queueManager.clear()
        eventEmitter.emit(SpeechEvents.queueUpdated(0))
        return Result.success(Unit)
    }

    override suspend fun submitComment(rawComment: RawComment): Result<SubmitResult> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }

        val settings = settingsRepository.get()

        if (!settings.enabled) {
            return Result.success(
                SubmitResult(
                    accepted = false,
                    skipped = true,
                    normalizedText = null,
                    skipReason = "disabled",
                    queueSize = queueManager.size()
                )
            )
        }

        val normalized = normalizer.normalize(rawComment, settings)

        if (normalized.skipReason != null) {
            eventEmitter.emit(
                SpeechEvents.commentSkipped(normalized.id, normalized.skipReason)
            )
            return Result.success(
                SubmitResult(
                    accepted = false,
                    skipped = true,
                    normalizedText = normalized.normalizedText,
                    skipReason = normalized.skipReason,
                    queueSize = queueManager.size()
                )
            )
        }

        if (normalized.normalizedText.isBlank()) {
            val reason = "empty_after_normalization"
            eventEmitter.emit(SpeechEvents.commentSkipped(normalized.id, reason))
            return Result.success(
                SubmitResult(
                    accepted = false,
                    skipped = true,
                    normalizedText = normalized.normalizedText,
                    skipReason = reason,
                    queueSize = queueManager.size()
                )
            )
        }

        val queueItem = SpeechQueueItem(
            commentId = normalized.id,
            text = normalized.normalizedText,
            priority = normalized.priority,
            createdAt = timeProvider()
        )

        val offerResult = queueManager.offer(queueItem)

        if (!offerResult.accepted) {
            return Result.success(
                SubmitResult(
                    accepted = false,
                    skipped = false,
                    normalizedText = normalized.normalizedText,
                    skipReason = offerResult.reason,
                    queueSize = queueManager.size()
                )
            )
        }

        eventEmitter.emit(SpeechEvents.queueUpdated(queueManager.size()))

        if (started) {
            startWorkerIfNeeded()
        }

        return Result.success(
            SubmitResult(
                accepted = true,
                skipped = false,
                normalizedText = normalized.normalizedText,
                skipReason = null,
                queueSize = queueManager.size()
            )
        )
    }

    override suspend fun updateSettings(settings: SpeechSettings): Result<Unit> {
        if (released) {
            return Result.failure(IllegalStateException("Controller has been released"))
        }
        settingsRepository.save(settings)

        // Propagate runtime-tunable settings via interface methods
        queueManager.updateMaxSize(settings.maxQueueSize)
        duplicateDetector?.updateDuplicateWindowMs(settings.duplicateWindowMs)

        // Clear regex cache when dictionary rules may have changed
        normalizer.clearRegexCache()

        return Result.success(Unit)
    }

    override suspend fun getStatus(): SpeechRuntimeStatus {
        val settings = settingsRepository.get()
        return SpeechRuntimeStatus(
            enabled = settings.enabled,
            engineState = engine.currentState(),
            playerState = player.currentState(),
            queueSize = queueManager.size(),
            currentCommentId = currentCommentId,
            currentText = currentText,
            currentSpeakerId = settings.speakerId
        )
    }

    override fun release() {
        // Uses synchronized (not workerMutex) because release() is a non-suspend
        // function.  Safety: setting released=true here ensures that processQueue()'s
        // workerMutex.withLock block will see `!released` as false and will NOT
        // relaunch, even if it runs concurrently.
        synchronized(this) {
            if (released) return
            released = true
            started = false
            activePrefetchJob?.cancel()
            activePrefetchJob = null
            prefetched = null
            workerJob?.cancel()
            workerJob = null
        }
        // Stop player before cancelling scope to avoid in-flight playback
        try {
            runBlocking { player.stop() }
        } catch (_: Exception) {
            // Best-effort: failure during cleanup is expected (player may already be stopped)
        }
        try {
            engine.release()
        } catch (_: Exception) {
            // Best-effort: failure during cleanup is expected (engine may already be released)
        }
        try {
            player.release()
        } catch (_: Exception) {
            // Best-effort: failure during cleanup is expected (player may already be released)
        }
        if (ownsSynthDispatcher) {
            (synthDispatcher as? CloseableCoroutineDispatcher)?.close()
        }
        scope.cancel()
    }

    private suspend fun startWorkerIfNeeded() {
        workerMutex.withLock {
            val currentJob = workerJob
            if (currentJob != null && currentJob.isActive) return

            workerJob = scope.launch {
                processQueue()
            }
        }
    }

    private suspend fun processQueue() {
        // Outer loop ensures we don't miss items added between poll()→null and worker exit.
        // The workerMutex lock at exit guarantees that no submitComment can observe
        // isActive==true for a job that is about to finish without re-checking the queue.
        do {
            while (started && !released) {
                val item = queueManager.poll() ?: break

                try {
                    processingMutex.withLock {
                        processItem(item)
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // Unexpected exceptions must not kill the worker.
                    // The item is skipped and processing continues with the next one.
                    try {
                        eventEmitter.emit(
                            SpeechEvents.speechFailed(
                                item.commentId,
                                e.message ?: "unexpected_error"
                            )
                        )
                    } catch (_: Exception) {
                        // Best-effort: emit itself may fail if the event sink
                        // is disconnected.  State cleanup below must still run.
                    }
                    currentCommentId = null
                    currentText = null
                }
            }
        } while (started && !released && !queueManager.isEmpty())

        // Atomically mark the worker as done and re-check the queue.
        // This closes the race window where submitComment calls startWorkerIfNeeded()
        // while the worker is between the loop exit and Job completion.
        //
        // When relaunching, the new coroutine (via scope.launch) runs on its own
        // stack frame — this is NOT recursive in the traditional sense and cannot
        // cause stack overflow.
        val relaunched = workerMutex.withLock {
            if (started && !released && !queueManager.isEmpty()) {
                // Items arrived after our last check — relaunch immediately.
                workerJob = scope.launch {
                    processQueue()
                }
                true
            } else {
                workerJob = null
                false
            }
        }

        // Only emit the queue-empty event when we are truly done.
        // If we relaunched, the new worker will emit the event when it finishes.
        if (!relaunched && !released) {
            eventEmitter.emit(SpeechEvents.queueUpdated(queueManager.size()))
        }
    }

    private suspend fun processItem(item: SpeechQueueItem) {
        currentCommentId = item.commentId
        currentText = item.text

        eventEmitter.emit(SpeechEvents.speechStarted(item.commentId, item.text))

        val settings = settingsRepository.get()

        // Use prefetched result if available for this item
        val wavResult: WavSynthesisResult
        val cached = prefetched
        if (cached != null && cached.commentId == item.commentId) {
            wavResult = cached.wavResult
            prefetched = null
        } else {
            // Clear stale prefetch (different item)
            prefetched = null

            val request = buildSpeechRequest(item.text, settings)
            val synthesisResult = try {
                withContext(synthDispatcher) { engine.synthesize(request) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Result.failure(e)
            }

            if (synthesisResult.isFailure) {
                val errorMessage =
                    synthesisResult.exceptionOrNull()?.message ?: "synthesis_failed"
                eventEmitter.emit(
                    SpeechEvents.speechFailed(item.commentId, errorMessage)
                )
                currentCommentId = null
                currentText = null
                return
            }
            wavResult = synthesisResult.getOrThrow()
        }

        // Start prefetching next item while playing current one
        val nextItem = queueManager.peek()
        activePrefetchJob = if (nextItem != null) {
            scope.async(synthDispatcher) {
                try {
                    val nextSettings = settingsRepository.get()
                    val nextRequest = buildSpeechRequest(nextItem.text, nextSettings)
                    engine.synthesize(nextRequest)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    null
                }
            }
        } else null

        // Play current item
        val playResult = try {
            player.play(wavResult.wavBytes)
        } catch (e: CancellationException) {
            activePrefetchJob?.cancel()
            activePrefetchJob = null
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }

        // Collect prefetch result
        val currentPrefetchJob = activePrefetchJob
        if (currentPrefetchJob != null) {
            try {
                val result = currentPrefetchJob.await()
                if (result != null && result.isSuccess) {
                    prefetched = PrefetchState(
                        commentId = nextItem!!.commentId,
                        wavResult = result.getOrThrow()
                    )
                }
            } catch (_: Exception) {
                // Prefetch failed, no problem - will synthesize normally
            }
            activePrefetchJob = null
        }

        if (playResult.isFailure) {
            val errorMessage =
                playResult.exceptionOrNull()?.message ?: "playback_failed"
            eventEmitter.emit(
                SpeechEvents.speechFailed(item.commentId, errorMessage)
            )
        } else {
            eventEmitter.emit(SpeechEvents.speechCompleted(item.commentId))
        }

        currentCommentId = null
        currentText = null
    }

    private fun buildSpeechRequest(text: String, settings: SpeechSettings): SpeechRequest {
        return SpeechRequest(
            text = text,
            speakerId = settings.speakerId,
            speedScale = settings.speedScale,
            pitchScale = settings.pitchScale,
            intonationScale = settings.intonationScale,
            volumeScale = settings.volumeScale,
            prePhonemeLength = settings.prePhonemeLength,
            postPhonemeLength = settings.postPhonemeLength
        )
    }
}
