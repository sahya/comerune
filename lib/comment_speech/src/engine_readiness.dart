import 'dart:async';

import '../../app_logging.dart';

import 'comment_speech_platform.dart';
import 'models/speech_runtime_status.dart';

const String _readyState = 'READY';
const Set<String> _transitionalStates = <String>{
  'INITIALIZING',
  'SYNTHESIZING',
};
const Set<String> _initializableStates = <String>{
  'UNINITIALIZED',
  'ERROR',
  'UNKNOWN',
};

/// Poll settings for long-running VOICEVOX initialization on slower devices.
const Duration voicevoxReadyPollInterval = Duration(milliseconds: 500);
const int voicevoxReadyMaxPollAttempts = 600;

void _debugLog(String Function() messageBuilder) {
  appDebugLogLazy(messageBuilder);
}

Future<void> ensureEngineReadyForModelLoad(
  CommentSpeechPlatform platform, {
  String logTag = '[SpeechEngine]',
  Duration pollInterval = const Duration(milliseconds: 150),
  int maxPollAttempts = 20,
}) async {
  SpeechRuntimeStatus status = await platform.getStatus();
  _debugLog(
    () =>
        '$logTag status-check(ready-guard): engineState=${status.engineState}',
  );

  if (_isReady(status.engineState)) {
    _debugLog(() => '$logTag ensureEngineReady: decision=already_ready');
    return;
  }

  if (_isTransitional(status.engineState)) {
    status = await _waitForStableState(
      platform,
      initialStatus: status,
      logTag: logTag,
      pollInterval: pollInterval,
      maxPollAttempts: maxPollAttempts,
    );
    if (_isReady(status.engineState)) {
      _debugLog(() => '$logTag ensureEngineReady: decision=ready_after_wait');
      return;
    }
  }

  if (_canInitialize(status.engineState)) {
    _debugLog(
      () => '$logTag ensureEngineReady: decision=initialize '
          'fromState=${status.engineState}',
    );
    await platform.initialize();
    _debugLog(() => '$logTag ensureEngineReady: decision=initialize_completed');
    return;
  }

  throw StateError(
    'Cannot prepare engine for model load from state: ${status.engineState}',
  );
}

Future<SpeechRuntimeStatus> _waitForStableState(
  CommentSpeechPlatform platform, {
  required SpeechRuntimeStatus initialStatus,
  required String logTag,
  required Duration pollInterval,
  required int maxPollAttempts,
}) async {
  SpeechRuntimeStatus latest = initialStatus;
  for (int i = 1; i <= maxPollAttempts; i++) {
    await Future<void>.delayed(pollInterval);
    latest = await platform.getStatus();
    _debugLog(
      () =>
          '$logTag status-check(wait-guard): engineState=${latest.engineState} '
          '(attempt=$i/$maxPollAttempts)',
    );
    if (!_isTransitional(latest.engineState)) {
      return latest;
    }
  }
  final int pollIntervalMs = pollInterval.inMilliseconds;
  throw TimeoutException(
    'Engine state did not settle from ${initialStatus.engineState} '
    '(attempts=$maxPollAttempts, pollIntervalMs=$pollIntervalMs, '
    'lastState=${latest.engineState})',
  );
}

bool _isReady(String state) => _normalizedState(state) == _readyState;

bool _isTransitional(String state) =>
    _transitionalStates.contains(_normalizedState(state));

bool _canInitialize(String state) =>
    _initializableStates.contains(_normalizedState(state));

String _normalizedState(String state) => state.trim().toUpperCase();
