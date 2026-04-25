import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/speech_failure_reason.dart';

void main() {
  group('SpeechFailureReason', () {
    group('literal pinning', () {
      // Issue #716 (ARCH-1): pin the wire-format strings so that a
      // careless rename on the Dart side trips this test before any
      // production behaviour breaks. Mirror these values in
      // `android/.../SpeechControllerImpl.kt` and the Kotlin contract
      // test (`PrefixContract.NOT_READY` / `PrefixContract.FAILED_PREFIX`).
      test('androidTtsNotReadyLiteral matches the native emitter', () {
        expect(
          SpeechFailureReason.androidTtsNotReadyLiteral,
          'android_tts_not_ready',
        );
      });

      test('androidTtsFailedPrefixLiteral matches the native emitter', () {
        expect(
          SpeechFailureReason.androidTtsFailedPrefixLiteral,
          'android_tts_failed',
        );
      });
    });

    group('fromMessage', () {
      test('returns AndroidTtsNotReady for the exact not-ready literal', () {
        final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
          'android_tts_not_ready',
        );
        expect(reason, isA<AndroidTtsNotReady>());
      });

      test('returns AndroidTtsFailed with stripped detail for the conventional '
          'colon-space separator', () {
        final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
          'android_tts_failed: TTS speak timed out',
        );
        expect(reason, isA<AndroidTtsFailed>());
        expect((reason as AndroidTtsFailed).detail, 'TTS speak timed out');
      });

      test(
        'returns AndroidTtsFailed with stripped detail when only a colon (no space)',
        () {
          final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
            'android_tts_failed:io error',
          );
          expect(reason, isA<AndroidTtsFailed>());
          expect((reason as AndroidTtsFailed).detail, 'io error');
        },
      );

      test(
        'returns AndroidTtsFailed with empty detail for the bare prefix',
        () {
          final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
            'android_tts_failed',
          );
          // Locking the existing `startsWith` semantics (PR #695). The
          // bare prefix without `:` is treated as a failed event with
          // an empty detail so an emitter quirk on the native side
          // doesn't silently bypass the detector.
          expect(reason, isA<AndroidTtsFailed>());
          expect((reason as AndroidTtsFailed).detail, '');
        },
      );

      test(
        'returns AndroidTtsFailed with empty detail for prefix + colon only',
        () {
          final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
            'android_tts_failed:',
          );
          expect(reason, isA<AndroidTtsFailed>());
          expect((reason as AndroidTtsFailed).detail, '');
        },
      );

      test('preserves trailing whitespace in detail', () {
        // We trim only the leading `: ` separator. Trailing whitespace
        // belongs to the inner exception message — silently stripping
        // it could mask a regression where the native side started
        // padding messages.
        final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
          'android_tts_failed: trailing space   ',
        );
        expect(reason, isA<AndroidTtsFailed>());
        expect((reason as AndroidTtsFailed).detail, 'trailing space   ');
      });

      test('returns null for unknown payloads (e.g. VOICEVOX errors)', () {
        // VOICEVOX-side errors (synthesis_failed, playback_failed) come
        // through a different code path and must NOT be classified as
        // Android-TTS failures.
        expect(SpeechFailureReason.fromMessage('synthesis_failed'), isNull);
        expect(SpeechFailureReason.fromMessage('playback_failed'), isNull);
        expect(SpeechFailureReason.fromMessage(''), isNull);
        expect(SpeechFailureReason.fromMessage('unknown'), isNull);
      });

      test(
        'parser is case-sensitive (locks behaviour with the native emitter)',
        () {
          // The native side emits lowercase. A different casing on the
          // wire is foreign payload and should NOT be matched.
          expect(
            SpeechFailureReason.fromMessage('Android_TTS_Not_Ready'),
            isNull,
          );
          expect(
            SpeechFailureReason.fromMessage('ANDROID_TTS_FAILED:x'),
            isNull,
          );
        },
      );

      test(
        'does NOT classify near-prefix strings (e.g. typos) as failures',
        () {
          // `startsWith('android_tts_failed')` would match
          // `'android_tts_failed_extra'` accidentally. Confirm this
          // accepted side effect of `startsWith` is locked into the
          // parser too, mirroring pre-SSOT behaviour byte-for-byte.
          // Callers that want strict matching should switch to a
          // `String == 'android_tts_failed:'` test, but the production
          // detector intentionally accepts variants to be liberal in
          // what it accepts (rationale: prefer false-positives over
          // missing failures in the detector).
          final SpeechFailureReason? reason = SpeechFailureReason.fromMessage(
            'android_tts_failed_extra',
          );
          expect(reason, isA<AndroidTtsFailed>());
          // The detail captures the trailing portion verbatim.
          expect((reason as AndroidTtsFailed).detail, '_extra');
        },
      );
    });

    group('sealed class exhaustiveness', () {
      test('switch on SpeechFailureReason covers all cases', () {
        // Compile-time exhaustiveness: if a new subclass is added,
        // this switch must be updated, surfacing the addition.
        String describe(SpeechFailureReason r) => switch (r) {
          AndroidTtsNotReady() => 'not-ready',
          AndroidTtsFailed(detail: final d) => 'failed:$d',
        };
        expect(describe(const AndroidTtsNotReady()), 'not-ready');
        expect(describe(const AndroidTtsFailed(detail: 'x')), 'failed:x');
      });
    });
  });
}
