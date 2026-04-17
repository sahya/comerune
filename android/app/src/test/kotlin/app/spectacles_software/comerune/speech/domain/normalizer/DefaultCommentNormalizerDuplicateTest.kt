package app.spectacles_software.comerune.speech.domain.normalizer

import app.spectacles_software.comerune.speech.domain.model.RawComment
import app.spectacles_software.comerune.speech.domain.model.SpeechSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class DefaultCommentNormalizerDuplicateTest {

    private var currentTime = 10000L
    private lateinit var detector: InMemoryDuplicateDetector
    private lateinit var normalizer: DefaultCommentNormalizer
    private lateinit var settings: SpeechSettings

    @Before
    fun setUp() {
        currentTime = 10000L
        detector = InMemoryDuplicateDetector(
            duplicateWindowMs = 5000L,
            timeProvider = { currentTime }
        )
        normalizer = DefaultCommentNormalizer(
            duplicateDetector = detector,
            timeProvider = { currentTime }
        )
        settings = SpeechSettings()
    }

    private fun raw(text: String, userId: String? = "user1") = RawComment(
        id = "test-id",
        text = text,
        userId = userId,
        postedAtEpochMs = 0L
    )

    @Test
    fun `duplicate text within window gets skipReason duplicate`() {
        val first = normalizer.normalize(raw("hello"), settings)
        assertNull(first.skipReason)

        val second = normalizer.normalize(raw("hello", userId = "user2"), settings)
        assertEquals("duplicate", second.skipReason)
    }

    @Test
    fun `same text after window passes is allowed`() {
        normalizer.normalize(raw("hello"), settings)

        currentTime += 5001L
        val second = normalizer.normalize(raw("hello", userId = "user2"), settings)
        assertNull(second.skipReason)
    }

    @Test
    fun `rapid fire same user gets skipReason duplicate`() {
        normalizer.normalize(raw("hello", userId = "user1"), settings)

        currentTime += 1000L
        val second = normalizer.normalize(raw("different text", userId = "user1"), settings)
        assertEquals("duplicate", second.skipReason)
    }

    @Test
    fun `different users different text passes through`() {
        normalizer.normalize(raw("hello", userId = "user1"), settings)

        currentTime += 1000L
        val second = normalizer.normalize(raw("world", userId = "user2"), settings)
        assertNull(second.skipReason)
    }

    @Test
    fun `already skipped comments are not recorded for dedup`() {
        // blank text is already skipped - should not be recorded
        normalizer.normalize(raw(""), settings)

        // Different user with different text should pass
        val result = normalizer.normalize(raw("hello", userId = "user2"), settings)
        assertNull(result.skipReason)
    }

    @Test
    fun `postedAtEpochMs does not affect duplicate detection`() {
        val farFuture = RawComment(
            id = "test-id",
            text = "hello",
            userId = "user1",
            postedAtEpochMs = 9_999_999_999_999L
        )
        val first = normalizer.normalize(farFuture, settings)
        assertNull(first.skipReason)

        // Same text from different user, still within window based on timeProvider, not postedAtEpochMs
        val second = normalizer.normalize(
            RawComment(
                id = "test-id-2",
                text = "hello",
                userId = "user2",
                postedAtEpochMs = 0L
            ),
            settings
        )
        assertEquals("duplicate", second.skipReason)
    }

    @Test
    fun `normalizer without detector does not check duplicates`() {
        val plainNormalizer = DefaultCommentNormalizer()

        plainNormalizer.normalize(raw("hello"), settings)
        val second = plainNormalizer.normalize(raw("hello"), settings)
        assertNull(second.skipReason)
    }
}
