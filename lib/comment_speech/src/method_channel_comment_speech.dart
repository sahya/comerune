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
      MethodChannel('jp.example.comment_speech/methods');
  static const _eventChannel = EventChannel('jp.example.comment_speech/events');

  late final Stream<SpeechEvent> _events =
      _eventChannel.receiveBroadcastStream().map(
            (event) => SpeechEvent.fromMap(Map<dynamic, dynamic>.from(event)),
          );

  @override
  Future<void> initialize() async {
    await _methodChannel.invokeMethod<void>('initialize');
  }

  @override
  Future<void> start() async {
    await _methodChannel.invokeMethod<void>('start');
  }

  @override
  Future<void> stop({bool clearQueue = false}) async {
    await _methodChannel.invokeMethod<void>('stop', {'clearQueue': clearQueue});
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
    await _methodChannel.invokeMethod<void>(
      'updateSettings',
      settings.toMap(),
    );
  }

  @override
  Future<SpeechRuntimeStatus> getStatus() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>(
      'getStatus',
    );
    if (result == null) {
      throw PlatformException(
        code: 'NULL_RESPONSE',
        message: 'getStatus returned null from the platform channel',
      );
    }
    return SpeechRuntimeStatus.fromMap(result);
  }

  @override
  Future<void> release() async {
    await _methodChannel.invokeMethod<void>('release');
  }

  @override
  Stream<SpeechEvent> get events => _events;
}
