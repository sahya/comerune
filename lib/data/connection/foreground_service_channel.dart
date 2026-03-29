import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Platform channel wrapper for the Android Foreground Service.
///
/// On non-Android platforms, all methods are no-ops.
class ForegroundServiceChannel {
  ForegroundServiceChannel({
    MethodChannel? channel,
    @visibleForTesting bool? platformOverride,
  })  : _channel = channel ??
            const MethodChannel('com.example.comerune/foreground_service'),
        _isAndroid = platformOverride ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Starts the foreground service with a notification.
  ///
  /// [title] is the notification title (e.g. program title).
  /// [body] is the notification body text.
  Future<void> startService({
    String title = 'comerune',
    String body = '接続中...',
  }) async {
    if (!_isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('startService', <String, String>{
        'title': title,
        'body': body,
      });
      _isRunning = true;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to start foreground service: $error',
        name: 'ForegroundServiceChannel',
        stackTrace: stackTrace,
      );
    }
  }

  /// Updates the notification content without restarting the service.
  Future<void> updateNotification({
    String title = 'comerune',
    String body = '接続中...',
  }) async {
    if (!_isAndroid || !_isRunning) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('updateNotification', <String, String>{
        'title': title,
        'body': body,
      });
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to update foreground service notification: $error',
        name: 'ForegroundServiceChannel',
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops the foreground service and removes the notification.
  Future<void> stopService() async {
    if (!_isAndroid || !_isRunning) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopService');
      _isRunning = false;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to stop foreground service: $error',
        name: 'ForegroundServiceChannel',
        stackTrace: stackTrace,
      );
    }
  }
}
