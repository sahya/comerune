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
  });
}

class FakeForegroundTaskOperations extends ForegroundTaskOperations {
  int startCallCount = 0;
  int stopCallCount = 0;
  int updateCallCount = 0;
  String? lastStartTitle;
  String? lastStartText;
  String? lastUpdateTitle;
  String? lastUpdateText;
  bool canStartResult = true;

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {}

  @override
  Future<bool> canStart() async => canStartResult;

  @override
  Future<void> start({
    required String notificationTitle,
    required String notificationText,
    required Function callback,
  }) async {
    startCallCount++;
    lastStartTitle = notificationTitle;
    lastStartText = notificationText;
  }

  @override
  Future<void> update({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateCallCount++;
    lastUpdateTitle = notificationTitle;
    lastUpdateText = notificationText;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }
}
