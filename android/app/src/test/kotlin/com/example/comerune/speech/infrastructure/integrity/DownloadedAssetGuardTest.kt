package com.example.comerune.speech.infrastructure.integrity

import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.io.IOException
import java.nio.file.Files

class DownloadedAssetGuardTest {

    // SHA-256("abc") from FIPS 180-2 Appendix B.1.
    private val abcSha256 =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private lateinit var tempDir: File

    @Before
    fun setUp() {
        tempDir = Files.createTempDirectory("asset_guard_test").toFile()
    }

    @After
    fun tearDown() {
        tempDir.deleteRecursively()
    }

    private fun fileWith(content: String): File =
        File(tempDir, "asset.bin").apply { writeText(content, Charsets.US_ASCII) }

    @Test
    fun `verifySha256 accepts a matching digest`() {
        DownloadedAssetGuard.verifySha256(fileWith("abc"), abcSha256)
    }

    @Test
    fun `verifySha256 accepts an upper-case expected digest`() {
        DownloadedAssetGuard.verifySha256(fileWith("abc"), abcSha256.uppercase())
    }

    @Test
    fun `verifySha256 rejects a modified file`() {
        assertThrows(IOException::class.java) {
            DownloadedAssetGuard.verifySha256(fileWith("abd"), abcSha256)
        }
    }

    @Test
    fun `verifySha256 rejects a malformed expected digest`() {
        val file = fileWith("abc")
        listOf("", "abc", abcSha256.dropLast(1), abcSha256.dropLast(1) + "g").forEach { bad ->
            assertThrows(IOException::class.java) {
                DownloadedAssetGuard.verifySha256(file, bad)
            }
        }
    }

    @Test
    fun `verifySha256 throws IOException for a missing file`() {
        assertThrows(IOException::class.java) {
            DownloadedAssetGuard.verifySha256(File(tempDir, "missing.bin"), abcSha256)
        }
    }

    @Test
    fun `parseSha256Hex rejects non-ASCII digits`() {
        val fullWidthZero = '０'
        assertNull(DownloadedAssetGuard.parseSha256Hex("$fullWidthZero${abcSha256.drop(1)}"))
    }

    @Test
    fun `sha256Of computes the known digest`() {
        assertArrayEquals(
            DownloadedAssetGuard.parseSha256Hex(abcSha256),
            DownloadedAssetGuard.sha256Of(fileWith("abc"))
        )
    }

    @Test
    fun `isWithinDirectory accepts the directory and its children`() {
        val dir = File(tempDir, "dict")
        assertTrue(DownloadedAssetGuard.isWithinDirectory(dir, dir))
        assertTrue(DownloadedAssetGuard.isWithinDirectory(File(dir, "sys.dic"), dir))
        assertTrue(DownloadedAssetGuard.isWithinDirectory(File(dir, "a/b/c.def"), dir))
    }

    @Test
    fun `isWithinDirectory rejects parent traversal`() {
        val dir = File(tempDir, "dict")
        assertFalse(DownloadedAssetGuard.isWithinDirectory(File(dir, "../outside.txt"), dir))
    }

    @Test
    fun `isWithinDirectory rejects a sibling sharing the name prefix`() {
        val dir = File(tempDir, "dict")
        assertFalse(DownloadedAssetGuard.isWithinDirectory(File(dir, "../dict-other/x"), dir))
        assertFalse(DownloadedAssetGuard.isWithinDirectory(File(tempDir, "dictx"), dir))
    }
}
