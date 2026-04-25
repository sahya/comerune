/// Single source of truth for the wire-format strings that the native
/// (Kotlin) speech controller emits as the `message` field of
/// `speech_failed` events for the Android TTS engine.
///
/// PR #705 Cycle 2 was a real production-broken regression where the
/// native and Dart sides drifted on the payload key (`'reason'` vs
/// `'message'`) — the contract was only documented in inline comments
/// and survived all reviews until users started seeing the AppBar stay
/// happy through real failures. To prevent recurrence, the literal
/// values are pinned here and the Dart consumer goes through this
/// type instead of duplicating string constants.
///
/// Mirror on the Kotlin side:
/// `android/app/src/main/kotlin/.../SpeechControllerImpl.kt` (the
/// emitting strings) and the contract test
/// `android/app/src/test/kotlin/.../SpeechControllerProcessAndroidTtsContractTest.kt`
/// (`PrefixContract.NOT_READY` / `PrefixContract.FAILED_PREFIX`). When
/// either side changes the literal here, update **all three** files.
///
/// Integration coverage: the routing in `comment_screen.dart` (the
/// `_consecutiveAndroidTtsFailures` counter and ERROR threshold) is
/// validated by the existing `comment_screen_speech_test.dart` suite —
/// the same fixtures (`android_tts_not_ready`, `android_tts_failed: ...`)
/// run through this parser and exercise the unchanged threshold logic,
/// so behavioural regressions surface in that suite without a separate
/// SSOT-integration test.
///
/// Behaviour parity with the pre-SSOT predicate
/// (`comment_screen.dart` constants `_kReasonAndroidTtsNotReady` /
/// `_kReasonAndroidTtsFailedPrefix`) is preserved intentionally:
/// * `'android_tts_not_ready'` (exact equality) → [AndroidTtsNotReady].
/// * any string `startsWith('android_tts_failed')` → [AndroidTtsFailed].
///   The `:` separator is conventional in the native emitter
///   (`"android_tts_failed: $inner"`), but the parser MUST also accept
///   the bare prefix so that an emitter quirk does not silently bypass
///   the detector — locking the existing `startsWith` semantics.
sealed class SpeechFailureReason {
  const SpeechFailureReason();

  /// Wire-format literal for the engine-not-ready guard. Emitted by
  /// `processWithAndroidTts` when `ttsSpeaker == null` or
  /// `speaker.isReady() == false`.
  static const String androidTtsNotReadyLiteral = 'android_tts_not_ready';

  /// Wire-format prefix for any other Android-TTS speak() failure. The
  /// native side appends the inner exception message after `'$prefix: '`
  /// (e.g. `"android_tts_failed: TTS speak timed out"`); see Issue
  /// #695. The prefix is emitted **without** trailing context when the
  /// inner exception has no message, so the parser must accept
  /// `startsWith` matches with no colon as well.
  static const String androidTtsFailedPrefixLiteral = 'android_tts_failed';

  /// Parses a raw `speech_failed` payload `message` string into a
  /// structured reason. Returns `null` when the value does not match
  /// any known reason — callers should treat unknown messages as
  /// non-Android-TTS failures (e.g. VOICEVOX-side errors that the
  /// existing engineStateChanged path handles separately).
  ///
  /// **Caller contract**: [message] must be a non-null `String`. Native
  /// `speech_failed` payloads arrive as `dynamic` (the platform
  /// channel returns `Map<dynamic, dynamic>`), so callers MUST narrow
  /// `payload['message']` with an `is String` check before invoking
  /// this method (see `comment_screen.dart`). Passing a non-string
  /// runtime value is a programming error, not a parse failure.
  static SpeechFailureReason? fromMessage(String message) {
    if (message == androidTtsNotReadyLiteral) {
      return const AndroidTtsNotReady();
    }
    if (message.startsWith(androidTtsFailedPrefixLiteral)) {
      // Trim the prefix and the conventional `: ` separator. If the
      // emitter sent the bare prefix (no colon), the detail is empty.
      final String tail = message.substring(
        androidTtsFailedPrefixLiteral.length,
      );
      String detail = tail;
      if (detail.startsWith(':')) {
        detail = detail.substring(1);
      }
      // Trim only the leading whitespace introduced by the conventional
      // `'android_tts_failed: '` separator. We do NOT trim trailing
      // whitespace because the inner exception message may legitimately
      // contain it and stripping silently could mask a regression.
      detail = detail.trimLeft();
      return AndroidTtsFailed(detail: detail);
    }
    return null;
  }
}

/// The Android TTS engine reported it could not service a speak request
/// because the native `TtsSpeaker` was either null (constructor never
/// ran) or its readiness check returned false. The Flutter UI uses this
/// to advance the consecutive-failure counter and, once a threshold is
/// crossed, flip the AppBar to ERROR.
final class AndroidTtsNotReady extends SpeechFailureReason {
  const AndroidTtsNotReady();
}

/// The Android TTS engine threw or returned a `Result.failure` while
/// servicing a speak request. [detail] holds the inner reason text from
/// the native side (may be empty when the exception had no message).
/// Counted toward the same consecutive-failure threshold as
/// [AndroidTtsNotReady].
final class AndroidTtsFailed extends SpeechFailureReason {
  const AndroidTtsFailed({required this.detail});

  /// The inner exception message after the `'android_tts_failed: '`
  /// prefix is stripped. Empty when the prefix arrived alone.
  final String detail;
}
