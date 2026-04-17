package app.spectacles_software.comerune.speech.infrastructure.repository

import android.content.Context
import android.util.Log
import app.spectacles_software.comerune.speech.domain.model.ModelDownloadState
import app.spectacles_software.comerune.speech.domain.model.VoicevoxModelInfo
import app.spectacles_software.comerune.speech.domain.model.VoicevoxModelManifest
import app.spectacles_software.comerune.speech.domain.repository.VoicevoxModelRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * File-system backed implementation of [VoicevoxModelRepository].
 *
 * Models are stored under app-internal files and downloaded from GitHub releases.
 * (If a model is marked bundled in the manifest, it is copied from assets.)
 */
class VoicevoxModelRepositoryImpl(private val context: Context) : VoicevoxModelRepository {

    companion object {
        private const val TAG = "VoicevoxModelRepo"
        private const val VOICEVOX_DIR = "voicevox"
        private const val VVM_DIR_NAME = "voicevox_models"
        private const val CONNECT_TIMEOUT_MS = 30_000
        private const val READ_TIMEOUT_MS = 120_000
        private const val PROGRESS_REPORT_INTERVAL_BYTES = 1_048_576L // 1 MB
    }

    private val downloadStates = ConcurrentHashMap<String, ModelDownloadState>()
    private val cancelledDownloads: MutableSet<String> = ConcurrentHashMap.newKeySet()

    private val modelDir: File
        get() = File(File(context.filesDir, VOICEVOX_DIR), VVM_DIR_NAME)

    override fun getAvailableModels(): List<VoicevoxModelInfo> {
        return VoicevoxModelManifest.models.map { model ->
            val file = File(modelDir, model.vvmFileName)
            val trackedState = downloadStates[model.modelId]
            model.copy(
                downloadState = when {
                    file.exists() -> ModelDownloadState.DOWNLOADED
                    trackedState == ModelDownloadState.DOWNLOADING -> ModelDownloadState.DOWNLOADING
                    trackedState == ModelDownloadState.ERROR -> ModelDownloadState.ERROR
                    else -> ModelDownloadState.NOT_DOWNLOADED
                }
            )
        }
    }

    override suspend fun downloadModel(
        modelId: String,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?
    ): Result<Unit> = withContext(Dispatchers.IO) {
        val modelInfo = VoicevoxModelManifest.findByModelId(modelId)
            ?: return@withContext Result.failure(
                IllegalArgumentException("Unknown model ID: $modelId")
            )

        // Already downloaded
        val targetFile = File(modelDir, modelInfo.vvmFileName)
        if (targetFile.exists()) {
            Log.i(TAG, "Model ${modelInfo.vvmFileName} already exists, skipping download")
            return@withContext Result.success(Unit)
        }

        try {
            downloadStates[modelId] = ModelDownloadState.DOWNLOADING
            cancelledDownloads.remove(modelId)

            if (!modelDir.exists() && !modelDir.mkdirs()) {
                throw IOException("Failed to create model directory: ${modelDir.absolutePath}")
            }

            if (modelInfo.isBundled) {
                // Copy from assets
                copyBundledModel(modelInfo)
            } else {
                // Download from URL
                downloadFromUrl(modelInfo, onProgress) { modelId in cancelledDownloads }
            }

            downloadStates[modelId] = ModelDownloadState.DOWNLOADED
            Log.i(TAG, "Model ${modelInfo.vvmFileName} is now available")
            Result.success(Unit)
        } catch (e: Exception) {
            val wasCancelled = modelId in cancelledDownloads
            downloadStates[modelId] =
                if (wasCancelled) ModelDownloadState.NOT_DOWNLOADED
                else ModelDownloadState.ERROR
            if (wasCancelled) {
                Log.i(TAG, "Download cancelled for model ${modelInfo.vvmFileName}")
            } else {
                Log.e(TAG, "Failed to obtain model ${modelInfo.vvmFileName}", e)
            }
            Result.failure(e)
        }
    }

    override fun deleteModel(modelId: String): Result<Unit> {
        val modelInfo = VoicevoxModelManifest.findByModelId(modelId)
            ?: return Result.failure(
                IllegalArgumentException("Unknown model ID: $modelId")
            )

        if (modelInfo.isBundled) {
            return Result.failure(
                UnsupportedOperationException(
                    "Cannot delete bundled model: ${modelInfo.displayName}"
                )
            )
        }

        val file = File(modelDir, modelInfo.vvmFileName)
        return if (file.exists()) {
            if (file.delete()) {
                downloadStates[modelId] = ModelDownloadState.NOT_DOWNLOADED
                Log.i(TAG, "Deleted model ${modelInfo.vvmFileName}")
                Result.success(Unit)
            } else {
                Result.failure(IOException("Failed to delete ${file.absolutePath}"))
            }
        } else {
            downloadStates[modelId] = ModelDownloadState.NOT_DOWNLOADED
            Result.success(Unit)
        }
    }

    override fun isModelDownloaded(modelId: String): Boolean {
        val modelInfo = VoicevoxModelManifest.findByModelId(modelId) ?: return false
        return File(modelDir, modelInfo.vvmFileName).exists()
    }

    override fun getModelFile(modelId: String): File? {
        val modelInfo = VoicevoxModelManifest.findByModelId(modelId) ?: return null
        val file = File(modelDir, modelInfo.vvmFileName)
        return if (file.exists()) file else null
    }

    /**
     * Ensure the bundled model (copied from assets) is available on disk.
     * This should be called during initialization for bundled models.
     */
    override fun ensureBundledModel(modelInfo: VoicevoxModelInfo) {
        if (!modelInfo.isBundled) return

        val targetFile = File(modelDir, modelInfo.vvmFileName)
        if (targetFile.exists()) return

        if (!modelDir.exists() && !modelDir.mkdirs()) {
            throw IOException("Failed to create model directory: ${modelDir.absolutePath}")
        }

        copyBundledModel(modelInfo)
        downloadStates[modelInfo.modelId] = ModelDownloadState.DOWNLOADED
        Log.i(TAG, "Bundled model ${modelInfo.vvmFileName} copied from assets")
    }

    override fun cancelDownload(modelId: String) {
        cancelledDownloads.add(modelId)
        Log.i(TAG, "Cancel requested for model $modelId")
    }

    // ── Private helpers ────────────────────────────────────────────────

    private fun copyBundledModel(modelInfo: VoicevoxModelInfo) {
        val targetFile = File(modelDir, modelInfo.vvmFileName)
        val tempFile = File(modelDir, "${modelInfo.vvmFileName}.tmp")

        try {
            context.assets.open("voicevox_models/${modelInfo.vvmFileName}").use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            if (!tempFile.renameTo(targetFile)) {
                throw IOException(
                    "Failed to rename temp file to ${targetFile.absolutePath}"
                )
            }
            Log.i(TAG, "Copied bundled model ${modelInfo.vvmFileName} from assets")
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }
    }

    private fun downloadFromUrl(
        modelInfo: VoicevoxModelInfo,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?,
        isCancelled: () -> Boolean = { false }
    ) {
        val targetFile = File(modelDir, modelInfo.vvmFileName)
        val tempFile = File(modelDir, "${modelInfo.vvmFileName}.tmp")

        try {
            val connection = openConnection(modelInfo.downloadUrl)
            try {
                val totalBytes = connection.contentLengthLong
                connection.inputStream.use { input ->
                    tempFile.outputStream().use { output ->
                        copyWithProgress(input, output, totalBytes, onProgress, isCancelled)
                    }
                }
                Log.i(
                    TAG,
                    "Downloaded ${modelInfo.vvmFileName} (${tempFile.length()} bytes)"
                )
            } finally {
                connection.disconnect()
            }

            if (!tempFile.renameTo(targetFile)) {
                throw IOException(
                    "Failed to rename temp file to ${targetFile.absolutePath}"
                )
            }
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }
    }

    /**
     * Open an HTTP connection following redirects (GitHub releases
     * redirect to S3-backed CDN).
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
                    ?: throw IOException(
                        "Redirect without Location header from $currentUrl"
                    )
                connection.disconnect()
                redirectCount++
                if (redirectCount > maxRedirects) {
                    throw IOException(
                        "Too many redirects (>$maxRedirects) starting from $url"
                    )
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
     * Copy [input] to [output], invoking [onProgress] periodically.
     */
    private fun copyWithProgress(
        input: InputStream,
        output: OutputStream,
        totalBytes: Long,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?,
        isCancelled: () -> Boolean = { false }
    ) {
        val buf = ByteArray(8192)
        var bytesDownloaded = 0L
        var lastReportedAt = 0L

        while (true) {
            if (isCancelled()) {
                throw IOException("Download cancelled")
            }
            val read = input.read(buf)
            if (read < 0) break
            output.write(buf, 0, read)
            bytesDownloaded += read

            if (onProgress != null &&
                bytesDownloaded - lastReportedAt >= PROGRESS_REPORT_INTERVAL_BYTES
            ) {
                lastReportedAt = bytesDownloaded
                onProgress(bytesDownloaded, totalBytes)
            }
        }
    }
}
