package com.example.comerune.speech.domain.player

/**
 * Sealed hierarchy describing why a [TtsSpeaker.speak] call resolved
 * with [Result.failure]. Introduced for Issue #966 / #968: previously the
 * speaker returned a bare [RuntimeException] for every failure path, so
 * the caller could not distinguish a user-initiated stop from a real
 * engine breakage. The Flutter-side
 * `_consecutiveAndroidTtsFailures` counter then counted user-stops as
 * engine failures and flipped the AppBar to ERROR after three consecutive
 * stops in close succession (engine switch / settings retry scenario).
 *
 * Extends [RuntimeException] so existing `catch (e: Exception)` /
 * `catch (e: RuntimeException)` sites remain source-compatible — only
 * call sites that want type-level dispatch need to add a `when (e is …)`
 * branch.
 *
 * **Wire-format contract**: the [message] of [Timeout] / [EngineError] /
 * [FocusLost] is what the [com.example.comerune.speech.domain.controller.SpeechControllerImpl]
 * forwards (with the `android_tts_failed: ` prefix) to the Flutter side
 * via `speech_failed`. Changing these strings will surface in the
 * `SpeechControllerProcessAndroidTtsContractTest` Kotlin contract tests
 * and any downstream UI that surfaces the inner detail.
 *
 * [UserStopped] is deliberately omitted from the `speech_failed` wire
 * format (see [com.example.comerune.speech.domain.controller.SpeechControllerImpl.processWithAndroidTts])
 * because a stop is the caller's own command and is not an engine failure.
 */
internal sealed class TtsSpeakException(message: String) : RuntimeException(message) {
    /**
     * The in-flight speak was interrupted by [TtsSpeaker.stop] or by the
     * `invokeOnCancellation` path on the suspending continuation. This
     * is the user's intent (e.g. queue clear, engine switch, disable),
     * not an engine failure — callers MUST NOT count it toward
     * consecutive-failure thresholds and MUST NOT surface it as a
     * `speech_failed` runtime event.
     */
    class UserStopped : TtsSpeakException("TTS stopped by caller")

    /**
     * The speak call did not return within the speaker's safety timeout.
     * Treated as an engine failure because the caller has no way to
     * know whether the native engine is wedged or merely slow.
     */
    class Timeout(val timeoutMs: Long) :
        TtsSpeakException("TTS speak timed out after ${timeoutMs}ms")

    /**
     * The native engine reported an error (e.g. `speak()` returned a
     * non-SUCCESS status, the [android.speech.tts.UtteranceProgressListener]
     * called `onError`). [reason] preserves the underlying detail so the
     * existing `android_tts_failed: <reason>` Flutter-side detector keeps
     * working byte-for-byte.
     */
    class EngineError(val reason: String) :
        TtsSpeakException("TTS engine error: $reason")

    /**
     * Audio focus was lost mid-speak; the engine has been stopped.
     * Treated as an engine failure for counter purposes because the
     * cause is external to the caller's intent.
     */
    class FocusLost : TtsSpeakException("Audio focus lost during speak")
}
