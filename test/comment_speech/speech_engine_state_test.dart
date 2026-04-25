import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/speech_engine_state.dart';

void main() {
  group('SpeechEngineState', () {
    group('wire literal pinning', () {
      // Issue #717 (ARCH-2): the wire-format strings stay the historical
      // uppercase values used by the native `engine_state_changed` event.
      // Pin them here so that a careless rename trips this test before
      // any production behaviour breaks.
      test('readyWire matches the native emitter', () {
        expect(SpeechEngineState.readyWire, 'READY');
      });

      test('errorWire matches the native emitter', () {
        expect(SpeechEngineState.errorWire, 'ERROR');
      });

      test('unknownWire is the empty string', () {
        expect(SpeechEngineState.unknownWire, '');
      });
    });

    group('fromWire', () {
      test('"READY" → ready', () {
        expect(SpeechEngineState.fromWire('READY'), SpeechEngineState.ready);
      });

      test('"ERROR" → error', () {
        expect(SpeechEngineState.fromWire('ERROR'), SpeechEngineState.error);
      });

      test('empty string → unknown', () {
        expect(SpeechEngineState.fromWire(''), SpeechEngineState.unknown);
      });

      test('any unrecognised string → unknown (defensive default)', () {
        // Defensive default: native may add new states in the future
        // (Issue #695 review #7), and the listener must NOT throw on
        // unknown payloads — that would tear down the StreamSubscription
        // and silently break all future event delivery.
        expect(
          SpeechEngineState.fromWire('UNINITIALIZED'),
          SpeechEngineState.unknown,
        );
        expect(SpeechEngineState.fromWire('busy'), SpeechEngineState.unknown);
        expect(
          SpeechEngineState.fromWire('READY '),
          SpeechEngineState.unknown,
          reason: 'fromWire is a strict equality match (no whitespace trim)',
        );
      });

      test('parser is case-sensitive', () {
        // The native emitter sends uppercase. Anything else is treated
        // as foreign payload.
        expect(SpeechEngineState.fromWire('ready'), SpeechEngineState.unknown);
        expect(SpeechEngineState.fromWire('Error'), SpeechEngineState.unknown);
      });
    });

    group('idempotent equality', () {
      test('two enum values of the same kind compare equal', () {
        // Sanity: a setter that uses `if (_x == next) return;` for
        // idempotency relies on this being true. The widget-level
        // setter test lives in
        // `test/presentation/screens/comment_screen_speech_test.dart`
        // (existing) — see "ERROR threshold" cases.
        expect(SpeechEngineState.error == SpeechEngineState.error, isTrue);
        expect(SpeechEngineState.unknown == SpeechEngineState.unknown, isTrue);
        expect(SpeechEngineState.ready != SpeechEngineState.error, isTrue);
      });
    });

    group('exhaustive switch', () {
      test('switch on SpeechEngineState covers all cases', () {
        // Compile-time check: adding a new enum value will surface as
        // a missing-case error at every site that switches on this type
        // (e.g. `speechIconViewFor` in `comment_screen.dart`).
        String describe(SpeechEngineState s) => switch (s) {
          SpeechEngineState.unknown => 'unknown',
          SpeechEngineState.ready => 'ready',
          SpeechEngineState.error => 'error',
        };
        expect(describe(SpeechEngineState.unknown), 'unknown');
        expect(describe(SpeechEngineState.ready), 'ready');
        expect(describe(SpeechEngineState.error), 'error');
      });
    });
  });
}
