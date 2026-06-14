package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.audio.CallStateProvider
import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.event.SpeechEventEmitter
import com.example.comerune.speech.domain.event.SpeechEvents
import com.example.comerune.speech.domain.model.EngineType
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.SpeechQueueItem
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.SpeechRuntimeStatus
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.SubmitResult
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult
import com.example.comerune.speech.domain.normalizer.CommentNormalizer
import com.example.comerune.speech.domain.normalizer.DuplicateDetector
import com.example.comerune.speech.domain.player.TtsSpeaker
import com.example.comerune.speech.domain.player.WavPlayer
import com.example.comerune.speech.domain.queue.SpeechQueueManager
import com.example.comerune.speech.domain.settings.SettingsRepository
import com.example.comerune.speech.domain.splitter.JapaneseTextSplitter
import com.example.comerune.speech.domain.splitter.TextSplitter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CloseableCoroutineDispatcher
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
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
    private val duplicateDetector: DuplicateDetector? = null,
    private val textSplitter: TextSplitter = JapaneseTextSplitter(),
    private val ttsSpeaker: TtsSpeaker? = null,
    private val callStateProvider: CallStateProvider? = null,
) : SpeechController {

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)

    // newSingleThreadContext is @DelicateCoroutinesApi + @ExperimentalCoroutinesApi.
    // Lifecycle is managed by release() below.
    @OptIn(DelicateCoroutinesApi::class, ExperimentalCoroutinesApi::class)
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
    private var activePrefetchJob: Deferred<Result<WavSynthesisResult>?>? = null

    /**
     * Gate that controls whether the queue worker loop keeps polling.
     *
     * - Set to `true` by [start] and back to `false` by [stop] / [release].
     * - Read by [submitComment] to decide whether to (re)start the worker
     *   when a new item arrives, and by `processQueue` as the primary
     *   loop condition.
     *
     * Semantically this is **worker-loop intent**: the user / caller has
     * asked for the queue to be drained. It is independent of engine
     * state ([TtsEngineState]) and of the TTS speaker lifecycle — for
     * example `started` can stay `true` while the engine is
     * `INITIALIZING` or while the audio player is briefly `PAUSED`.
     *
     * This field is the **ground truth** for the Flutter-side
     * `_speechStarted` mirror flag and is exposed via
     * [getStatus] -> [SpeechRuntimeStatus.started] so the Flutter layer
     * can reconcile after process recreation, engine switch, or any
     * lifecycle event that may have raced with its local mirror
     * (Issue #915).
     */
    @Volatile
    private var started = false

    @Volatile
    private var released = false

    @Volatile
    private var currentCommentId: String? = null

    @Volatile
    private var currentText: String? = null

    @Volatile
    private var lastAndroidTtsSpeed: Float? = null
    @Volatile
    private var lastAndroidTtsPitch: Float? = null
    @Volatile
    private var lastAndroidTtsVolume: Float? = null

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
        // Issue #962: interrupt the Android TTS engine FIRST. Without this,
        // the worker stays suspended inside speaker.speak() for up to the
        // speaker's safety timeout, the queue does not drain, and engine
        // switch / stop appears frozen to the user for tens of seconds.
        // speaker.stop() resumes the in-flight continuation synchronously
        // (see AndroidTtsSpeaker.stop) and is a benign no-op when no
        // utterance is in flight, so it is safe to call unconditionally.
        ttsSpeaker?.stop()
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
        // Issue #969: symmetry with stop() — interrupt the Android TTS engine
        // FIRST so the worker resumes from an in-flight speaker.speak()
        // immediately rather than waiting on the safety timeout. Without this
        // ordering, a skip issued while speak() is suspended would block on
        // player.stop() / prefetch cancellation before reaching speaker.stop()
        // and the queue could appear frozen on the next item. Calling stop()
        // is a benign no-op when no utterance is in flight, so it is safe to
        // invoke unconditionally before the other teardown steps.
        ttsSpeaker?.stop()
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

        // Diagnostic-only: detect callers that rely on updateSettings to bring
        // the VOICEVOX engine online without first calling initialize(). The
        // primary fix for engine-type switching lives on the Flutter side
        // (CommentScreen._handleSpeechSettingsChanged); this guard is purely
        // observability so a missed code path is visible instead of silent.
        // Behavior is unchanged: we only emit an event, never auto-initialize.
        if (settings.engineType == EngineType.VOICEVOX) {
            val state = engine.currentState()
            if (state != TtsEngineState.READY) {
                eventEmitter.emit(
                    SpeechEvents.engineNotReady(
                        engineType = EngineType.VOICEVOX.name,
                        engineState = state.name
                    )
                )
            }
        }

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
            currentSpeakerId = settings.speakerId,
            // Issue #915: expose the worker-loop intent so the Flutter
            // side can reconcile its `_speechStarted` mirror after engine
            // switch or any lifecycle event that may have raced with it.
            // This is the **ground truth** for that mirror — see the Kdoc
            // on [started] for why this is independent of engine state.
            started = started
        )
    }

    @OptIn(ExperimentalCoroutinesApi::class) // CloseableCoroutineDispatcher
    override fun release() {
        // Uses synchronized (not workerMutex) because release() is a non-suspend
        // function.  Setting released=true ensures processQueue()'s workerMutex.withLock
        // block will see released as true and will NOT relaunch.
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
        try {
            runBlocking { player.stop() }
        } catch (_: Exception) {
            // Best-effort
        }
        try {
            engine.release()
        } catch (_: Exception) {
            // Best-effort
        }
        try {
            player.release()
        } catch (_: Exception) {
            // Best-effort
        }
        try {
            ttsSpeaker?.release()
        } catch (_: Exception) {
            // Best-effort
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
                    try {
                        // Issue #695 round-2 review: when the engine in use is
                        // Android TTS, anything that throws *before* reaching
                        // `processWithAndroidTts` (e.g. a settings lookup, a
                        // pre-emit hook, or `processItem` itself) must still
                        // surface as an `android_tts_failed:` reason so the
                        // Flutter-side detector recognises it. Without this
                        // engine-aware wrapping the message would be a bare
                        // exception text or "unexpected_error", which slips
                        // past the threshold-based detector entirely.
                        val isAndroidTts =
                            settingsRepository.get().engineType ==
                                EngineType.ANDROID_TTS
                        val rawMessage = e.message ?: "unexpected_error"
                        val message = if (isAndroidTts) {
                            "android_tts_failed: $rawMessage"
                        } else {
                            rawMessage
                        }
                        eventEmitter.emit(
                            SpeechEvents.speechFailed(item.commentId, message)
                        )
                    } catch (_: Exception) {
                        // Best-effort
                    }
                    currentCommentId = null
                    currentText = null
                }
            }
        } while (started && !released && !queueManager.isEmpty())

        val relaunched = workerMutex.withLock {
            if (started && !released && !queueManager.isEmpty()) {
                workerJob = scope.launch {
                    processQueue()
                }
                true
            } else {
                workerJob = null
                false
            }
        }

        if (!relaunched && !released) {
            eventEmitter.emit(SpeechEvents.queueUpdated(queueManager.size()))
        }
    }

    private suspend fun processItem(item: SpeechQueueItem) {
        currentCommentId = item.commentId
        currentText = item.text

        // Issue #931: comerune no longer requests AudioFocus per utterance,
        // so the platform no longer auto-stops TTS when telephony takes
        // focus. Restore the previous "silent during a call" behavior by
        // probing the audio mode at dispatch time and skipping the
        // utterance entirely. The comment stays in CommentLog (Flutter
        // side) because we only drop the speak, not the log entry.
        if (callStateProvider?.isInCall() == true) {
            eventEmitter.emit(
                SpeechEvents.commentSkipped(item.commentId, "in_call"),
            )
            currentCommentId = null
            currentText = null
            return
        }

        eventEmitter.emit(SpeechEvents.speechStarted(item.commentId, item.text))

        val settings = settingsRepository.get()

        if (settings.engineType == EngineType.ANDROID_TTS) {
            processWithAndroidTts(item, settings)
        } else {
            val chunks = textSplitter.split(item.text)
            if (chunks.size == 1) {
                processSingleChunk(item, settings)
            } else {
                processChunkedPipeline(item.commentId, chunks, settings)
            }
        }

        currentCommentId = null
        currentText = null
    }

    private suspend fun processWithAndroidTts(
        item: SpeechQueueItem,
        settings: SpeechSettings
    ) {
        val speaker = ttsSpeaker
        if (speaker == null || !speaker.isReady()) {
            eventEmitter.emit(
                SpeechEvents.speechFailed(item.commentId, "android_tts_not_ready")
            )
            return
        }

        // Issue #695 cycle-3: wrap the whole speak path so that any throw from
        // setSpeechRate/setPitch/setVolume (e.g. native TextToSpeech instance
        // becomes invalidated mid-session) also lands as an `android_tts_failed:`
        // event. Otherwise the outer processQueue catch in run() swallows it as
        // an unprefixed `unexpected_error` and the Flutter-side detector never
        // sees an Android-TTS failure.
        try {
            if (lastAndroidTtsSpeed != settings.androidTtsSpeed) {
                speaker.setSpeechRate(settings.androidTtsSpeed)
                lastAndroidTtsSpeed = settings.androidTtsSpeed
            }
            if (lastAndroidTtsPitch != settings.androidTtsPitch) {
                speaker.setPitch(settings.androidTtsPitch)
                lastAndroidTtsPitch = settings.androidTtsPitch
            }
            if (lastAndroidTtsVolume != settings.androidTtsVolume) {
                speaker.setVolume(settings.androidTtsVolume)
                lastAndroidTtsVolume = settings.androidTtsVolume
            }

            val result = try {
                speaker.speak(item.text, item.commentId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Result.failure(e)
            }

            if (result.isFailure) {
                // Issue #695: always include the `android_tts_failed:` prefix so
                // the Flutter side can recognise this as an Android-TTS failure
                // regardless of the underlying exception text. Without the
                // prefix, the inner exception message ("TTS speak timed out",
                // "TTS speak() returned error: -1", etc.) bypasses the
                // Flutter-side detector entirely and the AppBar never flips to
                // ERROR even after sustained failures.
                val inner = result.exceptionOrNull()?.message ?: "unknown"
                val errorMessage = "android_tts_failed: $inner"
                eventEmitter.emit(SpeechEvents.speechFailed(item.commentId, errorMessage))
            } else {
                eventEmitter.emit(SpeechEvents.speechCompleted(item.commentId))
            }
            // Issue #695 cycle-2-new-1 review: signal that we have already
            // emitted a terminal event for this item so the outer catch
            // (below) does not double-emit a `speechFailed` after a
            // successful `speechCompleted`.
            return
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Reached only for exceptions thrown by the configuration calls
            // (setSpeechRate / setPitch / setVolume) before we entered the
            // speak() Result-wrapped path, OR for failures of
            // eventEmitter.emit itself. In either case no terminal event has
            // been emitted yet for this item, so emitting `speechFailed` here
            // does NOT race with a prior successful `speechCompleted`.
            val inner = e.message ?: "unknown"
            eventEmitter.emit(
                SpeechEvents.speechFailed(item.commentId, "android_tts_failed: $inner")
            )
        }
    }

    /**
     * Process a single chunk (no intra-comment splitting).
     * Uses the inter-comment prefetch pipeline from PR #348.
     */
    private suspend fun processSingleChunk(
        item: SpeechQueueItem,
        settings: SpeechSettings
    ) {
        val wavResult = synthesizeOrUsePrefetch(item, settings) ?: return

        val prefetchNextItem = startPrefetch(settings)

        val playResult = try {
            player.play(wavResult.wavBytes)
        } catch (e: CancellationException) {
            activePrefetchJob?.cancel()
            activePrefetchJob = null
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }

        if (prefetchNextItem != null) {
            collectPrefetch(prefetchNextItem)
        }

        if (playResult.isFailure) {
            val errorMessage =
                playResult.exceptionOrNull()?.message ?: "playback_failed"
            eventEmitter.emit(SpeechEvents.speechFailed(item.commentId, errorMessage))
        } else {
            eventEmitter.emit(SpeechEvents.speechCompleted(item.commentId))
        }
    }

    /**
     * Process multiple chunks with pipelined synthesis and playback.
     *
     * For each chunk after the first, synthesis is started before the
     * previous chunk finishes playing. Intermediate chunks use zero
     * pre/post phoneme lengths to minimize silence between chunks.
     *
     * After the last chunk plays, inter-comment prefetch is started
     * for the next queued comment.
     */
    private suspend fun processChunkedPipeline(
        commentId: String,
        chunks: List<String>,
        settings: SpeechSettings
    ) {
        // Invalidate inter-comment prefetch since we're doing intra-comment pipelining
        prefetched = null

        var nextChunkDeferred: Deferred<Result<WavSynthesisResult>>? = null
        var prefetchNextItem: SpeechQueueItem? = null

        for (i in chunks.indices) {
            val isFirst = i == 0
            val isLast = i == chunks.lastIndex
            val request = buildChunkRequest(chunks[i], settings, isFirst, isLast)

            val synthesisResult = if (nextChunkDeferred != null) {
                val deferred = nextChunkDeferred
                nextChunkDeferred = null
                try {
                    deferred.await()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Result.failure(e)
                }
            } else {
                synthesizeSafe(request)
            }

            if (synthesisResult.isFailure) {
                activePrefetchJob?.cancel()
                activePrefetchJob = null
                val errorMessage =
                    synthesisResult.exceptionOrNull()?.message ?: "synthesis_failed"
                eventEmitter.emit(SpeechEvents.speechFailed(commentId, errorMessage))
                return
            }

            val wavBytes = synthesisResult.getOrThrow().wavBytes

            // Start synthesizing the next chunk while playing the current one
            if (!isLast) {
                val nextIsLast = i + 1 == chunks.lastIndex
                val nextRequest = buildChunkRequest(
                    chunks[i + 1], settings, isFirst = false, isLast = nextIsLast
                )
                nextChunkDeferred = scope.async(synthDispatcher) { synthesizeSafe(nextRequest) }
            }

            // On the last chunk, start inter-comment prefetch and capture
            // the peeked item to avoid a second peek() that could return a
            // different item if the queue was modified during playback.
            if (isLast) {
                prefetchNextItem = startPrefetch(settings)
            }

            val playResult = playSafe(wavBytes)
            if (playResult.isFailure) {
                nextChunkDeferred?.cancel()
                activePrefetchJob?.cancel()
                activePrefetchJob = null
                val errorMessage =
                    playResult.exceptionOrNull()?.message ?: "playback_failed"
                eventEmitter.emit(SpeechEvents.speechFailed(commentId, errorMessage))
                return
            }
        }

        // Collect inter-comment prefetch using the same item that was peeked
        // in startPrefetch() to ensure the WAV is associated with the correct
        // commentId even if the queue was modified during chunk playback.
        if (prefetchNextItem != null) {
            collectPrefetch(prefetchNextItem)
        }

        eventEmitter.emit(SpeechEvents.speechCompleted(commentId))
    }

    /**
     * Returns synthesized WAV for the given item, using the prefetch cache
     * if available. Returns null and emits a failure event if synthesis fails.
     */
    private suspend fun synthesizeOrUsePrefetch(
        item: SpeechQueueItem,
        settings: SpeechSettings
    ): WavSynthesisResult? {
        val cached = prefetched
        if (cached != null && cached.commentId == item.commentId) {
            prefetched = null
            return cached.wavResult
        }

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
            return null
        }
        return synthesisResult.getOrThrow()
    }

    /**
     * Kicks off background synthesis for the next queued item.
     * Returns the peeked item (or null if the queue is empty).
     */
    private fun startPrefetch(settings: SpeechSettings): SpeechQueueItem? {
        val nextItem = queueManager.peek()
        activePrefetchJob = if (nextItem != null) {
            scope.async(synthDispatcher) {
                try {
                    val nextRequest = buildSpeechRequest(nextItem.text, settings)
                    engine.synthesize(nextRequest)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    null
                }
            }
        } else null
        return nextItem
    }

    /**
     * Awaits the in-flight prefetch job and stores the result for the next
     * [processItem] call.
     */
    private suspend fun collectPrefetch(nextItem: SpeechQueueItem) {
        val currentPrefetchJob = activePrefetchJob ?: return
        try {
            val result = currentPrefetchJob.await()
            if (result != null && result.isSuccess) {
                prefetched = PrefetchState(
                    commentId = nextItem.commentId,
                    wavResult = result.getOrThrow()
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Prefetch failed — will synthesize normally
        }
        activePrefetchJob = null
    }

    private fun buildSpeechRequest(text: String, settings: SpeechSettings): SpeechRequest {
        return SpeechRequest(
            text = text,
            speakerId = settings.speakerId,
            synthesisMode = settings.synthesisMode,
            speedScale = settings.speedScale,
            pitchScale = settings.pitchScale,
            intonationScale = settings.intonationScale,
            volumeScale = settings.volumeScale,
            prePhonemeLength = settings.prePhonemeLength,
            postPhonemeLength = settings.postPhonemeLength
        )
    }

    /**
     * Build a [SpeechRequest] for a chunk with adjusted phoneme lengths.
     * Intermediate boundaries use zero silence for seamless playback.
     */
    private fun buildChunkRequest(
        text: String,
        settings: SpeechSettings,
        isFirst: Boolean,
        isLast: Boolean
    ): SpeechRequest {
        return SpeechRequest(
            text = text,
            speakerId = settings.speakerId,
            synthesisMode = settings.synthesisMode,
            speedScale = settings.speedScale,
            pitchScale = settings.pitchScale,
            intonationScale = settings.intonationScale,
            volumeScale = settings.volumeScale,
            prePhonemeLength = if (isFirst) settings.prePhonemeLength else 0f,
            postPhonemeLength = if (isLast) settings.postPhonemeLength else 0f
        )
    }

    private suspend fun synthesizeSafe(request: SpeechRequest): Result<WavSynthesisResult> =
        try {
            engine.synthesize(request)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }

    private suspend fun playSafe(wavBytes: ByteArray): Result<Unit> =
        try {
            player.play(wavBytes)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        }
}
