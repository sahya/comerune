import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/foreground_service/foreground_service_controller.dart';
import 'package:comerune/data/foreground_service/foreground_service_manager.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';

/// Issue #739 — broadcast-end grace period for the FGS lifecycle.
///
/// The original [ForegroundServiceController] behaviour was "stop
/// immediately on `ConnectionStatus.ended`". This file verifies the new
/// gated behaviour:
/// - `ended` + grace ON → defer FGS stop for 30 s.
/// - `ended` + grace OFF → unchanged (stop now).
/// - `failed` / `stopped` → always stop now.
/// - reconnect during grace → cancel the timer.
void main() {
  group('ForegroundServiceController grace (#739)', () {
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

    ForegroundServiceController build({
      required bool grace,
      Duration graceDuration = const Duration(seconds: 30),
    }) {
      return ForegroundServiceController(
        foregroundServiceManager: manager,
        connectionSupervisor: supervisor,
        programTitleNotifier: titleNotifier,
        playRemainingAfterEnded: () => grace,
        graceDuration: graceDuration,
      );
    }

    Future<void> driveToStreaming() async {
      supervisor.startConnection();
      supervisor.onSessionWsConnected();
      supervisor.onNdgrEndpointResolved();
      await Future<void>.delayed(Duration.zero);
    }

    test('ended with grace ON does not stop FGS immediately', () async {
      final ForegroundServiceController controller = build(grace: true);
      addTearDown(controller.dispose);

      await driveToStreaming();
      expect(manager.isRunning, isTrue);

      expect(supervisor.endBroadcast(), isTrue);
      await Future<void>.delayed(Duration.zero);

      // The FGS must keep running until grace expires or the queue drains.
      expect(manager.isRunning, isTrue);
      expect(controller.isInGrace, isTrue);
      // The notification text reflects the transitional state so users see
      // why TTS keeps going for a few seconds after the broadcast ends.
      expect(fakeOps.lastUpdateText, '読み上げ完了待ち...');
    });

    test('grace timer fires and stops FGS after 30s', () {
      fakeAsync((FakeAsync async) {
        final ForegroundServiceController controller = build(grace: true);
        addTearDown(controller.dispose);

        supervisor.startConnection();
        supervisor.onSessionWsConnected();
        supervisor.onNdgrEndpointResolved();
        async.flushMicrotasks();
        expect(manager.isRunning, isTrue);

        supervisor.endBroadcast();
        async.flushMicrotasks();
        expect(manager.isRunning, isTrue);

        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        expect(
          manager.isRunning,
          isTrue,
          reason: 'FGS must still be alive within the grace window',
        );

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(manager.isRunning, isFalse);
        expect(controller.isInGrace, isFalse);
      });
    });

    test(
      'reconnect during grace cancels the timer (manager.stop NOT called)',
      () {
        fakeAsync((FakeAsync async) {
          final ForegroundServiceController controller = build(grace: true);
          addTearDown(controller.dispose);

          supervisor.startConnection();
          supervisor.onSessionWsConnected();
          supervisor.onNdgrEndpointResolved();
          async.flushMicrotasks();
          final int stopBefore = fakeOps.stopCallCount;

          supervisor.endBroadcast();
          async.flushMicrotasks();
          expect(controller.isInGrace, isTrue);

          // Grace in progress — drive a reconnect transition. From `ended`
          // ConnectionSupervisor permits going back to `connectingSessionWs`
          // via startConnection().
          async.elapse(const Duration(seconds: 5));
          supervisor.startConnection();
          async.flushMicrotasks();
          expect(
            controller.isInGrace,
            isFalse,
            reason: 'Reconnect must cancel the grace timer.',
          );

          // Let the original 30s window pass — no extra stop call may fire.
          async.elapse(const Duration(seconds: 60));
          async.flushMicrotasks();
          expect(fakeOps.stopCallCount, stopBefore);
          // FGS is still running on the new (re)connection.
          expect(manager.isRunning, isTrue);
        });
      },
    );

    test('failed always stops FGS immediately, even with grace ON', () async {
      final ForegroundServiceController controller = build(grace: true);
      addTearDown(controller.dispose);

      await driveToStreaming();
      expect(manager.isRunning, isTrue);

      // ConnectionSupervisor exposes `fail()` as the public failure entry
      // point — drive it directly so the test does not depend on the
      // reconnect/exhaustion path.
      supervisor.fail(ConnectionErrorCode.ndgrStreamFailed);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isRunning, isFalse);
      expect(controller.isInGrace, isFalse);
    });

    test(
      'manual stop always stops FGS immediately, even with grace ON',
      () async {
        final ForegroundServiceController controller = build(grace: true);
        addTearDown(controller.dispose);

        await driveToStreaming();
        expect(manager.isRunning, isTrue);

        supervisor.stopByUser();
        await Future<void>.delayed(Duration.zero);

        expect(manager.isRunning, isFalse);
        expect(controller.isInGrace, isFalse);
      },
    );

    test('grace OFF behaves like the legacy "ended → stop now"', () async {
      final ForegroundServiceController controller = build(grace: false);
      addTearDown(controller.dispose);

      await driveToStreaming();
      expect(manager.isRunning, isTrue);

      supervisor.endBroadcast();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isRunning, isFalse);
      expect(controller.isInGrace, isFalse);
    });

    test('notifyQueueDrained ends grace early', () {
      fakeAsync((FakeAsync async) {
        final ForegroundServiceController controller = build(grace: true);
        addTearDown(controller.dispose);

        supervisor.startConnection();
        supervisor.onSessionWsConnected();
        supervisor.onNdgrEndpointResolved();
        async.flushMicrotasks();

        supervisor.endBroadcast();
        async.flushMicrotasks();
        expect(controller.isInGrace, isTrue);

        async.elapse(const Duration(seconds: 5));
        controller.notifyQueueDrained();
        async.flushMicrotasks();

        expect(controller.isInGrace, isFalse);
        expect(manager.isRunning, isFalse);
      });
    });

    test('dispose during grace cancels the timer cleanly', () {
      fakeAsync((FakeAsync async) {
        final ForegroundServiceController controller = build(grace: true);

        supervisor.startConnection();
        supervisor.onSessionWsConnected();
        supervisor.onNdgrEndpointResolved();
        async.flushMicrotasks();

        supervisor.endBroadcast();
        async.flushMicrotasks();
        expect(controller.isInGrace, isTrue);

        controller.dispose();
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();

        // No exception, no extra timer fires, manager is stopped exactly
        // once (the dispose-driven stop).
        expect(manager.isRunning, isFalse);
      });
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
    NotificationIcon? notificationIcon,
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
