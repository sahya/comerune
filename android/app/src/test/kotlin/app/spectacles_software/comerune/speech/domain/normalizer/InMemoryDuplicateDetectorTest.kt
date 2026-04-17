package app.spectacles_software.comerune.speech.domain.normalizer

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class InMemoryDuplicateDetectorTest {

    private var currentTime = 0L
    private lateinit var detector: InMemoryDuplicateDetector

    @Before
    fun setUp() {
        currentTime = 10000L
        detector = InMemoryDuplicateDetector(
            duplicateWindowMs = 5000L,
            maxEntries = 50,
            timeProvider = { currentTime }
        )
    }

    // --- AC1: Same text within 5s is duplicate ---

    @Test
    fun `same text within window is duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 3000L
        assertTrue(detector.isDuplicate("hello", "user2", currentTime))
    }

    @Test
    fun `same text at exact window boundary is not duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 5000L
        assertFalse(detector.isDuplicate("hello", "user2", currentTime))
    }

    // --- AC2: After 5s, same text allowed ---

    @Test
    fun `same text after window passes is not duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 5001L
        assertFalse(detector.isDuplicate("hello", "user2", currentTime))
    }

    // --- AC3: Same userId different text within window is NOT suppressed ---
    // The duplicate detector only suppresses identical text, not same-user different text.

    @Test
    fun `same userId different text within window is not duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 1000L
        assertFalse(detector.isDuplicate("world", "user1", currentTime))
    }

    @Test
    fun `same userId same text within window is duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 1000L
        assertTrue(detector.isDuplicate("hello", "user1", currentTime))
    }

    @Test
    fun `null userId rapid posts with different text are not duplicate`() {
        detector.record("hello", null, currentTime)

        currentTime += 1000L
        assertFalse(detector.isDuplicate("world", null, currentTime))
    }

    // --- AC4: Different users/texts pass through ---

    @Test
    fun `different text different user is not duplicate`() {
        detector.record("hello", "user1", currentTime)

        currentTime += 1000L
        assertFalse(detector.isDuplicate("world", "user2", currentTime))
    }

    // --- AC5: duplicateWindowMs respected ---

    @Test
    fun `custom window is respected`() {
        val shortDetector = InMemoryDuplicateDetector(
            duplicateWindowMs = 1000L,
            timeProvider = { currentTime }
        )
        shortDetector.record("hello", "user1", currentTime)

        currentTime += 999L
        assertTrue(shortDetector.isDuplicate("hello", "user2", currentTime))

        currentTime += 1L
        assertFalse(shortDetector.isDuplicate("hello", "user2", currentTime))
    }

    // --- AC6: History bounded ---

    @Test
    fun `history does not exceed max entries`() {
        for (i in 1..60) {
            detector.record("text$i", "user$i", currentTime)
        }
        // All within window, so first 10 should have been evicted by max entries limit
        // The oldest entries were removed, so text1 should no longer be detected
        assertFalse(detector.isDuplicate("text1", "userX", currentTime))
        // Recent entry should still be detected
        assertTrue(detector.isDuplicate("text60", "userX", currentTime))
    }

    // --- Edge cases ---

    @Test
    fun `clear removes all history`() {
        detector.record("hello", "user1", currentTime)
        detector.clear()

        assertFalse(detector.isDuplicate("hello", "user1", currentTime))
    }

    @Test
    fun `empty text is treated like any other text`() {
        detector.record("", "user1", currentTime)

        currentTime += 1000L
        assertTrue(detector.isDuplicate("", "user2", currentTime))
    }

    @Test
    fun `zero window means nothing is duplicate`() {
        val zeroDetector = InMemoryDuplicateDetector(
            duplicateWindowMs = 0L,
            timeProvider = { currentTime }
        )
        zeroDetector.record("hello", "user1", currentTime)
        assertFalse(zeroDetector.isDuplicate("hello", "user1", currentTime))
    }
}
