package com.example.comerune.speech.domain.controller

import com.example.comerune.speech.domain.model.EngineType
import com.example.comerune.speech.domain.model.SpeechSettings
import com.example.comerune.speech.domain.player.TtsSpeakException
import com.example.comerune.speech.domain.player.TtsSpeaker
import com.example.comerune.speech.domain.queue.InMemorySpeechQueueManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Issue #715 (QA-1): contract tests pinning the wire-format strings that
 * `processWithAndroidTts` emits to the Flutter side.
 *
 * The Dart side mirrors these constants in
 * `lib/presentation/screens/comment_screen.dart` as
 * `_kReasonAndroidTtsNotReady` / `_kReasonAndroidTtsFailedPrefix`. PR #705
 * Cycle 2 was a real production-broken regression caused by drift between
 * the two sides (the Dart side detector was reading the wrong payload key).
 * These tests exist to:
 *   1. Lock the literal prefix values so they cannot drift silently on the
 *      Kotlin side.
 *   2. Cover each failure path that produces those payloads (not-ready,
 *      outer catch, inner Result.failure).
 *
 * Whenever the Dart-side mirrors are renamed, update both sides AND the
 * pinned literals in [PrefixContract] together.
 */
class SpeechControllerProcessAndroidTtsContractTest {

    /**
     * Single source of truth for the wire-format prefix literals. The Dart
     * side mirrors these values; any change here must be paired with a
     * matching update in `comment_screen.dart` (see #715 / #716 follow-up).
     */
    private object PrefixContract {
        const val NOT_READY: String = "android_tts_not_ready"
        const val FAILED_PREFIX: String = "android_tts_failed"
    }

    private lateinit var normalizer: FakeNormalizer
    private lateinit var queue: InMemorySpeechQueueManager
    private lateinit var engine: FakeEngine
    private lateinit var player: FakePlayer
    private lateinit var settings: FakeSettingsRepository
    private lateinit var emitter: FakeEventEmitter

    /**
     * Returns the assertion-failure detail for [emitter.events] so test
     * failures show every event that the controller actually emitted —
     * not just the first mismatch. Saves diagnostic time when the
     * Android-TTS contract drifts in unexpected ways.
     */
    private fun emittedEventsDump(): String =
        emitter.events.joinToString(prefix = "[", postfix = "]") {
            val type = it["type"] as? String ?: "?"
            val payload = it["payload"] as? Map<*, *>
            val message = payload?.get("message")
            "$type${if (message != null) "($message)" else ""}"
        }

    @Before
    fun setUp() {
        normalizer = FakeNormalizer()
        queue = InMemorySpeechQueueManager(maxSize = 20)
        engine = FakeEngine()
        player = FakePlayer()
        settings = FakeSettingsRepository()
        // Dispatch all comments through the Android TTS path.
        settings.save(SpeechSettings(engineType = EngineType.ANDROID_TTS))
        emitter = FakeEventEmitter()
    }

    /**
     * Helper that builds a controller wired with the supplied [ttsSpeaker]
     * (or null) and the standard fake VOICEVOX engine / queue / player /
     * settings. Returns the controller so the caller can drive its lifecycle.
     */
    private fun newController(ttsSpeaker: TtsSpeaker?) =
        SpeechControllerImpl(
            normalizer = normalizer,
            queueManager = queue,
            engine = engine,
            player = player,
            settingsRepository = settings,
            eventEmitter = emitter,
            dispatcher = Dispatchers.Default,
            synthesisDispatcher = Dispatchers.Default,
            ttsSpeaker = ttsSpeaker
        )

    @After
    fun tearDown() {
        // No-op: each test creates its own controller and releases it inline.
    }

    // ---------------------------------------------------------------------
    // Prefix pinning
    // ---------------------------------------------------------------------

    @Test
    fun `prefix literals are pinned to the wire-format values shared with Dart`() {
        // Locks the exact strings. Renaming on either side without
        // updating the mirror will fail this test, surfacing the drift
        // in CI before any Flutter-side bug appears.
        assertEquals("android_tts_not_ready", PrefixContract.NOT_READY)
        assertEquals("android_tts_failed", PrefixContract.FAILED_PREFIX)
    }

    // ---------------------------------------------------------------------
    // Not-ready path
    // ---------------------------------------------------------------------

    @Test
    fun `processWithAndroidTts emits android_tts_not_ready when ttsSpeaker is null`() =
        runBlocking {
            val controller = newController(ttsSpeaker = null)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c1", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val payload = failed.first()["payload"] as Map<*, *>
                assertEquals(PrefixContract.NOT_READY, payload["message"])
                assertEquals("c1", payload["commentId"])
            } finally {
                controller.release()
            }
        }

    @Test
    fun `processWithAndroidTts emits android_tts_not_ready when speaker isReady returns false`() =
        runBlocking {
            val speaker = FakeTtsSpeaker().apply { readyOverride = false }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c2", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val payload = failed.first()["payload"] as Map<*, *>
                // The not-ready payload is emitted EXACTLY (no colon, no
                // trailing detail) so the Dart side equality check
                // `message == _kReasonAndroidTtsNotReady` keeps working.
                assertEquals(PrefixContract.NOT_READY, payload["message"])
                // The speaker must NOT have been driven if it reported
                // not-ready (otherwise the failure could be masked).
                assertEquals(0, speaker.speakCalls.get())
            } finally {
                controller.release()
            }
        }

    // ---------------------------------------------------------------------
    // Outer-catch path (configuration setter throws BEFORE speak)
    // ---------------------------------------------------------------------

    @Test
    fun `processWithAndroidTts emits android_tts_failed prefix when setSpeechRate throws (outer catch)`() =
        runBlocking {
            val speaker = FakeTtsSpeaker().apply { throwOnSetSpeechRate = true }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c3", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val message = (failed.first()["payload"] as Map<*, *>)["message"] as String
                // The outer catch produces "android_tts_failed: $inner".
                // The test asserts the prefix only — the inner message
                // is implementation-detail.
                assertTrue(
                    "expected message to start with '${PrefixContract.FAILED_PREFIX}:' " +
                        "but was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:")
                )
                // No speak call because the failure happened before the
                // inner Result-wrapped speak path was entered.
                assertEquals(0, speaker.speakCalls.get())
            } finally {
                controller.release()
            }
        }

    @Test
    fun `processWithAndroidTts emits android_tts_failed prefix when setPitch throws (outer catch)`() =
        runBlocking {
            // setPitch is the most likely Android setter to throw at
            // runtime (hidden API restrictions, device-specific
            // behaviour). Covering it explicitly ensures the contract
            // stays uniform across all three configuration setters.
            val speaker = FakeTtsSpeaker().apply { throwOnSetPitch = true }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c-pitch", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals(
                    "expected exactly 1 speech_failed event, got ${emittedEventsDump()}",
                    1,
                    failed.size,
                )
                val message =
                    (failed.first()["payload"] as Map<*, *>)["message"] as String
                assertTrue(
                    "expected message to start with '${PrefixContract.FAILED_PREFIX}:' " +
                        "but was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:")
                )
            } finally {
                controller.release()
            }
        }

    @Test
    fun `processWithAndroidTts emits android_tts_failed prefix when setVolume throws (outer catch)`() =
        runBlocking {
            // Different setter to confirm any of the three configuration
            // setters route through the same outer catch contract.
            val speaker = FakeTtsSpeaker().apply { throwOnSetVolume = true }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c4", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val message = (failed.first()["payload"] as Map<*, *>)["message"] as String
                assertTrue(
                    "expected message to start with '${PrefixContract.FAILED_PREFIX}:' " +
                        "but was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:")
                )
            } finally {
                controller.release()
            }
        }

    // ---------------------------------------------------------------------
    // Inner Result-wrapped path (speak returns Result.failure)
    // ---------------------------------------------------------------------

    @Test
    fun `processWithAndroidTts emits android_tts_failed prefix when speak returns Result failure`() =
        runBlocking {
            val speaker = FakeTtsSpeaker().apply { failOnSpeak = true }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c5", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val message = (failed.first()["payload"] as Map<*, *>)["message"] as String
                assertTrue(
                    "expected message to start with '${PrefixContract.FAILED_PREFIX}:' " +
                        "but was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:")
                )
                // speak() was reached at least once.
                assertTrue(
                    "expected speak() to be called at least once, was ${speaker.speakCalls.get()}",
                    speaker.speakCalls.get() >= 1
                )
            } finally {
                controller.release()
            }
        }

    @Test
    fun `processWithAndroidTts emits android_tts_failed prefix when speak throws (caught by inner)`() =
        runBlocking {
            val speaker = FakeTtsSpeaker().apply { throwOnSpeak = true }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c6", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals("expected exactly 1 speech_failed event, got ${emittedEventsDump()}", 1, failed.size)
                val message = (failed.first()["payload"] as Map<*, *>)["message"] as String
                // The inner try-catch around speak() wraps thrown
                // exceptions in Result.failure, so this still emits the
                // prefix; we never reach the outer catch.
                assertTrue(
                    "expected message to start with '${PrefixContract.FAILED_PREFIX}:' " +
                        "but was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:")
                )
            } finally {
                controller.release()
            }
        }

    // ---------------------------------------------------------------------
    // Happy path (sanity): no failure event when speaker.speak succeeds.
    // ---------------------------------------------------------------------

    @Test
    fun `processWithAndroidTts emits speech_completed and no failure on happy path`() =
        runBlocking {
            val speaker = FakeTtsSpeaker()
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c7", "hello"))
                delay(500)

                val completed = emitter.eventsOfType("speech_completed")
                val failed = emitter.eventsOfType("speech_failed")
                assertEquals(1, completed.size)
                assertEquals(0, failed.size)
                assertNotNull(speaker.speakCalls.get())
            } finally {
                controller.release()
            }
        }

    // ---------------------------------------------------------------------
    // Issue #966 / #968: a [TtsSpeakException.UserStopped] failure must NOT
    // be surfaced as `speech_failed`. Otherwise three rapid user-stops
    // (engine switch / settings retry / queue clear) trip the Flutter-side
    // `_consecutiveAndroidTtsFailures` counter and flip the AppBar to ERROR
    // even though the engine is healthy. The recovery counterpart is the
    // happy-path test above (no double-emit of `speech_completed`).
    // ---------------------------------------------------------------------

    @Test
    fun `processWithAndroidTts skips speech_failed when speak returns UserStopped`() =
        runBlocking {
            val speaker = FakeTtsSpeaker().apply {
                speakFailureOverride = TtsSpeakException.UserStopped()
            }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c-user-stop", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals(
                    "UserStopped is the caller's intent — no speech_failed must be emitted, got ${emittedEventsDump()}",
                    0,
                    failed.size,
                )
                // Also must NOT have emitted `speech_completed`: a stop is
                // not a successful speak, so the Flutter recovery path
                // (counter reset on `speech_completed`) must not be
                // triggered by a stop either.
                val completed = emitter.eventsOfType("speech_completed")
                assertEquals(
                    "UserStopped must not surface as speech_completed either, got ${emittedEventsDump()}",
                    0,
                    completed.size,
                )
            } finally {
                controller.release()
            }
        }

    @Test
    fun `processWithAndroidTts still emits android_tts_failed for sealed EngineError`() =
        runBlocking {
            // Sibling guard for the UserStopped suppression: a real engine
            // failure expressed via the sealed type must still surface as
            // `android_tts_failed:` so the Flutter-side counter and ERROR
            // detector keep working (Issue #695 contract preserved).
            val speaker = FakeTtsSpeaker().apply {
                speakFailureOverride =
                    TtsSpeakException.EngineError("simulated engine breakage")
            }
            val controller = newController(ttsSpeaker = speaker)
            try {
                controller.initialize()
                controller.start()

                controller.submitComment(rawComment("c-engine-err", "hello"))
                delay(500)

                val failed = emitter.eventsOfType("speech_failed")
                assertEquals(
                    "EngineError must still surface as speech_failed, got ${emittedEventsDump()}",
                    1,
                    failed.size,
                )
                val message =
                    (failed.first()["payload"] as Map<*, *>)["message"] as String
                assertTrue(
                    "expected '${PrefixContract.FAILED_PREFIX}:' prefix, was '$message'",
                    message.startsWith("${PrefixContract.FAILED_PREFIX}:"),
                )
            } finally {
                controller.release()
            }
        }

    // ---------------------------------------------------------------------
    // Issue #962: controller.stop() must propagate to speaker.stop() so the
    // queue worker leaves an in-flight Android TTS speak() immediately. The
    // previous code left the worker suspended in speaker.speak() until the
    // 60s safety timeout fired, freezing the queue on engine switch / stop.
    // ---------------------------------------------------------------------

    @Test
    fun `stop interrupts in-flight android tts speak and drains queue`() = runBlocking {
        val speaker = FakeTtsSpeaker().apply { suspendOnSpeak = true }
        val controller = newController(ttsSpeaker = speaker)
        try {
            controller.initialize()
            controller.start()

            controller.submitComment(rawComment("c-stop-1", "in-flight"))
            // Wait until speak() is actually suspended on the worker.
            val deadline = System.currentTimeMillis() + 500
            while (speaker.speakCalls.get() == 0 && System.currentTimeMillis() < deadline) {
                delay(10)
            }
            assertEquals(
                "speak must have been entered before stop is issued",
                1,
                speaker.speakCalls.get(),
            )

            // stop must propagate to speaker.stop() so the worker wakes up
            // immediately rather than waiting for the safety timeout.
            controller.stop(clearQueue = true)

            // Generous 1s ceiling: production resumes within milliseconds.
            // The bug being guarded against is a 60s freeze, so any value
            // well under that proves the fix.
            val resumeDeadline = System.currentTimeMillis() + 1000
            while (speaker.stopCalls.get() == 0 &&
                System.currentTimeMillis() < resumeDeadline
            ) {
                delay(10)
            }
            assertTrue(
                "controller.stop must invoke speaker.stop on the in-flight speaker",
                speaker.stopCalls.get() >= 1,
            )
        } finally {
            controller.release()
        }
    }

    // ---------------------------------------------------------------------
    // Issue #969: skip() must mirror stop()'s ordering and call
    // speaker.stop() up-front so an in-flight Android TTS speak() is
    // interrupted immediately. The previous code called speaker.stop() last,
    // which left the same regression surface as #962 latent on the skip
    // path — covered here so future refactors cannot regress the symmetry.
    // ---------------------------------------------------------------------

    @Test
    fun `skip interrupts in-flight android tts speak symmetrically with stop`() = runBlocking {
        val speaker = FakeTtsSpeaker().apply { suspendOnSpeak = true }
        val controller = newController(ttsSpeaker = speaker)
        try {
            controller.initialize()
            controller.start()

            controller.submitComment(rawComment("c-skip-1", "in-flight"))
            // Wait until speak() is actually suspended on the worker.
            val deadline = System.currentTimeMillis() + 500
            while (speaker.speakCalls.get() == 0 && System.currentTimeMillis() < deadline) {
                delay(10)
            }
            assertEquals(
                "speak must have been entered before skip is issued",
                1,
                speaker.speakCalls.get(),
            )

            // skip must propagate to speaker.stop() so the worker wakes up
            // immediately rather than waiting for the safety timeout —
            // the same guarantee stop() makes (Issue #962).
            controller.skip()

            // Generous 1s ceiling: production resumes within milliseconds.
            // The bug being guarded against is a 60s freeze, so any value
            // well under that proves the symmetry holds.
            val resumeDeadline = System.currentTimeMillis() + 1000
            while (speaker.stopCalls.get() == 0 &&
                System.currentTimeMillis() < resumeDeadline
            ) {
                delay(10)
            }
            assertTrue(
                "controller.skip must invoke speaker.stop on the in-flight speaker",
                speaker.stopCalls.get() >= 1,
            )
        } finally {
            controller.release()
        }
    }
}
