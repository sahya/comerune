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
  static const _methodChannel =
      MethodChannel('com.example.comerune.speech/methods');
  static const _eventChannel =
      EventChannel('com.example.comerune.speech/events');

  late final Stream<SpeechEvent> _events =
      _eventChannel.receiveBroadcastStream().map(
    (event) {
      final parsed = SpeechEvent.fromMap(Map<dynamic, dynamic>.from(event));
      debugPrint('[MethodChannel] event: ${parsed.type}');
      return parsed;
    },
  );

  @override
  Future<void> initialize() async {
    debugPrint('[MethodChannel] → initialize()');
    await _methodChannel.invokeMethod<void>('initialize');
    debugPrint('[MethodChannel] ← initialize() done');
  }

  @override
  Future<void> start() async {
    debugPrint('[MethodChannel] → start()');
    await _methodChannel.invokeMethod<void>('start');
    debugPrint('[MethodChannel] ← start() done');
  }

  @override
  Future<void> stop({bool clearQueue = false}) async {
    debugPrint('[MethodChannel] → stop(clearQueue=$clearQueue)');
    await _methodChannel.invokeMethod<void>('stop', {'clearQueue': clearQueue});
    debugPrint('[MethodChannel] ← stop() done');
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
    debugPrint(
      '[MethodChannel] → updateSettings(enabled=${settings.enabled}, speaker=${settings.speakerId}, speed=${settings.speedScale})',
    );
    await _methodChannel.invokeMethod<void>(
      'updateSettings',
      settings.toMap(),
    );
    debugPrint('[MethodChannel] ← updateSettings() done');
  }

  @override
  Future<SpeechRuntimeStatus> getStatus() async {
    debugPrint('[MethodChannel] → getStatus()');
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
    debugPrint(
      '[MethodChannel] ← getStatus: engine=${parsed.engineState}, player=${parsed.playerState}, queue=${parsed.queueSize}',
    );
    return parsed;
  }

  @override
  Future<void> release() async {
    debugPrint('[MethodChannel] → release()');
    await _methodChannel.invokeMethod<void>('release');
  }

  @override
  Stream<SpeechEvent> get events => _events;

  @override
  Future<List<Map<String, dynamic>>> getAvailableModels() async {
    final result = await _methodChannel.invokeListMethod<Map<dynamic, dynamic>>(
      'getAvailableModels',
    );
    if (result == null) return [];
    return result.map((m) => Map<String, dynamic>.from(m)).toList();
  }

  @override
  Future<void> downloadModel(String modelId) async {
    await _methodChannel
        .invokeMethod<void>('downloadModel', {'modelId': modelId});
  }

  @override
  Future<void> deleteModel(String modelId) async {
    await _methodChannel
        .invokeMethod<void>('deleteModel', {'modelId': modelId});
  }

  @override
  Future<List<String>> getDownloadedModels() async {
    final result =
        await _methodChannel.invokeListMethod<String>('getDownloadedModels');
    return result ?? [];
  }

  @override
  Future<void> loadModel(String modelId) async {
    await _methodChannel.invokeMethod<void>('loadModel', {'modelId': modelId});
  }
}
