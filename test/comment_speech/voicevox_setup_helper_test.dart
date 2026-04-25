import 'dart:async';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_comment_speech_platform.dart';

void main() {
  group('VoicevoxSetupHelper', () {
    late FakeCommentSpeechPlatform platform;

    setUp(() {
      platform = FakeCommentSpeechPlatform();
    });

    tearDown(() {
      platform.dispose();
    });

    test(
      'reaches ready state when initialize completes before dispose',
      () async {
        final helper = VoicevoxSetupHelper(platform);
        addTearDown(() {
          if (!helper.isDisposed) helper.dispose();
        });

        await helper.start();

        expect(helper.state.value, VoicevoxSetupState.ready);
        expect(helper.progress.value, 1.0);
        expect(helper.statusMessage.value, '準備完了');
      },
    );

    test('does not throw when initialize resolves after dispose', () async {
      final gate = Completer<void>();
      platform.initializeCompleter = gate;

      final helper = VoicevoxSetupHelper(platform);
      final startFuture = helper.start();

      // Simulate the owning widget being torn down while
      // `_platform.initialize()` is still pending.
      helper.dispose();

      // Resolving the platform initialization after dispose must not throw
      // and must not mutate the (already-disposed) notifiers.
      gate.complete();
      await startFuture;

      expect(helper.isDisposed, isTrue);
      // If `state` had been written to after dispose, ValueNotifier would
      // have thrown a FlutterError before we get here.
    });

    test('does not throw when initialize throws after dispose', () async {
      final gate = Completer<void>();
      platform.initializeCompleter = gate;
      platform.initializeError = Exception('native init failed');

      final helper = VoicevoxSetupHelper(platform);
      final startFuture = helper.start();

      helper.dispose();

      gate.complete();
      await startFuture;

      expect(helper.isDisposed, isTrue);
    });

    test('does not throw when speech events arrive after dispose', () async {
      final helper = VoicevoxSetupHelper(platform);
      // Start subscription; keep initialize pending so start() stays alive
      // while we dispose and emit events.
      final gate = Completer<void>();
      platform.initializeCompleter = gate;
      final startFuture = helper.start();

      helper.dispose();

      // Emitting every event type that _onEvent handles must be safe after
      // dispose. This covers downloadStarted / downloadProgress /
      // downloadCompleted / engineStateChanged (both READY and ERROR).
      platform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.downloadStarted,
          payload: {'fileName': 'model.vvm'},
        ),
      );
      platform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.downloadProgress,
          payload: {'bytesDownloaded': 512, 'totalBytes': 1024},
        ),
      );
      platform.emitEvent(
        const SpeechEvent(type: SpeechEventType.downloadCompleted, payload: {}),
      );
      platform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.engineStateChanged,
          payload: {'state': 'READY'},
        ),
      );
      platform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.engineStateChanged,
          payload: {'state': 'ERROR'},
        ),
      );

      // Let pending microtasks and stream deliveries flush.
      await Future<void>.delayed(Duration.zero);

      gate.complete();
      await startFuture;

      expect(helper.isDisposed, isTrue);
    });

    test(
      'subsequent start() after dispose is a no-op and does not throw',
      () async {
        final helper = VoicevoxSetupHelper(platform);
        helper.dispose();

        await helper.start();

        expect(helper.isDisposed, isTrue);
        expect(platform.initializeCalled, isFalse);
      },
    );

    test('dispose() is idempotent', () {
      final helper = VoicevoxSetupHelper(platform);
      helper.dispose();
      // A second dispose() must not throw (would happen if we tried to
      // dispose the ValueNotifiers twice).
      expect(helper.dispose, returnsNormally);
    });
  });
}
