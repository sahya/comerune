import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/foreground_service/foreground_service_manager.dart';

void main() {
  group('ForegroundServiceManager', () {
    late FakeForegroundTaskOperations fakeOps;
    late ForegroundServiceManager manager;

    setUp(() {
      fakeOps = FakeForegroundTaskOperations();
      manager = ForegroundServiceManager(taskOperations: fakeOps);
    });

    test('isRunning is false initially', () {
      expect(manager.isRunning, isFalse);
    });

    test('init calls operations with expected channel configuration', () {
      manager.init();

      expect(fakeOps.initCallCount, 1);
      expect(
        fakeOps.lastAndroidNotificationOptions?.channelId,
        'comerune_foreground_service',
      );
      expect(
        fakeOps.lastAndroidNotificationOptions?.channelImportance,
        NotificationChannelImportance.LOW,
      );
      expect(fakeOps.lastForegroundTaskOptions?.autoRunOnBoot, isFalse);
    });

    test('init enables stopWithTask so app task removal stops the service', () {
      manager.init();

      expect(fakeOps.lastForegroundTaskOptions?.stopWithTask, isTrue);
    });

    test('start passes notificationIcon to operations', () async {
      await manager.start(title: 'Test', text: 'body');

      expect(fakeOps.lastNotificationIcon, isNotNull);
      expect(
        fakeOps.lastNotificationIcon?.metaDataName,
        'com.example.comerune.service.NOTIFICATION_ICON',
      );
      expect(
        fakeOps.lastNotificationIcon?.backgroundColor,
        const Color(0xFF000000),
      );
    });

    test('start sets isRunning to true and calls operations', () async {
      await manager.start(title: 'Test', text: 'body');

      expect(manager.isRunning, isTrue);
      expect(fakeOps.startCallCount, 1);
      expect(fakeOps.lastStartTitle, 'Test');
      expect(fakeOps.lastStartText, 'body');
    });

    test('start is idempotent when already running', () async {
      await manager.start(title: 'A', text: 'a');
      await manager.start(title: 'B', text: 'b');

      expect(fakeOps.startCallCount, 1);
      expect(fakeOps.lastStartTitle, 'A');
    });

    test('stop sets isRunning to false and calls operations', () async {
      await manager.start(title: 'Test', text: 'body');
      await manager.stop();

      expect(manager.isRunning, isFalse);
      expect(fakeOps.stopCallCount, 1);
    });

    test('stop is no-op when not running', () async {
      await manager.stop();

      expect(fakeOps.stopCallCount, 0);
    });

    test('updateNotification delegates to operations', () async {
      await manager.start(title: 'Test', text: 'body');
      await manager.updateNotification(title: 'New', text: 'updated');

      expect(fakeOps.updateCallCount, 1);
      expect(fakeOps.lastUpdateTitle, 'New');
      expect(fakeOps.lastUpdateText, 'updated');
    });

    test('updateNotification is no-op when not running', () async {
      await manager.updateNotification(title: 'New', text: 'updated');

      expect(fakeOps.updateCallCount, 0);
    });

    test('start does not proceed when canStart returns false', () async {
      fakeOps.canStartResult = false;
      await manager.start(title: 'Test', text: 'body');

      expect(manager.isRunning, isFalse);
      expect(fakeOps.startCallCount, 0);
    });

    test('can restart after stop', () async {
      await manager.start(title: 'A', text: 'a');
      await manager.stop();
      await manager.start(title: 'B', text: 'b');

      expect(manager.isRunning, isTrue);
      expect(fakeOps.startCallCount, 2);
      expect(fakeOps.lastStartTitle, 'B');
    });

    test(
      'start catches exception from operations and remains not running',
      () async {
        fakeOps.startException = Exception('platform error');
        await manager.start(title: 'Test', text: 'body');

        expect(manager.isRunning, isFalse);
        expect(fakeOps.startCallCount, 1);
      },
    );

    test(
      'stop catches exception from operations and sets isRunning false',
      () async {
        await manager.start(title: 'Test', text: 'body');
        fakeOps.stopException = Exception('platform error');
        await manager.stop();

        expect(manager.isRunning, isFalse);
      },
    );

    test('updateNotification catches exception from operations '
        'and remains running', () async {
      await manager.start(title: 'Test', text: 'body');
      fakeOps.updateException = Exception('platform error');
      await manager.updateNotification(title: 'New', text: 'updated');

      expect(manager.isRunning, isTrue);
    });
  });
}

class FakeForegroundTaskOperations extends ForegroundTaskOperations {
  int initCallCount = 0;
  int startCallCount = 0;
  int stopCallCount = 0;
  int updateCallCount = 0;
  String? lastStartTitle;
  String? lastStartText;
  NotificationIcon? lastNotificationIcon;
  String? lastUpdateTitle;
  String? lastUpdateText;
  bool canStartResult = true;
  AndroidNotificationOptions? lastAndroidNotificationOptions;
  ForegroundTaskOptions? lastForegroundTaskOptions;
  Exception? startException;
  Exception? stopException;
  Exception? updateException;

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    initCallCount++;
    lastAndroidNotificationOptions = androidNotificationOptions;
    lastForegroundTaskOptions = foregroundTaskOptions;
  }

  @override
  Future<bool> canStart() async => canStartResult;

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    NotificationIcon? notificationIcon,
    required Function callback,
  }) async {
    startCallCount++;
    lastStartTitle = notificationTitle;
    lastStartText = notificationText;
    lastNotificationIcon = notificationIcon;
    if (startException != null) {
      throw startException!;
    }
  }

  @override
  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateCallCount++;
    lastUpdateTitle = notificationTitle;
    lastUpdateText = notificationText;
    if (updateException != null) {
      throw updateException!;
    }
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (stopException != null) {
      throw stopException!;
    }
  }
}
