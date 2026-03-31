package com.example.comerune.speech.infrastructure.plugin

import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import com.example.comerune.speech.domain.controller.SpeechController
import com.example.comerune.speech.domain.controller.SpeechControllerImpl
import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.model.RawComment
import com.example.comerune.speech.domain.model.ReplaceRule
import com.example.comerune.speech.domain.model.SpeechRuntimeStatus
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.model.SubmitResult
import com.example.comerune.speech.domain.model.VoicevoxModelManifest
import com.example.comerune.speech.domain.normalizer.DefaultCommentNormalizer
import com.example.comerune.speech.domain.normalizer.InMemoryDuplicateDetector
import com.example.comerune.speech.domain.queue.InMemorySpeechQueueManager
import com.example.comerune.speech.domain.repository.VoicevoxModelRepository
import com.example.comerune.speech.domain.settings.InMemorySettingsRepository
import com.example.comerune.speech.infrastructure.engine.VoicevoxEngineImpl
import com.example.comerune.speech.infrastructure.event.FlutterSpeechEventEmitter
import com.example.comerune.speech.infrastructure.player.MediaPlayerWavPlayer
import com.example.comerune.speech.infrastructure.repository.VoicevoxModelRepositoryImpl

class CommentSpeechPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "CommentSpeechPlugin"
        const val METHOD_CHANNEL = "com.example.comerune.speech/methods"
        const val EVENT_CHANNEL = "com.example.comerune.speech/events"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var controller: SpeechController? = null
    private var eventEmitter: FlutterSpeechEventEmitter? = null
    private var pluginScope: CoroutineScope? = null
    private var modelRepository: VoicevoxModelRepository? = null
    private var engine: VoicevoxEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger = binding.binaryMessenger

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }

        val duplicateDetector = InMemoryDuplicateDetector()
        val normalizer = DefaultCommentNormalizer(duplicateDetector)
        val queueManager = InMemorySpeechQueueManager(maxSize = 20)
        val settingsRepository = InMemorySettingsRepository()
        val emitter = FlutterSpeechEventEmitter()
        val context = binding.applicationContext
        val voicevoxEngine = VoicevoxEngineImpl(context)
        voicevoxEngine.onDownloadEvent = { event -> emitter.emit(event) }
        val player = MediaPlayerWavPlayer(context)

        eventEmitter = emitter
        engine = voicevoxEngine

        val repository = VoicevoxModelRepositoryImpl(context)
        modelRepository = repository

        controller = SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queueManager,
            engine = voicevoxEngine,
            player = player,
            settingsRepository = settingsRepository,
            eventEmitter = emitter,
            duplicateDetector = duplicateDetector
        )

        pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null

        eventChannel?.setStreamHandler(null)
        eventChannel = null

        controller?.release()
        controller = null

        pluginScope?.cancel()
        pluginScope = null

        eventEmitter?.setEventSink(null)
        eventEmitter = null

        modelRepository = null
        engine = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "[onMethodCall] method=${call.method}")
        val ctrl = controller
        if (ctrl == null) {
            Log.e(TAG, "[onMethodCall] controller is null — plugin not attached")
            result.error("NOT_INITIALIZED", "Plugin not attached to engine", null)
            return
        }

        when (call.method) {
            "initialize" -> {
                Log.d(TAG, "[onMethodCall] → initialize")
                handleAsync(result) {
                    val initResult = ctrl.initialize()
                    if (initResult.isSuccess) {
                        // Ensure bundled models are available and load them
                        val repo = modelRepository
                        val eng = engine
                        if (repo != null && eng != null) {
                            for (model in VoicevoxModelManifest.models.filter { it.isBundled }) {
                                repo.ensureBundledModel(model)
                                val modelFile = repo.getModelFile(model.modelId)
                                if (modelFile != null) {
                                    val loadResult = eng.loadModel(modelFile.absolutePath)
                                    if (loadResult.isFailure) {
                                        Log.w(
                                            TAG,
                                            "Failed to load bundled model ${model.modelId}: ${loadResult.exceptionOrNull()?.message}"
                                        )
                                    }
                                }
                            }
                        }
                    }
                    initResult
                }
            }
            "start" -> {
                Log.d(TAG, "[onMethodCall] → start")
                handleAsync(result) { ctrl.start() }
            }
            "stop" -> {
                val clearQueue = call.argument<Boolean>("clearQueue") ?: false
                Log.d(TAG, "[onMethodCall] → stop(clearQueue=$clearQueue)")
                handleAsync(result) { ctrl.stop(clearQueue) }
            }
            "skip" -> handleAsync(result) { ctrl.skip() }
            "clearQueue" -> handleAsync(result) { ctrl.clearQueue() }
            "submitComment" -> {
                val rawComment = parseRawComment(call, result) ?: return
                Log.d(TAG, "[onMethodCall] → submitComment id=${rawComment.id}, text=${rawComment.text.take(30)}")
                handleAsync(result) {
                    val submitResult = ctrl.submitComment(rawComment)
                    Log.d(TAG, "[onMethodCall] submitComment result=$submitResult")
                    submitResult.map { it.toMap() }
                }
            }
            "updateSettings" -> {
                val settings = parseSpeechSettings(call)
                Log.d(TAG, "[onMethodCall] → updateSettings enabled=${settings.enabled}, speaker=${settings.speakerId}, speed=${settings.speedScale}")
                handleAsync(result) { ctrl.updateSettings(settings) }
            }
            "getStatus" -> {
                Log.d(TAG, "[onMethodCall] → getStatus")
                handleAsync(result) {
                    val status = ctrl.getStatus()
                    Log.d(TAG, "[onMethodCall] getStatus result: engine=${status.engineState}, player=${status.playerState}, queue=${status.queueSize}")
                    Result.success(status.toMap())
                }
            }
            "release" -> {
                Log.d(TAG, "[onMethodCall] → release")
                try {
                    ctrl.release()
                    result.success(mapOf("ok" to true))
                } catch (e: Exception) {
                    Log.e(TAG, "[onMethodCall] release FAILED: ${e.message}")
                    result.error(
                        "RELEASE_ERROR",
                        e.message ?: "Unknown error during release",
                        null
                    )
                }
            }
            "getAvailableModels" -> {
                val repo = modelRepository
                if (repo == null) {
                    result.error("NOT_INITIALIZED", "Model repository not available", null)
                } else {
                    result.success(repo.getAvailableModels().map { it.toMap() })
                }
            }
            "downloadModel" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId == null) {
                    result.error("INVALID_ARGUMENT", "Required field 'modelId' is missing", null)
                    return
                }
                val repo = modelRepository
                val emitter = eventEmitter
                if (repo == null) {
                    result.error("NOT_INITIALIZED", "Model repository not available", null)
                    return
                }
                val modelInfo = VoicevoxModelManifest.findByModelId(modelId)
                handleAsync(result) {
                    emitter?.emit(
                        mapOf(
                            "type" to "model_download_started",
                            "payload" to mapOf(
                                "modelId" to modelId,
                                "fileName" to (modelInfo?.vvmFileName ?: "")
                            )
                        )
                    )
                    val downloadResult = repo.downloadModel(modelId) { bytesDownloaded, totalBytes ->
                        emitter?.emit(
                            mapOf(
                                "type" to "model_download_progress",
                                "payload" to mapOf(
                                    "modelId" to modelId,
                                    "bytesDownloaded" to bytesDownloaded,
                                    "totalBytes" to totalBytes
                                )
                            )
                        )
                    }
                    if (downloadResult.isSuccess) {
                        emitter?.emit(
                            mapOf(
                                "type" to "model_download_completed",
                                "payload" to mapOf("modelId" to modelId)
                            )
                        )
                    } else {
                        emitter?.emit(
                            mapOf(
                                "type" to "model_download_failed",
                                "payload" to mapOf(
                                    "modelId" to modelId,
                                    "error" to (downloadResult.exceptionOrNull()?.message ?: "Unknown error")
                                )
                            )
                        )
                    }
                    downloadResult
                }
            }
            "deleteModel" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId == null) {
                    result.error("INVALID_ARGUMENT", "Required field 'modelId' is missing", null)
                    return
                }
                val repo = modelRepository
                val emitter = eventEmitter
                if (repo == null) {
                    result.error("NOT_INITIALIZED", "Model repository not available", null)
                    return
                }
                val deleteResult = repo.deleteModel(modelId)
                if (deleteResult.isSuccess) {
                    emitter?.emit(
                        mapOf(
                            "type" to "model_deleted",
                            "payload" to mapOf("modelId" to modelId)
                        )
                    )
                    result.success(mapOf("ok" to true))
                } else {
                    result.error(
                        "DELETE_ERROR",
                        deleteResult.exceptionOrNull()?.message ?: "Unknown error",
                        null
                    )
                }
            }
            "getDownloadedModels" -> {
                val repo = modelRepository
                if (repo == null) {
                    result.error("NOT_INITIALIZED", "Model repository not available", null)
                } else {
                    val downloadedIds = VoicevoxModelManifest.models
                        .filter { repo.isModelDownloaded(it.modelId) }
                        .map { it.modelId }
                    result.success(downloadedIds)
                }
            }
            "loadModel" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId == null) {
                    result.error("INVALID_ARGUMENT", "Required field 'modelId' is missing", null)
                    return
                }
                val repo = modelRepository
                val eng = engine
                if (repo == null || eng == null) {
                    result.error("NOT_INITIALIZED", "Plugin not fully initialized", null)
                    return
                }
                val modelFile = repo.getModelFile(modelId)
                if (modelFile == null) {
                    result.error(
                        "MODEL_NOT_FOUND",
                        "Model $modelId is not downloaded",
                        null
                    )
                    return
                }
                handleAsync(result) {
                    eng.loadModel(modelFile.absolutePath)
                }
            }
            "cancelDownload" -> {
                val modelId = call.argument<String>("modelId")
                if (modelId == null) {
                    result.error("INVALID_ARGUMENT", "Required field 'modelId' is missing", null)
                    return
                }
                val repo = modelRepository
                if (repo == null) {
                    result.error("NOT_INITIALIZED", "Model repository not available", null)
                    return
                }
                repo.cancelDownload(modelId)
                result.success(mapOf("ok" to true))
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventEmitter?.setEventSink(
            if (events != null) { event -> events.success(event) } else null
        )
    }

    override fun onCancel(arguments: Any?) {
        eventEmitter?.setEventSink(null)
    }

    // --- Argument parsing ---

    private fun parseRawComment(
        call: MethodCall,
        result: MethodChannel.Result
    ): RawComment? {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error(
                "INVALID_ARGUMENT",
                "Required field 'id' is missing or not a String",
                null
            )
            return null
        }

        val text = call.argument<String>("text")
        if (text == null) {
            result.error(
                "INVALID_ARGUMENT",
                "Required field 'text' is missing or not a String",
                null
            )
            return null
        }

        val postedAtEpochMs = call.argument<Number>("postedAtEpochMs")
        if (postedAtEpochMs == null) {
            result.error(
                "INVALID_ARGUMENT",
                "Required field 'postedAtEpochMs' is missing or not a number",
                null
            )
            return null
        }

        return RawComment(
            id = id,
            text = text,
            userId = call.argument<String>("userId"),
            postedAtEpochMs = postedAtEpochMs.toLong(),
            score = call.argument<Number>("score")?.toInt(),
            isOwner = call.argument<Boolean>("isOwner") ?: false
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun parseSpeechSettings(call: MethodCall): SpeechSettings {
        val rawRules = call.argument<List<Map<String, Any?>>>("dictionaryRules")
        val dictionaryRules = rawRules?.mapNotNull { map ->
            val pattern = map["pattern"] as? String ?: return@mapNotNull null
            val replacement = map["replacement"] as? String ?: return@mapNotNull null
            val enabled = map["enabled"] as? Boolean ?: true
            ReplaceRule(pattern = pattern, replacement = replacement, enabled = enabled)
        } ?: emptyList()

        val ngWords = call.argument<List<String>>("ngWords") ?: emptyList()

        return SpeechSettings(
            enabled = call.argument<Boolean>("enabled") ?: true,
            speakerId = call.argument<Number>("speakerId")?.toInt() ?: 0,
            speedScale = call.argument<Number>("speedScale")?.toFloat() ?: 1.15f,
            pitchScale = call.argument<Number>("pitchScale")?.toFloat() ?: 0.0f,
            intonationScale = call.argument<Number>("intonationScale")?.toFloat() ?: 1.0f,
            volumeScale = call.argument<Number>("volumeScale")?.toFloat() ?: 0.7f,
            prePhonemeLength = call.argument<Number>("prePhonemeLength")?.toFloat() ?: 0.1f,
            postPhonemeLength = call.argument<Number>("postPhonemeLength")?.toFloat() ?: 0.1f,
            maxTextLength = call.argument<Number>("maxTextLength")?.toInt() ?: 50,
            maxQueueSize = (call.argument<Number>("maxQueueSize")?.toInt() ?: 20).coerceAtLeast(1),
            duplicateWindowMs = (call.argument<Number>("duplicateWindowMs")?.toLong() ?: 5000L).coerceAtLeast(0L),
            skipEmojiOnly = call.argument<Boolean>("skipEmojiOnly") ?: true,
            skipUrlOnly = call.argument<Boolean>("skipUrlOnly") ?: true,
            replaceUrlWith = call.argument<String>("replaceUrlWith") ?: "URL省略",
            trimLongTextSuffix = call.argument<String>("trimLongTextSuffix") ?: "、以下省略",
            dictionaryRules = dictionaryRules,
            ngWords = ngWords
        )
    }

    // --- Serialization extensions ---

    private fun SubmitResult.toMap(): Map<String, Any?> = mapOf(
        "accepted" to accepted,
        "skipped" to skipped,
        "normalizedText" to normalizedText,
        "skipReason" to skipReason,
        "queueSize" to queueSize
    )

    private fun SpeechRuntimeStatus.toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "engineState" to engineState.name,
        "playerState" to playerState.name,
        "queueSize" to queueSize,
        "currentCommentId" to currentCommentId,
        "currentText" to currentText,
        "currentSpeakerId" to currentSpeakerId
    )

    // --- Async helper ---

    private fun handleAsync(
        result: MethodChannel.Result,
        block: suspend () -> Result<Any?>
    ) {
        val scope = pluginScope
        if (scope == null) {
            result.error("NOT_INITIALIZED", "Plugin coroutine scope not available", null)
            return
        }

        scope.launch {
            try {
                val outcome = block()
                outcome.fold(
                    onSuccess = { value ->
                        if (value is Map<*, *>) {
                            result.success(value)
                        } else {
                            result.success(mapOf("ok" to true))
                        }
                    },
                    onFailure = { e ->
                        result.error(
                            "SPEECH_ERROR",
                            e.message ?: "Unknown error",
                            null
                        )
                    }
                )
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result.error(
                    "SPEECH_ERROR",
                    e.message ?: "Unknown error",
                    null
                )
            }
        }
    }
}
