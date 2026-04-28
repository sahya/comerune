import 'dart:developer' as developer;

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:meta/meta.dart';

/// Manages the Android Foreground Service lifecycle for maintaining
/// WebSocket/HTTP streaming connections while the app is backgrounded.
///
/// This class wraps [FlutterForegroundTask] to:
/// - Show a persistent notification with broadcast info
/// - Keep the process alive during screen-off / app-switch
/// - Stop the service when the connection ends
///
/// The Android service is declared with `foregroundServiceType="dataSync"` in
/// `AndroidManifest.xml` because the actual workload is keeping a comment
/// streaming connection alive (data sync), not media playback.
///
/// Callers should only instantiate this class on Android.
/// On non-Android platforms, pass `null` instead.
class ForegroundServiceManager {
  ForegroundServiceManager({
    @visibleForTesting ForegroundTaskOperations? taskOperations,
  }) : _ops = taskOperations ?? const _DefaultForegroundTaskOperations();

  final ForegroundTaskOperations _ops;
  bool _isRunning = false;

  /// Whether the foreground service is currently active.
  bool get isRunning => _isRunning;

  /// Initializes the foreground task configuration.
  ///
  /// Must be called once before [start], typically during app startup.
  void init() {
    _ops.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'comerune_foreground_service',
        channelName: 'コメント接続',
        channelDescription: 'コメント接続を維持するためのサービス',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the foreground service with the given notification content.
  ///
  /// [title] is the notification title (e.g. app name or broadcast title).
  /// [text] is the notification body text.
  ///
  /// No-op if already running.
  Future<void> start({required String title, required String text}) async {
    if (_isRunning) {
      return;
    }

    try {
      final bool canStart = await _ops.canStart();
      if (!canStart) {
        return;
      }

      await _ops.start(
        notificationTitle: title,
        notificationText: text,
        callback: _foregroundTaskCallback,
      );
      _isRunning = true;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to start foreground service',
        name: 'ForegroundServiceManager',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Updates the notification content while the service is running.
  ///
  /// Use this to reflect program title changes or connection status.
  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!_isRunning) {
      return;
    }

    try {
      await _ops.update(notificationTitle: title, notificationText: text);
    } catch (error, stackTrace) {
      developer.log(
        'Failed to update foreground service notification',
        name: 'ForegroundServiceManager',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stops the foreground service.
  ///
  /// No-op if not running.
  Future<void> stop() async {
    if (!_isRunning) {
      return;
    }

    _isRunning = false;
    try {
      await _ops.stop();
    } catch (error, stackTrace) {
      developer.log(
        'Failed to stop foreground service',
        name: 'ForegroundServiceManager',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

// Top-level callback required by flutter_foreground_task.
// The actual work (WebSocket/HTTP streaming) runs in the main isolate,
// so this callback intentionally does nothing.
@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_NoOpTaskHandler());
}

class _NoOpTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Abstraction over [FlutterForegroundTask] static methods for testability.
@visibleForTesting
abstract class ForegroundTaskOperations {
  const ForegroundTaskOperations();

  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  });

  Future<bool> canStart();

  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
  });

  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  });

  Future<void> stop();
}

class _DefaultForegroundTaskOperations extends ForegroundTaskOperations {
  const _DefaultForegroundTaskOperations();

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    FlutterForegroundTask.init(
      androidNotificationOptions: androidNotificationOptions,
      iosNotificationOptions: iosNotificationOptions,
      foregroundTaskOptions: foregroundTaskOptions,
    );
  }

  @override
  Future<bool> canStart() async {
    // Check notification permission on Android 13+.
    final NotificationPermission permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
      final NotificationPermission afterRequest =
          await FlutterForegroundTask.checkNotificationPermission();
      if (afterRequest != NotificationPermission.granted) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
  }) async {
    await FlutterForegroundTask.startService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: callback,
    );
  }

  @override
  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  }) async {
    await FlutterForegroundTask.updateService(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  @override
  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }
}
