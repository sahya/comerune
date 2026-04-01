import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'comment_speech_platform.dart';
import 'models/raw_comment.dart';
import 'models/speech_event.dart';
import 'models/speech_runtime_status.dart';
import 'models/speech_settings.dart';
import 'models/submit_result.dart';

/// [CommentSpeechPlatform] implementation backed by MethodChannel and
/// EventChannel that delegates to the Android Kotlin plugin.
class MethodChannelCommentSpeech implements CommentSpeechPlatform {
  static const _methodChannel = MethodChannel(
    'com.example.comerune.speech/methods',
  );
  static const _eventChannel = EventChannel(
    'com.example.comerune.speech/events',
  );
  static const Set<String> _noisyEventTypes = <String>{
    SpeechEventType.downloadProgress,
    SpeechEventType.modelDownloadProgress,
  };

  static void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  late final Stream<SpeechEvent> _events =
      _eventChannel.receiveBroadcastStream().map((event) {
    final parsed = SpeechEvent.fromMap(Map<dynamic, dynamic>.from(event));
    if (!_noisyEventTypes.contains(parsed.type)) {
      _debugLog('[MethodChannel] event: ${parsed.type}');
    }
    return parsed;
  });

  @override
  Future<void> initialize() async {
    _debugLog('[MethodChannel] → initialize()');
    await _methodChannel.invokeMethod<void>('initialize');
    _debugLog('[MethodChannel] ← initialize() done');
  }

  @override
  Future<void> start() async {
    _debugLog('[MethodChannel] → start()');
    await _methodChannel.invokeMethod<void>('start');
    _debugLog('[MethodChannel] ← start() done');
  }

  @override
  Future<void> stop({bool clearQueue = false}) async {
    _debugLog('[MethodChannel] → stop(clearQueue=$clearQueue)');
    await _methodChannel.invokeMethod<void>('stop', {'clearQueue': clearQueue});
    _debugLog('[MethodChannel] ← stop() done');
  }

  @override
  Future<void> skip() async {
    await _methodChannel.invokeMethod<void>('skip');
  }

  @override
  Future<void> clearQueue() async {
    await _methodChannel.invokeMethod<void>('clearQueue');
  }

  @override
  Future<SubmitResult> submitComment(RawComment comment) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'submitComment',
      comment.toMap(),
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESPONSE',
        message: 'submitComment returned null from the platform channel',
      );
    }
    return SubmitResult.fromMap(result);
  }

  @override
  Future<void> updateSettings(SpeechSettings settings) async {
    _debugLog(
      '[MethodChannel] → updateSettings(enabled=${settings.enabled}, speaker=${settings.speakerId}, speed=${settings.speedScale})',
    );
    await _methodChannel.invokeMethod<void>('updateSettings', settings.toMap());
    _debugLog('[MethodChannel] ← updateSettings() done');
  }

  @override
  Future<SpeechRuntimeStatus> getStatus() async {
    _debugLog('[MethodChannel] → getStatus()');
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getStatus',
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESPONSE',
        message: 'getStatus returned null from the platform channel',
      );
    }
    final parsed = SpeechRuntimeStatus.fromMap(result);
    _debugLog(
      '[MethodChannel] ← getStatus: engine=${parsed.engineState}, player=${parsed.playerState}, queue=${parsed.queueSize}',
    );
    return parsed;
  }

  @override
  Future<void> release() async {
    _debugLog('[MethodChannel] → release()');
    await _methodChannel.invokeMethod<void>('release');
  }

  @override
  Stream<SpeechEvent> get events => _events;

  @override
  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    _debugLog('[MethodChannel] → getAvailableModels()');
    final result = await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>(
      'getAvailableModels',
    );
    if (result == null) {
      _debugLog('[MethodChannel] ← getAvailableModels(): 0 models (null)');
      return [];
    }
    final models = result.map((m) => Map<String, dynamic>.from(m)).toList();
    _debugLog(
      '[MethodChannel] ← getAvailableModels(): ${models.length} models',
    );
    return models;
  }

  @override
  Future<void> downloadModel(String modelId) async {
    _debugLog('[MethodChannel] → downloadModel(modelId=$modelId)');
    await _methodChannel.invokeMethod<void>('downloadModel', {
      'modelId': modelId,
    });
    _debugLog('[MethodChannel] ← downloadModel() done modelId=$modelId');
  }

  @override
  Future<void> deleteModel(String modelId) async {
    _debugLog('[MethodChannel] → deleteModel(modelId=$modelId)');
    await _methodChannel.invokeMethod<void>('deleteModel', {
      'modelId': modelId,
    });
    _debugLog('[MethodChannel] ← deleteModel() done modelId=$modelId');
  }

  @override
  Future<List<String>> getDownloadedModels() async {
    final result = await _methodChannel.invokeListMethod<String>(
      'getDownloadedModels',
    );
    return result ?? [];
  }

  @override
  Future<void> loadModel(String modelId) async {
    _debugLog('[MethodChannel] → loadModel(modelId=$modelId)');
    await _methodChannel.invokeMethod<void>('loadModel', {'modelId': modelId});
    _debugLog('[MethodChannel] ← loadModel() done modelId=$modelId');
  }

  @override
  Future<void> cancelDownload(String modelId) async {
    _debugLog('[MethodChannel] → cancelDownload(modelId=$modelId)');
    await _methodChannel.invokeMethod<void>('cancelDownload', {
      'modelId': modelId,
    });
    _debugLog('[MethodChannel] ← cancelDownload() done modelId=$modelId');
  }
}
