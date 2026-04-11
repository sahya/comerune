import 'dart:async';

import 'package:comerune/comment_speech/comment_speech.dart';

/// A fake [CommentSpeechPlatform] for widget tests.
///
/// Tracks method calls and allows controlling responses for assertions.
class FakeCommentSpeechPlatform implements CommentSpeechPlatform {
  bool initializeCalled = false;
  bool startCalled = false;
  bool stopCalled = false;
  bool releaseCalled = false;
  SpeechSettings? lastUpdatedSettings;
  final List<SpeechSettings> updateSettingsCalls = <SpeechSettings>[];
  final List<RawComment> submittedComments = <RawComment>[];
  final StreamController<SpeechEvent> _eventController =
      StreamController<SpeechEvent>.broadcast();

  /// If non-null, [initialize] will throw this.
  Object? initializeError;

  /// If non-null, [submitComment] will throw this for every call.
  Object? submitCommentError;

  /// The models to return from [getAvailableModels].
  List<Map<String, dynamic>> availableModelsToReturn = [];

  /// The status to return from [getStatus].
  SpeechRuntimeStatus statusToReturn = const SpeechRuntimeStatus(
    enabled: false,
    engineState: 'UNKNOWN',
    playerState: 'UNKNOWN',
    queueSize: 0,
    currentSpeakerId: 0,
  );

  /// If non-empty, [getStatus] returns values in sequence and then keeps the
  /// last value.
  List<SpeechRuntimeStatus> statusSequenceToReturn = const [];

  /// Number of calls to [getStatus].
  int getStatusCallCount = 0;

  /// If non-null, [getStatus] throws this.
  Object? getStatusError;

  /// When [getStatusError] is set, this limits throwing to this call number.
  /// If null, every [getStatus] call throws.
  int? getStatusErrorAtCall;

  /// If non-null, [loadModel] will throw this.
  Object? loadModelError;

  /// If non-null, [loadModel] will wait for this completer before returning.
  /// Useful for testing loading indicators and race conditions.
  Completer<void>? loadModelCompleter;

  /// If non-null, [start] will wait for this completer before returning.
  /// Useful for testing initialization races.
  Completer<void>? startCompleter;

  /// If non-null, [getAvailableModels] will throw this.
  Object? getAvailableModelsError;

  /// If non-null, [getAvailableModels] will wait for this completer before
  /// returning.  Useful for testing loading placeholders.
  Completer<void>? getAvailableModelsCompleter;

  /// If non-null, [downloadModel] will throw this.
  Object? downloadModelError;

  /// Tracks which model IDs were passed to [downloadModel].
  final List<String> downloadedModelIds = <String>[];

  /// Tracks which model IDs were passed to [loadModel].
  final List<String> loadedModelIds = <String>[];

  /// Tracks which model IDs were passed to [cancelDownload].
  final List<String> cancelledModelIds = <String>[];

  /// If non-null, [cancelDownload] will throw this.
  Object? cancelDownloadError;

  int _statusSequenceIndex = 0;

  @override
  Future<void> initialize() async {
    initializeCalled = true;
    if (initializeError != null) {
      throw initializeError!;
    }
  }

  @override
  Future<void> start() async {
    startCalled = true;
    if (startCompleter != null) {
      await startCompleter!.future;
    }
  }

  @override
  Future<void> stop({bool clearQueue = false}) async {
    stopCalled = true;
  }

  @override
  Future<void> skip() async {}

  @override
  Future<void> clearQueue() async {}

  @override
  Future<SubmitResult> submitComment(RawComment comment) async {
    submittedComments.add(comment);
    if (submitCommentError != null) {
      throw submitCommentError!;
    }
    return const SubmitResult(accepted: true, skipped: false, queueSize: 1);
  }

  @override
  Future<void> updateSettings(SpeechSettings settings) async {
    lastUpdatedSettings = settings;
    updateSettingsCalls.add(settings);
  }

  @override
  Future<SpeechRuntimeStatus> getStatus() async {
    getStatusCallCount++;
    if (getStatusError != null &&
        (getStatusErrorAtCall == null ||
            getStatusCallCount == getStatusErrorAtCall)) {
      throw getStatusError!;
    }
    if (statusSequenceToReturn.isNotEmpty) {
      final int index = _statusSequenceIndex;
      if (_statusSequenceIndex < statusSequenceToReturn.length - 1) {
        _statusSequenceIndex++;
      }
      return statusSequenceToReturn[index];
    }
    return statusToReturn;
  }

  @override
  Future<void> release() async {
    releaseCalled = true;
  }

  @override
  Stream<SpeechEvent> get events => _eventController.stream;

  @override
  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    if (getAvailableModelsCompleter != null) {
      await getAvailableModelsCompleter!.future;
    }
    if (getAvailableModelsError != null) {
      throw getAvailableModelsError!;
    }
    return availableModelsToReturn;
  }

  @override
  Future<void> downloadModel(String modelId) async {
    downloadedModelIds.add(modelId);
    if (downloadModelError != null) {
      throw downloadModelError!;
    }
  }

  @override
  Future<void> deleteModel(String modelId) async {}

  @override
  Future<List<String>> getDownloadedModels() async {
    return <String>[];
  }

  @override
  Future<void> loadModel(String modelId) async {
    loadedModelIds.add(modelId);
    if (loadModelCompleter != null) {
      await loadModelCompleter!.future;
    }
    if (loadModelError != null) {
      throw loadModelError!;
    }
  }

  @override
  Future<void> cancelDownload(String modelId) async {
    cancelledModelIds.add(modelId);
    if (cancelDownloadError != null) {
      throw cancelDownloadError!;
    }
  }

  /// Emit a speech event for testing.
  void emitEvent(SpeechEvent event) {
    _eventController.add(event);
  }

  void dispose() {
    _eventController.close();
  }
}
