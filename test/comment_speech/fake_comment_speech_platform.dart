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
    return const SubmitResult(
      accepted: true,
      skipped: false,
      queueSize: 1,
    );
  }

  @override
  Future<void> updateSettings(SpeechSettings settings) async {
    lastUpdatedSettings = settings;
  }

  @override
  Future<SpeechRuntimeStatus> getStatus() async {
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
    return availableModelsToReturn;
  }

  @override
  Future<void> downloadModel(String modelId) async {}

  @override
  Future<void> deleteModel(String modelId) async {}

  @override
  Future<List<String>> getDownloadedModels() async {
    return <String>[];
  }

  @override
  Future<void> loadModel(String modelId) async {}

  /// Emit a speech event for testing.
  void emitEvent(SpeechEvent event) {
    _eventController.add(event);
  }

  void dispose() {
    _eventController.close();
  }
}
