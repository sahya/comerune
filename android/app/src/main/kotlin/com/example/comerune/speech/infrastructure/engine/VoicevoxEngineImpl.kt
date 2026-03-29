package com.example.comerune.speech.infrastructure.engine

import android.content.Context
import android.util.Log
import com.example.comerune.speech.domain.engine.VoicevoxEngine
import com.example.comerune.speech.domain.model.SpeechRequest
import com.example.comerune.speech.domain.model.TtsEngineState
import com.example.comerune.speech.domain.model.WavSynthesisResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.zip.GZIPInputStream

/**
 * Real implementation of [VoicevoxEngine] backed by VOICEVOX Core 0.16.2 via JNI.
 *
 * On [initialize], this class downloads OpenJTalk dictionary and VVM model files
 * from GitHub releases on first use (one-time operation), then initializes the
 * native synthesizer. Subsequent launches skip the download if assets are already
 * present and the version marker matches.
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
        /** Increment this when remote assets change to force re-download. */
        private const val ASSET_VERSION = "1"
        private const val VERSION_FILE = ".asset_version"

        private const val OPEN_JTALK_DICT_URL =
            "https://github.com/r9y9/open_jtalk/releases/download/v1.11.1/open_jtalk_dic_utf_8-1.11.tar.gz"
        private const val VVM_DOWNLOAD_URL =
            "https://github.com/VOICEVOX/voicevox_vvm/releases/download/0.16.2/0.vvm"

        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 120_000
        private const val PROGRESS_REPORT_INTERVAL_BYTES = 1_048_576L // 1 MB
    }

    @Volatile
    private var state: TtsEngineState = TtsEngineState.UNINITIALIZED

    /** Lock for state transitions in non-suspend functions (e.g. release). */
    private val stateLock = Any()

    private val mutex = Mutex()

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

            state = TtsEngineState.INITIALIZING

            try {
                withContext(Dispatchers.IO) {
                    val baseDir = File(context.filesDir, VOICEVOX_DIR)
                    val dictDir = File(baseDir, OPEN_JTALK_DICT_DIR_NAME)
                    val modelDir = File(baseDir, VVM_DIR_NAME)

                    ensureAssetsAvailable(baseDir, dictDir, modelDir)

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
                val message = if (e is IOException) {
                    "VOICEVOXモデルのダウンロードに失敗しました。ネットワーク接続を確認してください。"
                } else {
                    e.message ?: "Unknown initialization error"
                }
                Result.failure(RuntimeException(message, e))
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

    // ── Asset download ──────────────────────────────────────────────────

    /**
     * Ensure that the OpenJTalk dictionary and VVM model are present on disk.
     * Downloads them from GitHub releases if missing or if the version marker
     * does not match [ASSET_VERSION].
     */
    private fun ensureAssetsAvailable(baseDir: File, dictDir: File, modelDir: File) {
        val versionFile = File(baseDir, VERSION_FILE)
        val versionMatches = versionFile.exists() &&
            versionFile.readText().trim() == ASSET_VERSION

        if (versionMatches &&
            dictDir.exists() && (dictDir.listFiles()?.isNotEmpty() == true) &&
            modelDir.exists() && (modelDir.listFiles()?.any { it.extension == "vvm" } == true)
        ) {
            Log.i(TAG, "Assets already downloaded (version $ASSET_VERSION)")
            return
        }

        // Version mismatch or first download — clear stale files
        if (baseDir.exists()) {
            baseDir.deleteRecursively()
            Log.i(TAG, "Cleared stale assets at ${baseDir.absolutePath}")
        }

        if (!baseDir.mkdirs() && !baseDir.exists()) {
            throw IOException("Failed to create directory: ${baseDir.absolutePath}")
        }

        // Download OpenJTalk dictionary (tar.gz archive)
        emitDownloadEvent("download_started", OPEN_JTALK_DICT_DIR_NAME)
        downloadAndExtractTarGz(
            url = OPEN_JTALK_DICT_URL,
            targetDir = dictDir,
            stripPrefix = OPEN_JTALK_DICT_DIR_NAME,
            displayName = OPEN_JTALK_DICT_DIR_NAME
        )

        // Download VVM model
        emitDownloadEvent("download_started", "0.vvm")
        if (!modelDir.mkdirs() && !modelDir.exists()) {
            throw IOException("Failed to create directory: ${modelDir.absolutePath}")
        }
        downloadFile(
            url = VVM_DOWNLOAD_URL,
            targetFile = File(modelDir, "0.vvm"),
            displayName = "0.vvm"
        )

        // Write version marker so subsequent launches skip download
        versionFile.writeText(ASSET_VERSION)
        emitDownloadEvent("download_completed", "")
        Log.i(TAG, "All assets downloaded (version $ASSET_VERSION)")
    }

    /**
     * Download a single file from [url] to [targetFile], following HTTP redirects.
     */
    private fun downloadFile(url: String, targetFile: File, displayName: String) {
        targetFile.parentFile?.mkdirs()
        val connection = openConnection(url)
        try {
            val totalBytes = connection.contentLengthLong
            connection.inputStream.use { input ->
                targetFile.outputStream().use { output ->
                    copyWithProgress(input, output, totalBytes, displayName)
                }
            }
            Log.i(TAG, "Downloaded $displayName (${targetFile.length()} bytes)")
        } finally {
            connection.disconnect()
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
