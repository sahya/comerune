package com.example.comerune.speech.infrastructure.integrity

import java.io.File
import java.io.IOException
import java.security.MessageDigest

/**
 * Checks applied to assets fetched at runtime (voice models, dictionary
 * archives) before they are handed to the native engine.
 *
 * Downloaded files are only promoted or extracted after their SHA-256
 * matches the value pinned in the app, so a changed upstream file is
 * rejected instead of being loaded.
 */
object DownloadedAssetGuard {

    private const val SHA256_HEX_LENGTH = 64
    private const val BUFFER_SIZE = 8192

    /**
     * Verify that [file] has the SHA-256 digest [expectedSha256Hex]
     * (64 hex characters, case-insensitive).
     *
     * @throws IOException when the digest does not match, when the expected
     *   value is not a well-formed SHA-256 hex string, or when the file
     *   cannot be read. The message stays generic on purpose.
     */
    fun verifySha256(file: File, expectedSha256Hex: String) {
        val expected = parseSha256Hex(expectedSha256Hex)
            ?: throw IOException("Integrity check is not configured correctly")
        val actual = sha256Of(file)
        if (!MessageDigest.isEqual(actual, expected)) {
            throw IOException("Downloaded file failed integrity check")
        }
    }

    /**
     * Whether [candidate] resolves to [directory] itself or to a path inside
     * it. Both paths are canonicalized, and the prefix comparison includes
     * the path separator so that a sibling such as `dir-other/` is not
     * treated as being inside `dir/`.
     */
    fun isWithinDirectory(candidate: File, directory: File): Boolean {
        val base = directory.canonicalPath
        val path = candidate.canonicalPath
        return path == base || path.startsWith(base + File.separator)
    }

    internal fun sha256Of(file: File): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest()
    }

    internal fun parseSha256Hex(hex: String): ByteArray? {
        if (hex.length != SHA256_HEX_LENGTH) return null
        val out = ByteArray(SHA256_HEX_LENGTH / 2)
        for (i in out.indices) {
            val high = asciiHexValue(hex[i * 2])
            val low = asciiHexValue(hex[i * 2 + 1])
            if (high < 0 || low < 0) return null
            out[i] = ((high shl 4) or low).toByte()
        }
        return out
    }

    /** ASCII-only hex digit value; -1 for anything else (incl. full-width). */
    private fun asciiHexValue(c: Char): Int = when (c) {
        in '0'..'9' -> c - '0'
        in 'a'..'f' -> c - 'a' + 10
        in 'A'..'F' -> c - 'A' + 10
        else -> -1
    }
}
