import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/foreground_service/foreground_service_controller.dart';
import 'package:comerune/data/foreground_service/foreground_service_manager.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';

void main() {
  group('ForegroundServiceController', () {
    late FakeForegroundTaskOperations fakeOps;
    late ForegroundServiceManager manager;
    late ConnectionSupervisor supervisor;
    late ValueNotifier<String?> titleNotifier;

    setUp(() {
      fakeOps = FakeForegroundTaskOperations();
      manager = ForegroundServiceManager(taskOperations: fakeOps);
      supervisor = ConnectionSupervisor();
      titleNotifier = ValueNotifier<String?>(null);
    });

    tearDown(() {
      supervisor.dispose();
      titleNotifier.dispose();
    });

    ForegroundServiceController createController({
      bool Function()? playRemainingAfterEnded,
      Duration graceDuration = const Duration(seconds: 30),
    }) {
      return ForegroundServiceController(
        foregroundServiceManager: manager,
        connectionSupervisor: supervisor,
        programTitleNotifier: titleNotifier,
        // Issue #739: keep the legacy "stop immediately on ended" semantics
        // for the original test suite by defaulting the grace toggle to
        // OFF here. The new grace tests live in
        // foreground_service_controller_grace_test.dart.
        playRemainingAfterEnded: playRemainingAfterEnded ?? () => false,
        graceDuration: graceDuration,
      );
    }

    test('starts foreground service when connection starts', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isRunning, isTrue);
      expect(fakeOps.lastStartTitle, 'comerune');
      expect(fakeOps.lastStartText, '接続中...');
    });

    test('uses program title when available', () async {
      titleNotifier.value = 'テスト放送';
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);

      expect(fakeOps.lastStartTitle, 'テスト放送');
    });

    test('updates notification when status changes to streaming', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);

      // Transition to streaming.
      supervisor.onSessionWsConnected();
      supervisor.onNdgrEndpointResolved();
      await Future<void>.delayed(Duration.zero);

      expect(fakeOps.lastUpdateText, 'コメント受信中');
    });

    test('stops foreground service when user stops connection', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isTrue);

      supervisor.stopByUser();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isFalse);
    });

    test('stops foreground service when broadcast ends', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      supervisor.onSessionWsConnected();
      supervisor.onNdgrEndpointResolved();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isTrue);

      supervisor.endBroadcast();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isFalse);
    });

    test('updates notification when program title changes', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isTrue);

      titleNotifier.value = '新しい番組タイトル';
      await Future<void>.delayed(Duration.zero);

      expect(fakeOps.lastUpdateTitle, '新しい番組タイトル');
    });

    test('title change is no-op when service is not running', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      titleNotifier.value = 'タイトル変更';
      await Future<void>.delayed(Duration.zero);

      expect(fakeOps.updateCallCount, 0);
    });

    test('dispose stops service and removes listeners', () async {
      final ForegroundServiceController controller = createController();

      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isTrue);

      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(manager.isRunning, isFalse);

      // Further state changes should not trigger operations.
      final int stopCount = fakeOps.stopCallCount;
      supervisor.startConnection();
      await Future<void>.delayed(Duration.zero);

      // No new stop call since listener was removed.
      expect(fakeOps.stopCallCount, stopCount);
    });

    test('shows reconnecting text during reconnection', () async {
      final ForegroundServiceController controller = createController();
      addTearDown(controller.dispose);

      supervisor.startConnection();
      supervisor.onSessionWsConnected();
      supervisor.onNdgrEndpointResolved();
      await Future<void>.delayed(Duration.zero);

      supervisor.onStreamDisconnected(ConnectionErrorCode.ndgrStreamFailed);
      await Future<void>.delayed(Duration.zero);

      expect(fakeOps.lastUpdateText, '再接続中...');
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

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {}

  @override
  Future<bool> canStart() async => true;

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
