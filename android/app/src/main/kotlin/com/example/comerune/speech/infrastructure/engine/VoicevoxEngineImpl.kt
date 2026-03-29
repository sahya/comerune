package com.example.comerune.speech.infrastructure.engine

import android.content.Context
import android.util.Log
import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.VoicevoxConfig
import com.example.comerune.speech.domain.model.WavSynthesisResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException

/**
 * Real implementation of [VoicevoxEngine] backed by VOICEVOX Core 0.16.2 via JNI.
 *
 * On [initialize], this class extracts OpenJTalk dictionary and VVM model files
 * from Android assets to the app's internal storage (one-time operation), then
 * initializes the native synthesizer.
 *
 * @param context Android application context used for asset access and file storage.
 *                Must be an application context to avoid activity lifecycle leaks.
 */
class VoicevoxEngineImpl(private val context: Context) : VoicevoxEngine {

    companion object {
        private const val TAG = "VoicevoxEngineImpl"
        private const val VOICEVOX_DIR = "voicevox"
        private const val OPEN_JTALK_DICT_ASSET_DIR = "open_jtalk_dic_utf_8-1.11"
        private const val VVM_ASSET_DIR = "voicevox_models"
        /** Increment this when bundled assets change to force re-extraction. */
        private const val ASSET_VERSION = "1"
        private const val VERSION_FILE = ".asset_version"
    }

    @Volatile
    private var state: TtsEngineState = TtsEngineState.UNINITIALIZED

    /** Lock for state transitions in non-suspend functions (e.g. release). */
    private val stateLock = Any()

    private val mutex = Mutex()

    override suspend fun initialize(config: VoicevoxConfig): Result<Unit> =
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

            state = TtsEngineState.INITIALIZING

            try {
                withContext(Dispatchers.IO) {
                    val baseDir = File(context.filesDir, VOICEVOX_DIR)
                    val dictDir = File(baseDir, OPEN_JTALK_DICT_ASSET_DIR)
                    val modelDir = File(baseDir, VVM_ASSET_DIR)

                    extractAssetsIfNeeded(OPEN_JTALK_DICT_ASSET_DIR, dictDir)
                    extractAssetsIfNeeded(VVM_ASSET_DIR, modelDir)

                    val initialized = NativeVoicevoxBridge.nativeInitialize(
                        dictDir.absolutePath
                    )
                    if (!initialized) {
                        throw RuntimeException(
                            "NativeVoicevoxBridge.nativeInitialize failed"
                        )
                    }

                    val vvmFiles = modelDir.listFiles { file ->
                        file.extension == "vvm"
                    }
                    if (vvmFiles.isNullOrEmpty()) {
                        Log.w(TAG, "No .vvm files found in ${modelDir.absolutePath}")
                    } else {
                        for (vvm in vvmFiles) {
                            val loaded = NativeVoicevoxBridge.nativeLoadModel(
                                vvm.absolutePath
                            )
                            if (!loaded) {
                                throw RuntimeException(
                                    "Failed to load voice model: ${vvm.name}"
                                )
                            }
                            Log.i(TAG, "Loaded voice model: ${vvm.name}")
                        }
                    }
                }

                state = TtsEngineState.READY
                Log.i(TAG, "VOICEVOX engine initialized successfully")
                Result.success(Unit)
            } catch (e: Exception) {
                state = TtsEngineState.ERROR
                Log.e(TAG, "Initialization failed", e)
                Result.failure(e)
            }
        }

    override suspend fun synthesize(request: SpeechRequest): Result<WavSynthesisResult> =
        mutex.withLock {
            if (state != TtsEngineState.READY) {
                return@withLock Result.failure(
                    IllegalStateException(
                        "Engine is not ready. Current state: $state"
                    )
                )
            }

            state = TtsEngineState.SYNTHESIZING

            try {
                val wavBytes = withContext(Dispatchers.IO) {
                    NativeVoicevoxBridge.nativeTts(
                        text = request.text,
                        speakerId = request.speakerId,
                        speedScale = request.speedScale,
                        pitchScale = request.pitchScale,
                        intonationScale = request.intonationScale,
                        volumeScale = request.volumeScale,
                        prePhonemeLength = request.prePhonemeLength,
                        postPhonemeLength = request.postPhonemeLength
                    )
                }

                state = TtsEngineState.READY

                if (wavBytes == null) {
                    // Only restore READY if release() hasn't been called
                    if (state == TtsEngineState.SYNTHESIZING) {
                        state = TtsEngineState.READY
                    }
                    Result.failure(
                        RuntimeException("TTS synthesis returned null (text length=${request.text.length})")
                    )
                } else {
                    // Only restore READY if release() hasn't been called
                    if (state == TtsEngineState.SYNTHESIZING) {
                        state = TtsEngineState.READY
                    }
                    Result.success(
                        WavSynthesisResult(
                            wavBytes = wavBytes,
                            text = request.text,
                            durationEstimateMs = estimateDurationFromWav(wavBytes)
                        )
                    )
                }
            } catch (e: Exception) {
                // Only restore READY if release() hasn't been called concurrently.
                // If state is UNINITIALIZED, release() ran during synthesis — don't overwrite.
                if (state == TtsEngineState.SYNTHESIZING) {
                    state = TtsEngineState.READY
                }
                Log.e(TAG, "Synthesis failed", e)
                Result.failure(e)
            }
        }

    override fun isReady(): Boolean = state == TtsEngineState.READY

    override fun currentState(): TtsEngineState = state

    override fun release() {
        // Use the same Mutex strategy as synthesize() to prevent state races.
        // Since release() is non-suspend, we use a @Volatile flag + native-level
        // g_mutex for thread safety instead of the coroutine Mutex.
        val alreadyReleased = synchronized(stateLock) {
            if (state == TtsEngineState.UNINITIALIZED) {
                true
            } else {
                state = TtsEngineState.UNINITIALIZED
                false
            }
        }
        if (alreadyReleased) {
            Log.i(TAG, "VOICEVOX engine already released, skipping")
            return
        }
        NativeVoicevoxBridge.nativeRelease()
        Log.i(TAG, "VOICEVOX engine released")
    }

    /**
     * Extract assets from a directory in the APK to the target directory on disk.
     * Skips extraction if the target directory already exists, contains files,
     * and its version marker matches [ASSET_VERSION]. When the bundled assets
     * are updated, increment [ASSET_VERSION] to trigger re-extraction.
     */
    private fun extractAssetsIfNeeded(assetDir: String, targetDir: File) {
        val versionFile = File(targetDir, VERSION_FILE)
        val versionMatches = versionFile.exists() &&
            versionFile.readText().trim() == ASSET_VERSION

        if (targetDir.exists() && targetDir.listFiles()?.isNotEmpty() == true && versionMatches) {
            Log.i(TAG, "Assets already extracted to ${targetDir.absolutePath} (version $ASSET_VERSION)")
            return
        }

        // Version mismatch or first extraction — clear stale files
        if (targetDir.exists()) {
            targetDir.deleteRecursively()
            Log.i(TAG, "Cleared stale assets at ${targetDir.absolutePath}")
        }

        if (!targetDir.mkdirs() && !targetDir.exists()) {
            throw IOException("Failed to create directory: ${targetDir.absolutePath}")
        }

        val assetManager = context.assets
        val files = assetManager.list(assetDir)
        if (files.isNullOrEmpty()) {
            Log.w(TAG, "No assets found in '$assetDir'")
            return
        }

        for (fileName in files) {
            val assetPath = "$assetDir/$fileName"
            val targetFile = File(targetDir, fileName)

            // Check if this is a subdirectory
            val subFiles = assetManager.list(assetPath)
            if (subFiles != null && subFiles.isNotEmpty()) {
                extractAssetsIfNeeded(assetPath, targetFile)
            } else {
                assetManager.open(assetPath).use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }
        }

        // Write version marker so subsequent launches can skip re-extraction
        File(targetDir, VERSION_FILE).writeText(ASSET_VERSION)
        Log.i(TAG, "Extracted assets from '$assetDir' to ${targetDir.absolutePath} (version $ASSET_VERSION)")
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
