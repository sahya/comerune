import 'dart:async';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_comment_speech_platform.dart';

const SpeechRuntimeStatus _readyStatus = SpeechRuntimeStatus(
  enabled: true,
  engineState: 'READY',
  playerState: 'IDLE',
  queueSize: 0,
  currentSpeakerId: 0,
);

const SpeechRuntimeStatus _initializingStatus = SpeechRuntimeStatus(
  enabled: true,
  engineState: 'INITIALIZING',
  playerState: 'IDLE',
  queueSize: 0,
  currentSpeakerId: 0,
);

const SpeechRuntimeStatus _downloadingStatus = SpeechRuntimeStatus(
  enabled: true,
  engineState: 'DOWNLOADING',
  playerState: 'IDLE',
  queueSize: 0,
  currentSpeakerId: 0,
);

const SpeechRuntimeStatus _extractingStatus = SpeechRuntimeStatus(
  enabled: true,
  engineState: 'EXTRACTING',
  playerState: 'IDLE',
  queueSize: 0,
  currentSpeakerId: 0,
);

const SpeechRuntimeStatus _uninitializedStatus = SpeechRuntimeStatus(
  enabled: false,
  engineState: 'UNINITIALIZED',
  playerState: 'UNKNOWN',
  queueSize: 0,
  currentSpeakerId: 0,
);

void main() {
  group('ensureEngineReadyForModelLoad', () {
    test('does not initialize when state is READY', () async {
      final platform = FakeCommentSpeechPlatform()
        ..statusToReturn = _readyStatus;

      await ensureEngineReadyForModelLoad(
        platform,
        pollInterval: Duration.zero,
      );

      expect(platform.initializeCalled, isFalse);
      expect(platform.getStatusCallCount, 1);
    });

    test('initializes when state is UNINITIALIZED', () async {
      final platform = FakeCommentSpeechPlatform()
        ..statusToReturn = _uninitializedStatus;

      await ensureEngineReadyForModelLoad(
        platform,
        pollInterval: Duration.zero,
      );

      expect(platform.initializeCalled, isTrue);
      expect(platform.getStatusCallCount, 1);
    });

    test('waits transitional state and skips initialize when READY', () async {
      final platform = FakeCommentSpeechPlatform()
        ..statusSequenceToReturn = <SpeechRuntimeStatus>[
          _initializingStatus,
          _readyStatus,
        ];

      await ensureEngineReadyForModelLoad(
        platform,
        pollInterval: Duration.zero,
        maxPollAttempts: 2,
      );

      expect(platform.initializeCalled, isFalse);
      expect(platform.getStatusCallCount, 2);
    });

    test(
      'extends wait budget when asset preparation state is observed',
      () async {
        final platform = FakeCommentSpeechPlatform()
          ..statusSequenceToReturn = <SpeechRuntimeStatus>[
            _downloadingStatus,
            _downloadingStatus,
            _readyStatus,
          ];

        await ensureEngineReadyForModelLoad(
          platform,
          pollInterval: Duration.zero,
          maxPollAttempts: 1,
        );

        expect(platform.initializeCalled, isFalse);
        expect(platform.getStatusCallCount, 3);
      },
    );

    test(
      'extends wait budget when asset preparation starts during wait',
      () async {
        final platform = FakeCommentSpeechPlatform()
          ..statusSequenceToReturn = <SpeechRuntimeStatus>[
            _initializingStatus,
            _downloadingStatus,
            _extractingStatus,
            _readyStatus,
          ];

        await ensureEngineReadyForModelLoad(
          platform,
          pollInterval: Duration.zero,
          maxPollAttempts: 1,
        );

        expect(platform.initializeCalled, isFalse);
        expect(platform.getStatusCallCount, 4);
      },
    );

    test(
      'waits transitional state then initializes when UNINITIALIZED',
      () async {
        final platform = FakeCommentSpeechPlatform()
          ..statusSequenceToReturn = <SpeechRuntimeStatus>[
            _initializingStatus,
            _uninitializedStatus,
          ];

        await ensureEngineReadyForModelLoad(
          platform,
          pollInterval: Duration.zero,
          maxPollAttempts: 2,
        );

        expect(platform.initializeCalled, isTrue);
        expect(platform.getStatusCallCount, 2);
      },
    );

    test('throws timeout when transitional state does not settle', () async {
      final platform = FakeCommentSpeechPlatform()
        ..statusSequenceToReturn = <SpeechRuntimeStatus>[_initializingStatus];

      await expectLater(
        () => ensureEngineReadyForModelLoad(
          platform,
          pollInterval: Duration.zero,
          maxPollAttempts: 2,
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(platform.initializeCalled, isFalse);
      expect(platform.getStatusCallCount, 3);
    });
  });
}
