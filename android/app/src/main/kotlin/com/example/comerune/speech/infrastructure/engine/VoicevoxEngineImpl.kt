package com.example.comerune.speech.infrastructure.engine

import android.content.Context
import android.util.Log
import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.SynthesisMode
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.VoicevoxModelManifest
import com.example.comerune.speech.domain.model.WavSynthesisResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.zip.GZIPInputStream

/**
 * Real implementation of [VoicevoxEngine] backed by VOICEVOX Core 0.16.2 via JNI.
 *
 * [initialize] only uses local assets and never performs network downloads.
 * Asset downloads are user-triggered via [prepareForModelDownload].
 *
 * @param context Android application context used for file storage.
 *                Must be an application context to avoid activity lifecycle leaks.
 */
class VoicevoxEngineImpl(private val context: Context) : VoicevoxEngine {

    companion object {
        private const val TAG = "VoicevoxEngineImpl"
        private const val VOICEVOX_DIR = "voicevox"
        private const val OPEN_JTALK_DICT_DIR_NAME = "open_jtalk_dic_utf_8-1.11"
        private const val VVM_DIR_NAME = "voicevox_models"

        /**
         * Apply speech parameters to an AudioQuery JSON string.
         *
         * Exposed as a companion function for testability — no instance
         * state is required.
         *
         * @throws org.json.JSONException if [audioQueryJson] is not valid JSON
         */
        internal fun applyParametersToAudioQuery(
            audioQueryJson: String,
            request: SpeechRequest
        ): String {
            val json = JSONObject(audioQueryJson)
            json.put("speedScale", sanitize(request.speedScale, 1.15f).toDouble())
            json.put("pitchScale", sanitize(request.pitchScale, 0.0f).toDouble())
            json.put("intonationScale", sanitize(request.intonationScale, 1.0f).toDouble())
            json.put("volumeScale", sanitize(request.volumeScale, 0.7f).toDouble())
            json.put("prePhonemeLength", sanitize(request.prePhonemeLength, 0.1f).toDouble())
            json.put("postPhonemeLength", sanitize(request.postPhonemeLength, 0.1f).toDouble())
            return json.toString()
        }

        /**
         * Return [fallback] when [value] is NaN or infinite.
         *
         * Fallback values must match the defaults in [SpeechSettings].
         */
        private fun sanitize(value: Float, fallback: Float): Float =
            if (value.isNaN() || value.isInfinite()) fallback else value

        /**
         * Apply [volumeScale] to the PCM samples in a 16-bit WAV byte array.
         *
         * Scans for the "data" chunk, then multiplies each 16-bit little-endian
         * sample by [volumeScale], clamping to [-32768, 32767].
         *
         * Returns the original [wavBytes] unmodified if volumeScale is
         * effectively 1.0, or if the WAV format cannot be parsed.
         */
        internal fun applyVolumeToWav(wavBytes: ByteArray, volumeScale: Float): ByteArray {
            if (wavBytes.size < 44) return wavBytes
            val clamped = volumeScale.coerceIn(0f, 2f)
            if ((clamped - 1.0f).let { it > -0.001f && it < 0.001f }) return wavBytes

            val dataOffset = findDataChunkOffset(wavBytes) ?: return wavBytes
            val result = wavBytes.copyOf()

            var i = dataOffset
            while (i + 1 < result.size) {
                val lo = result[i].toInt() and 0xFF
                val hi = result[i + 1].toInt()
                val sample = (hi shl 8) or lo
                val scaled = (sample * clamped).toInt().coerceIn(-32768, 32767)
                result[i] = (scaled and 0xFF).toByte()
                result[i + 1] = ((scaled shr 8) and 0xFF).toByte()
                i += 2
            }
            return result
        }

        private fun findDataChunkOffset(wavBytes: ByteArray): Int? {
            var pos = 12
            while (pos + 8 <= wavBytes.size) {
                val id = String(wavBytes, pos, 4, Charsets.US_ASCII)
                val size = ((wavBytes[pos + 4].toInt() and 0xFF)) or
                        ((wavBytes[pos + 5].toInt() and 0xFF) shl 8) or
                        ((wavBytes[pos + 6].toInt() and 0xFF) shl 16) or
                        ((wavBytes[pos + 7].toInt() and 0xFF) shl 24)
                if (id == "data") return pos + 8
                if (size < 0) return null
                pos += 8 + size
            }
            return null
        }

        internal fun buildMissingAssetsMessage(hasDict: Boolean, hasAnyVvm: Boolean): String? {
            if (hasDict && hasAnyVvm) {
                return null
            }
            val missing = mutableListOf<String>()
            if (!hasDict) {
                missing += "open_jtalk 辞書"
            }
            if (!hasAnyVvm) {
                missing += "音声モデル"
            }
            return "VOICEVOXの初期化に必要なデータが未準備です（不足: ${missing.joinToString("・")}）。" +
                "話者ライブラリでモデルをダウンロードしてください。"
        }

        internal fun buildPrepareForModelDownloadFailure(exception: Exception): RuntimeException {
            val message = when (exception) {
                is IOException ->
                    "VOICEVOX辞書のダウンロードに失敗しました。ネットワーク接続を確認してください。"
                else ->
                    exception.message ?: "Unknown dictionary download error"
            }
            return RuntimeException(message, exception)
        }

        internal suspend fun runPrepareForModelDownload(
            previousState: TtsEngineState,
            updateEngineState: (TtsEngineState, String) -> Unit,
            prepareAction: suspend () -> Unit
        ): Result<Unit> {
            return try {
                prepareAction()
                updateEngineState(previousState, "prepare_download_completed")
                Result.success(Unit)
            } catch (e: CancellationException) {
                updateEngineState(previousState, "prepare_download_cancelled_restore")
                throw e
            } catch (e: Exception) {
                updateEngineState(previousState, "prepare_download_failed_restore")
                Result.failure(buildPrepareForModelDownloadFailure(e))
            }
        }

        /**
         * Increment this when remote assets change to force re-download.
         * The effective version used for comparison also includes the app's
         * versionCode so that APK upgrades automatically invalidate cached
         * assets (see [getEffectiveAssetVersion]).
         */
        private const val ASSET_VERSION = "1"
        private const val VERSION_FILE = ".asset_version"

        private const val OPEN_JTALK_DICT_URL =
            "https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz"
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 120_000
        private const val PROGRESS_REPORT_INTERVAL_BYTES = 1_048_576L // 1 MB
    }

    @Volatile
    private var state: TtsEngineState = TtsEngineState.UNINITIALIZED

    /** Lock for state transitions and synthesis count updates (release, synthesize). */
    private val stateLock = Any()

    /** Mutex for lifecycle operations (initialize, loadModel, prepareForModelDownload). */
    private val mutex = Mutex()

    /**
     * Number of synthesis calls currently in flight.
     * Used to derive [TtsEngineState.SYNTHESIZING] without blocking
     * concurrent synthesis — the native VOICEVOX Core synthesizer is
     * internally thread-safe for `const` operations.
     */
    private val activeSynthesisCount = AtomicInteger(0)

    private val loadedModelPaths: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val loadedModelIds: MutableSet<String> = ConcurrentHashMap.newKeySet()

    private class MissingAssetsException(message: String) : IllegalStateException(message)

    /**
     * Optional callback invoked during asset download to report progress.
     * The map follows the same structure as [com.example.comerune.speech.domain.event.SpeechEvents].
     */
    var onDownloadEvent: ((Map<String, Any?>) -> Unit)? = null

    override suspend fun initialize(): Result<Unit> =
        mutex.withLock {
            if (state == TtsEngineState.READY) {
                return@withLock Result.success(Unit)
            }

            // Allow re-initialization from ERROR state (e.g., after a native crash
            // during a previous initialize attempt)
            if (state != TtsEngineState.UNINITIALIZED && state != TtsEngineState.ERROR) {
                return@withLock Result.failure(
                    IllegalStateException(
                        "Cannot initialize from state: $state"
                    )
                )
            }

            updateEngineState(TtsEngineState.INITIALIZING, "initialize_started")
            loadedModelPaths.clear()
            loadedModelIds.clear()

            try {
                withContext(Dispatchers.IO) {
                    val baseDir = File(context.filesDir, VOICEVOX_DIR)
                    val dictDir = File(baseDir, OPEN_JTALK_DICT_DIR_NAME)
                    val modelDir = File(baseDir, VVM_DIR_NAME)

                    ensureLocalAssetsAvailable(dictDir, modelDir)
                    updateEngineState(TtsEngineState.INITIALIZING, "assets_ready")

                    Log.i(TAG, "Calling NativeVoicevoxBridge.nativeInitialize(${dictDir.absolutePath})")
                    val initialized = NativeVoicevoxBridge.nativeInitialize(
                        dictDir.absolutePath
                    )
                    Log.i(TAG, "nativeInitialize returned: $initialized")
                    if (!initialized) {
                        throw RuntimeException(
                            "NativeVoicevoxBridge.nativeInitialize failed"
                        )
                    }

                    val vvmFiles = modelDir.listFiles { file ->
                        file.extension == "vvm"
                    }
                    Log.i(TAG, "VVM files found: ${vvmFiles?.map { it.name } ?: "null"}")
                    if (vvmFiles.isNullOrEmpty()) {
                        Log.w(TAG, "No .vvm files found in ${modelDir.absolutePath}")
                    } else {
                        for (vvm in vvmFiles) {
                            val normalizedPath = normalizeModelPath(vvm.absolutePath)
                            val modelId = extractModelId(normalizedPath)
                            Log.i(
                                TAG,
                                "Loading voice model: $normalizedPath (${vvm.length()} bytes)"
                            )
                            val loaded = NativeVoicevoxBridge.nativeLoadModel(normalizedPath)
                            Log.i(TAG, "nativeLoadModel(${vvm.name}) returned: $loaded")
                            if (!loaded) {
                                throw RuntimeException(
                                    "Failed to load voice model: ${vvm.name}"
                                )
                            }
                            markModelLoaded(normalizedPath, modelId)
                        }
                    }
                }

                updateEngineState(TtsEngineState.READY, "initialize_completed")
                Log.i(TAG, "VOICEVOX engine initialized successfully")
                Result.success(Unit)
            } catch (e: Throwable) {
                updateEngineState(TtsEngineState.ERROR, "initialize_failed")
                loadedModelPaths.clear()
                loadedModelIds.clear()
                Log.e(TAG, "Initialization failed", e)
                val message = when (e) {
                    is MissingAssetsException ->
                        e.message ?: "VOICEVOXの必須データが未準備です。"
                    is IOException ->
                        "VOICEVOX初期化に必要なローカルデータへアクセスできませんでした。"
                    is UnsatisfiedLinkError ->
                        "VOICEVOXネイティブライブラリの読み込みに失敗しました。このデバイスのアーキテクチャはサポートされていない可能性があります。"
                    else ->
                        e.message ?: "Unknown initialization error"
                }
                Result.failure(RuntimeException(message, e))
            }
        }

    override suspend fun prepareForModelDownload(): Result<Unit> =
        mutex.withLock {
            val previousState = state
            runPrepareForModelDownload(
                previousState = previousState,
                updateEngineState = ::updateEngineState
            ) {
                withContext(Dispatchers.IO) {
                    val baseDir = File(context.filesDir, VOICEVOX_DIR)
                    val dictDir = File(baseDir, OPEN_JTALK_DICT_DIR_NAME)
                    ensureDictionaryAvailableForDownload(baseDir, dictDir)
                }
            }
        }

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> {
        // Guard + count increment must be atomic to prevent race with release().
        // No lifecycle mutex needed — concurrent synthesis is safe because
        // VOICEVOX Core's synthesizer accepts `const` pointers and is
        // internally thread-safe. The C++ shared_mutex allows parallel reads.
        synchronized(stateLock) {
            val currentState = state
            if (currentState != TtsEngineState.READY &&
                currentState != TtsEngineState.SYNTHESIZING
            ) {
                return Result.failure(
                    IllegalStateException(
                        "Engine is not ready. Current state: $currentState"
                    )
                )
            }
            activeSynthesisCount.incrementAndGet()
            state = TtsEngineState.SYNTHESIZING
        }

        return try {
            val wavBytes = withContext(Dispatchers.IO) {
                when (request.synthesisMode) {
                    SynthesisMode.AUDIO_QUERY -> synthesizeViaAudioQuery(request)
                    SynthesisMode.ONE_SHOT -> synthesizeViaOneShot(request)
                }
            }

            Result.success(
                WavSynthesisResult(
                    wavBytes = wavBytes,
                    text = request.text,
                    durationEstimateMs = estimateDurationFromWav(wavBytes)
                )
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Synthesis failed", e)
            Result.failure(e)
        } finally {
            synchronized(stateLock) {
                if (activeSynthesisCount.decrementAndGet() == 0) {
                    // Restore READY only when no synthesis is in flight
                    // and release() hasn't been called concurrently.
                    if (state == TtsEngineState.SYNTHESIZING) {
                        state = TtsEngineState.READY
                    }
                }
            }
        }
    }

    /**
     * Synthesize WAV via the AudioQuery path, which allows applying
     * volumeScale, speedScale, pitchScale, intonationScale, and
     * pre/postPhonemeLength parameters at the synthesis level.
     *
     * This prevents audio clipping that occurs with the TTS one-shot API
     * where these parameters are ignored.
     *
     * @throws RuntimeException if AudioQuery creation or synthesis fails
     */
    private fun synthesizeViaAudioQuery(request: SpeechRequest): ByteArray {
        val audioQueryJson = NativeVoicevoxBridge.nativeCreateAudioQuery(
            text = request.text,
            speakerId = request.speakerId
        ) ?: throw RuntimeException(
            "AudioQuery creation returned null (text length=${request.text.length})"
        )

        val modifiedJson = applyParametersToAudioQuery(
            audioQueryJson,
            request
        )

        return NativeVoicevoxBridge.nativeSynthesis(
            audioQueryJson = modifiedJson,
            speakerId = request.speakerId
        ) ?: throw RuntimeException(
            "Synthesis from AudioQuery returned null (text length=${request.text.length})"
        )
    }

    /**
     * Synthesize WAV via the TTS one-shot API.
     *
     * This is faster than the AudioQuery path but does **not** support
     * speed/pitch/intonation/volume parameters — those are fixed at the
     * engine's built-in defaults.
     *
     * @throws RuntimeException if TTS synthesis fails
     */
    private fun synthesizeViaOneShot(request: SpeechRequest): ByteArray {
        val wav = NativeVoicevoxBridge.nativeTts(
            text = request.text,
            speakerId = request.speakerId,
            speedScale = request.speedScale,
            pitchScale = request.pitchScale,
            intonationScale = request.intonationScale,
            volumeScale = request.volumeScale,
            prePhonemeLength = request.prePhonemeLength,
            postPhonemeLength = request.postPhonemeLength
        ) ?: throw RuntimeException(
            "TTS one-shot returned null (text length=${request.text.length})"
        )
        // VOICEVOX Core 0.16.2 の TTS one-shot API はパラメータを無視するため、
        // WAV の PCM データに直接 volumeScale を適用する。
        return applyVolumeToWav(wav, request.volumeScale)
    }

    /**
     * Apply [volumeScale] to the PCM samples in a 16-bit WAV byte array.
     *
     * Visible as a companion function for testability.
     */
    private fun applyVolumeToWav(wavBytes: ByteArray, volumeScale: Float): ByteArray =
        Companion.applyVolumeToWav(wavBytes, volumeScale)

    /**
     * Apply speech parameters to an AudioQuery JSON object.
     *
     * The AudioQuery JSON from VOICEVOX contains fields like
     * `speedScale`, `pitchScale`, `intonationScale`, `volumeScale`,
     * `prePhonemeLength`, `postPhonemeLength` at the top level.
     * This method overrides them with the values from [request].
     *
     * @throws org.json.JSONException if [audioQueryJson] is not valid JSON
     */
    private fun applyParametersToAudioQuery(
        audioQueryJson: String,
        request: SpeechRequest
    ): String = Companion.applyParametersToAudioQuery(audioQueryJson, request)

    override suspend fun loadModel(modelPath: String): Result<Unit> =
        mutex.withLock {
            if (state != TtsEngineState.READY) {
                return@withLock Result.failure(
                    IllegalStateException("Cannot load model from state: $state")
                )
            }
            val normalizedPath = normalizeModelPath(modelPath)
            val modelId = extractModelId(normalizedPath)
            val alreadyLoadedByPath = loadedModelPaths.contains(normalizedPath)
            val alreadyLoadedById = modelId != null && loadedModelIds.contains(modelId)
            if (alreadyLoadedByPath || alreadyLoadedById) {
                // Verify that the native synthesizer actually has this model loaded.
                // The tracking sets can become stale (e.g. after deleteModel followed
                // by re-download) so we probe the native engine before skipping.
                val nativeHasModel = isModelAlreadyLoadedBySpeakerProbe(modelId)
                if (nativeHasModel) {
                    val reason = when {
                        alreadyLoadedByPath && alreadyLoadedById -> "already_loaded_path_and_id"
                        alreadyLoadedByPath -> "already_loaded_path"
                        else -> "already_loaded_id"
                    }
                    Log.i(
                        TAG,
                        "loadModel skip: reason=$reason modelId=${modelId ?: "unknown"} modelPath=$normalizedPath"
                    )
                    return@withLock Result.success(Unit)
                }
                // Tracking says loaded but native doesn't have it — clear stale
                // tracking and fall through to actually load the model.
                Log.w(
                    TAG,
                    "loadModel stale tracking detected: modelId=${modelId ?: "unknown"} " +
                        "modelPath=$normalizedPath — clearing and reloading"
                )
                loadedModelPaths.remove(normalizedPath)
                if (modelId != null) {
                    loadedModelIds.remove(modelId)
                }
            }

            try {
                withContext(Dispatchers.IO) {
                    Log.i(TAG, "Loading model: $normalizedPath")
                    val loaded = NativeVoicevoxBridge.nativeLoadModel(normalizedPath)
                    if (!loaded) {
                        Log.w(
                            TAG,
                            "loadModel nativeLoadModel returned false: modelId=${modelId ?: "unknown"} modelPath=$normalizedPath"
                        )
                        val recoveredAsAlreadyLoaded =
                            isModelAlreadyLoadedBySpeakerProbe(modelId)
                        if (recoveredAsAlreadyLoaded) {
                            markModelLoaded(normalizedPath, modelId)
                            Log.i(
                                TAG,
                                "loadModel fallback: reason=already_loaded_by_probe modelId=${modelId ?: "unknown"} modelPath=$normalizedPath"
                            )
                            return@withContext
                        }
                        Log.w(
                            TAG,
                            "loadModel fallback: reason=probe_not_loaded modelId=${modelId ?: "unknown"} modelPath=$normalizedPath"
                        )
                        throw RuntimeException("Failed to load model: $normalizedPath")
                    }
                    markModelLoaded(normalizedPath, modelId)
                    Log.i(
                        TAG,
                        "Model loaded successfully: modelId=${modelId ?: "unknown"} path=$normalizedPath"
                    )
                }
                Result.success(Unit)
            } catch (e: Throwable) {
                Log.e(TAG, "loadModel failed", e)
                Result.failure(e)
            }
        }

    override fun isReady(): Boolean =
        state == TtsEngineState.READY || state == TtsEngineState.SYNTHESIZING

    override fun currentState(): TtsEngineState = state

    override fun clearLoadedModel(modelId: String) {
        val removedPath = loadedModelPaths.removeAll { path ->
            extractModelId(path) == modelId
        }
        val removedId = loadedModelIds.remove(modelId)
        Log.i(
            TAG,
            "clearLoadedModel: modelId=$modelId removedPath=$removedPath removedId=$removedId"
        )
    }

    override fun release() {
        // Since release() is non-suspend, we use a @Volatile flag + native-level
        // g_mutex (exclusive lock) for thread safety instead of the coroutine Mutex.
        // Any in-flight synthesis calls will see state == UNINITIALIZED in their
        // finally block and skip the READY restore. The native nativeRelease()
        // acquires an exclusive lock, so it waits for in-flight synthesis to finish.
        val alreadyReleased = synchronized(stateLock) {
            if (state == TtsEngineState.UNINITIALIZED) {
                true
            } else {
                state = TtsEngineState.UNINITIALIZED
                activeSynthesisCount.set(0)
                loadedModelPaths.clear()
                loadedModelIds.clear()
                false
            }
        }
        if (alreadyReleased) {
            Log.i(TAG, "VOICEVOX engine already released, skipping")
            return
        }
        try {
            NativeVoicevoxBridge.nativeRelease()
            Log.i(TAG, "VOICEVOX engine released")
        } catch (e: Throwable) {
            Log.w(TAG, "nativeRelease failed (native library may not have loaded): ${e.message}")
        }
    }

    // ── Asset download ──────────────────────────────────────────────────

    /**
     * Return a version string that combines [ASSET_VERSION] with the app's
     * `versionCode`. This ensures that an APK upgrade (which changes
     * versionCode) invalidates cached assets even when [ASSET_VERSION]
     * itself has not been bumped.
     */
    private fun getEffectiveAssetVersion(): String {
        val versionCode = try {
            val packageInfo =
                context.packageManager.getPackageInfo(context.packageName, 0)
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read versionCode, falling back to 0", e)
            0L
        }
        return "${ASSET_VERSION}_$versionCode"
    }

    /**
     * Ensure required local assets exist for initialization.
     *
     * This method does not perform network downloads; missing assets should be
     * prepared via [prepareForModelDownload].
     */
    private fun ensureLocalAssetsAvailable(dictDir: File, modelDir: File) {
        val hasDict = dictDir.exists() && (dictDir.listFiles()?.isNotEmpty() == true)
        val hasAnyVvm = modelDir.exists() && (modelDir.listFiles()?.any { it.extension == "vvm" } == true)

        Log.i(
            TAG,
            "Local asset readiness: hasDict=$hasDict hasAnyVvm=$hasAnyVvm"
        )

        if (hasDict && hasAnyVvm) {
            return
        }

        val message = buildMissingAssetsMessage(hasDict = hasDict, hasAnyVvm = hasAnyVvm)
            ?: "VOICEVOXの初期化に必要なデータが未準備です。"
        throw MissingAssetsException(message)
    }

    /**
     * Ensure the OpenJTalk dictionary is present for model download flows.
     * Dictionary download is user-triggered and happens only from explicit
     * model download actions.
     */
    private fun ensureDictionaryAvailableForDownload(baseDir: File, dictDir: File) {
        val effectiveVersion = getEffectiveAssetVersion()
        val versionFile = File(baseDir, VERSION_FILE)
        val currentVersion = if (versionFile.exists()) {
            versionFile.readText().trim()
        } else {
            null
        }
        val hasDict = dictDir.exists() && (dictDir.listFiles()?.isNotEmpty() == true)
        val versionMatches = currentVersion == effectiveVersion

        if (hasDict && versionMatches) {
            Log.i(TAG, "Dictionary already prepared (version $effectiveVersion)")
            return
        }

        if (!baseDir.exists() && !baseDir.mkdirs()) {
            throw IOException("Failed to create directory: ${baseDir.absolutePath}")
        }

        if (dictDir.exists()) {
            dictDir.deleteRecursively()
            Log.i(TAG, "Cleared stale dictionary directory: ${dictDir.absolutePath}")
        }

        updateEngineState(
            TtsEngineState.DOWNLOADING,
            "download_dict:$OPEN_JTALK_DICT_DIR_NAME"
        )
        emitDownloadEvent("download_started", OPEN_JTALK_DICT_DIR_NAME)
        downloadAndExtractTarGz(
            url = OPEN_JTALK_DICT_URL,
            targetDir = dictDir,
            stripPrefix = OPEN_JTALK_DICT_DIR_NAME,
            displayName = OPEN_JTALK_DICT_DIR_NAME
        )

        versionFile.writeText(effectiveVersion)
        emitDownloadEvent("download_completed", "")
        Log.i(TAG, "Dictionary prepared (version $effectiveVersion)")
    }

    private fun normalizeModelPath(path: String): String = try {
        File(path).canonicalPath
    } catch (_: IOException) {
        File(path).absolutePath
    }

    private fun extractModelId(modelPath: String): String? =
        File(modelPath).nameWithoutExtension
            .takeIf { it.isNotBlank() }

    private fun markModelLoaded(modelPath: String, modelId: String?) {
        loadedModelPaths.add(modelPath)
        if (!modelId.isNullOrBlank()) {
            loadedModelIds.add(modelId)
        }
    }

    private fun isModelAlreadyLoadedBySpeakerProbe(modelId: String?): Boolean {
        if (modelId.isNullOrBlank()) {
            return false
        }

        val probeSpeakerId = VoicevoxModelManifest.findByModelId(modelId)
            ?.speakerIds
            ?.firstOrNull()
            ?: return false

        return try {
            val probeQuery = NativeVoicevoxBridge.nativeCreateAudioQuery(
                text = "ロード確認",
                speakerId = probeSpeakerId
            )
            val alreadyLoaded = !probeQuery.isNullOrEmpty()
            Log.i(
                TAG,
                "loadModel probe: modelId=$modelId speakerId=$probeSpeakerId alreadyLoaded=$alreadyLoaded"
            )
            alreadyLoaded
        } catch (e: Throwable) {
            Log.w(
                TAG,
                "loadModel probe failed: modelId=$modelId speakerId=$probeSpeakerId error=${e.message}"
            )
            false
        }
    }

    /**
     * Download a tar.gz archive from [url], extract it to [targetDir],
     * stripping the leading [stripPrefix] directory from entry paths.
     */
    private fun downloadAndExtractTarGz(
        url: String,
        targetDir: File,
        stripPrefix: String,
        displayName: String
    ) {
        targetDir.mkdirs()
        val tempFile = File.createTempFile("download_", ".tar.gz", targetDir.parentFile)
        try {
            // Download to temp file
            val connection = openConnection(url)
            try {
                val totalBytes = connection.contentLengthLong
                connection.inputStream.use { input ->
                    tempFile.outputStream().use { output ->
                        copyWithProgress(input, output, totalBytes, displayName)
                    }
                }
                Log.i(TAG, "Downloaded $displayName (${tempFile.length()} bytes)")
            } finally {
                connection.disconnect()
            }

            // Extract tar.gz
            updateEngineState(
                TtsEngineState.EXTRACTING,
                "extract:$displayName"
            )
            GZIPInputStream(tempFile.inputStream()).use { gzip ->
                extractTar(gzip, targetDir, stripPrefix)
            }
            Log.i(TAG, "Extracted $displayName to ${targetDir.absolutePath}")
        } finally {
            tempFile.delete()
        }
    }

    /**
     * Open an HTTP connection to [url], following redirects (GitHub releases
     * redirect from the release URL to an S3-backed CDN).
     */
    private fun openConnection(url: String): java.net.HttpURLConnection {
        var currentUrl = url
        var redirectCount = 0
        val maxRedirects = 5

        while (true) {
            val connection = java.net.URL(currentUrl)
                .openConnection() as java.net.HttpURLConnection
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.instanceFollowRedirects = false

            val responseCode = connection.responseCode
            if (responseCode in 300..399) {
                val location = connection.getHeaderField("Location")
                    ?: throw IOException("Redirect without Location header from $currentUrl")
                connection.disconnect()
                redirectCount++
                if (redirectCount > maxRedirects) {
                    throw IOException("Too many redirects (>$maxRedirects) starting from $url")
                }
                currentUrl = location
            } else if (responseCode == java.net.HttpURLConnection.HTTP_OK) {
                return connection
            } else {
                connection.disconnect()
                throw IOException("HTTP $responseCode from $currentUrl")
            }
        }
    }

    /**
     * Copy [input] to [output], emitting download progress events periodically.
     */
    private fun copyWithProgress(
        input: InputStream,
        output: java.io.OutputStream,
        totalBytes: Long,
        displayName: String
    ) {
        val buf = ByteArray(8192)
        var bytesDownloaded = 0L
        var lastReportedAt = 0L

        while (true) {
            val read = input.read(buf)
            if (read < 0) break
            output.write(buf, 0, read)
            bytesDownloaded += read

            if (bytesDownloaded - lastReportedAt >= PROGRESS_REPORT_INTERVAL_BYTES) {
                lastReportedAt = bytesDownloaded
                onDownloadEvent?.invoke(
                    mapOf(
                        "type" to "download_progress",
                        "payload" to mapOf(
                            "bytesDownloaded" to bytesDownloaded,
                            "totalBytes" to totalBytes,
                            "fileName" to displayName
                        )
                    )
                )
            }
        }
    }

    // ── Tar extraction ──────────────────────────────────────────────────

    /**
     * Extract a TAR archive from [inputStream] into [targetDir].
     * Entry paths that start with [stripPrefix]/ have that prefix removed.
     *
     * This is a minimal TAR parser supporting regular files ('0', NUL) and
     * directories ('5'). It handles the standard 512-byte header format
     * used by GNU tar / POSIX ustar.
     */
    private fun extractTar(inputStream: InputStream, targetDir: File, stripPrefix: String) {
        val header = ByteArray(512)
        while (true) {
            val bytesRead = readFully(inputStream, header)
            if (bytesRead < 512) break

            // Two consecutive zero-filled blocks mark end-of-archive
            if (header.all { it == 0.toByte() }) break

            // Parse header fields
            val rawName = parseString(header, 0, 100)
            val sizeStr = parseString(header, 124, 12)
            val size = if (sizeStr.isNotEmpty()) sizeStr.toLong(8) else 0L
            val typeFlag = header[156].toInt().toChar()

            // ustar prefix field (bytes 345-500)
            val ustarPrefix = parseString(header, 345, 155)
            val fullName = if (ustarPrefix.isNotEmpty()) "$ustarPrefix/$rawName" else rawName

            // Strip leading prefix directory
            val relativeName = if (fullName.startsWith("$stripPrefix/")) {
                fullName.removePrefix("$stripPrefix/")
            } else {
                fullName
            }

            if (relativeName.isEmpty() || relativeName == "/") {
                skipBytes(inputStream, roundUpTo512(size))
                continue
            }

            // Security: reject paths that escape the target directory
            val targetFile = File(targetDir, relativeName).canonicalFile
            if (!targetFile.path.startsWith(targetDir.canonicalPath)) {
                Log.w(TAG, "Skipping tar entry with path traversal: $relativeName")
                skipBytes(inputStream, roundUpTo512(size))
                continue
            }

            when (typeFlag) {
                '5', 'D' -> targetFile.mkdirs()
                '0', '\u0000' -> {
                    targetFile.parentFile?.mkdirs()
                    targetFile.outputStream().use { output ->
                        var remaining = size
                        val copyBuf = ByteArray(8192)
                        while (remaining > 0) {
                            val toRead = minOf(remaining.toInt(), copyBuf.size)
                            val read = inputStream.read(copyBuf, 0, toRead)
                            if (read <= 0) break
                            output.write(copyBuf, 0, read)
                            remaining -= read
                        }
                    }
                    // Skip padding to 512-byte boundary
                    val padding = roundUpTo512(size) - size
                    if (padding > 0) skipBytes(inputStream, padding)
                }
                else -> skipBytes(inputStream, roundUpTo512(size))
            }
        }
    }

    private fun parseString(buffer: ByteArray, offset: Int, length: Int): String =
        String(buffer, offset, length, Charsets.US_ASCII).trim('\u0000', ' ')

    /**
     * Read exactly [buffer].size bytes from [inputStream], returning the actual
     * number of bytes read. Returns less than the buffer size only at EOF.
     */
    private fun readFully(inputStream: InputStream, buffer: ByteArray): Int {
        var offset = 0
        while (offset < buffer.size) {
            val read = inputStream.read(buffer, offset, buffer.size - offset)
            if (read < 0) break
            offset += read
        }
        return offset
    }

    private fun roundUpTo512(size: Long): Long = ((size + 511) / 512) * 512

    private fun skipBytes(inputStream: InputStream, count: Long) {
        var remaining = count
        val buf = ByteArray(8192)
        while (remaining > 0) {
            val toSkip = minOf(remaining.toInt(), buf.size)
            val read = inputStream.read(buf, 0, toSkip)
            if (read <= 0) break
            remaining -= read
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private fun emitDownloadEvent(type: String, fileName: String) {
        onDownloadEvent?.invoke(
            mapOf("type" to type, "payload" to mapOf("fileName" to fileName))
        )
    }

    private fun updateEngineState(next: TtsEngineState, reason: String) {
        val current = state
        if (current == next) return
        state = next
        Log.i(TAG, "Engine state changed: $current -> $next ($reason)")
    }

    /**
     * Estimate WAV playback duration from the WAV header.
     * Returns null if the header cannot be parsed.
     *
     * WAV format: bytes 24-27 = sample rate (little-endian uint32),
     *             bytes 28-31 = byte rate (little-endian uint32).
     * Duration = (total data size) / byte rate * 1000 ms.
     */
    private fun estimateDurationFromWav(wavBytes: ByteArray): Long? {
        if (wavBytes.size < 44) return null

        val byteRate = ((wavBytes[28].toInt() and 0xFF)) or
                ((wavBytes[29].toInt() and 0xFF) shl 8) or
                ((wavBytes[30].toInt() and 0xFF) shl 16) or
                ((wavBytes[31].toInt() and 0xFF) shl 24)

        if (byteRate <= 0) return null

        // Data size is total minus the 44-byte standard header
        val dataSize = wavBytes.size - 44
        return (dataSize.toLong() * 1000L) / byteRate.toLong()
    }
}
