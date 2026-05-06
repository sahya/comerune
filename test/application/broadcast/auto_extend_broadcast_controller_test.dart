import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/broadcast/auto_extend_broadcast_controller.dart';
import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('AutoExtendBroadcastController', () {
    test('does nothing when disabled', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final List<AppMessage> emitted = <AppMessage>[];
        final List<DateTime> updatedEnds = <DateTime>[];
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: emitted.add,
              onEndTimeUpdated: updatedEnds.add,
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(DateTime.utc(2026, 1, 1, 12)).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: false,
          programId: 'lv1',
          userSession: 'sess',
          endAt: DateTime.utc(2026, 1, 1, 12, 30),
        );

        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();

        expect(repo.calls, isEmpty);
        expect(emitted, isEmpty);
        expect(updatedEnds, isEmpty);
        expect(controller.hasScheduledTimerForTesting, isFalse);
      });
    });

    test('schedules timer for endAt - threshold and fires extendBroadcast', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final List<AppMessage> emitted = <AppMessage>[];
        final List<DateTime> updatedEnds = <DateTime>[];
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: emitted.add,
              onEndTimeUpdated: updatedEnds.add,
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        // endAt 30 min away → fire at endAt - 5min = now + 25 min.
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );

        // Just before fire — no API call yet.
        async.elapse(const Duration(minutes: 24, seconds: 59));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);

        // Cross the threshold — Timer fires once, extendBroadcast is
        // called once with the configured 30 minutes default.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(1));
        expect(repo.calls.single.programId, 'lv1');
        expect(repo.calls.single.userSession, 'sess');
        expect(repo.calls.single.minutes, 30);
      });
    });

    test('success: emits success message and bubbles new endAt upstream', () {
      fakeAsync((FakeAsync async) {
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final DateTime newEndAt = now.add(const Duration(minutes: 60));
        final int newEndAtSec = newEndAt.millisecondsSinceEpoch ~/ 1000;
        final _RecordingRepository repo = _RecordingRepository(
          responder: (_, _, _) async =>
              BroadcastControlResult(success: true, endTime: newEndAtSec),
        );
        final List<AppMessage> emitted = <AppMessage>[];
        final List<DateTime> updatedEnds = <DateTime>[];
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: emitted.add,
              onEndTimeUpdated: updatedEnds.add,
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        async.elapse(const Duration(minutes: 25));
        async.flushMicrotasks();

        expect(updatedEnds, hasLength(1));
        // The upstream endAt is the server's authoritative value.
        expect(updatedEnds.single.millisecondsSinceEpoch ~/ 1000, newEndAtSec);
        expect(emitted, hasLength(1));
        expect(emitted.single.type, AppMessageType.notification);
        expect(
          emitted.single.id.startsWith(kSystemAutoExtendSuccessMessageIdPrefix),
          isTrue,
        );
        expect(emitted.single.content, contains('+30 分'));
      });
    });

    test('failure: retries up to maxRetries, then emits failure message', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository(
          responder: (_, _, _) async => const BroadcastControlResult(
            success: false,
            errorCode: BroadcastControlErrorCode.networkError,
          ),
        );
        final List<AppMessage> emitted = <AppMessage>[];
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: emitted.add,
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        // Cross the threshold — first attempt runs.
        async.elapse(const Duration(minutes: 25));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(1));
        expect(emitted, isEmpty);

        // After 30s backoff, second attempt runs. Default config retries
        // up to 6 times with 30 s spacing — verify the cadence of the
        // first few intervals to pin the schedule, then jump to the
        // final retry to assert the failure message arrives at attempt
        // 6 (and not earlier or later).
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(2));
        expect(emitted, isEmpty);

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(3));
        expect(emitted, isEmpty);

        // Skip ahead through retries 4 and 5 — still no failure message.
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(5));
        expect(emitted, isEmpty);

        // Sixth (final) attempt fires after another 30 s; failure
        // message is emitted only once attempt 6 returns.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(6));
        expect(emitted, hasLength(1));
        expect(
          emitted.single.id.startsWith(kSystemAutoExtendFailureMessageIdPrefix),
          isTrue,
        );
      });
    });

    test(
      'all retries failed leaves the controller idle (no Switch toggle)',
      () {
        // Verify the AC: 「リトライ全失敗でも Switch は OFF にしない」.
        // The controller does not flip its `_enabled` state — that is the
        // host's concern. We assert that no further extendBroadcast call
        // is made until the host re-arms by calling [update] again.
        fakeAsync((FakeAsync async) {
          final _RecordingRepository repo = _RecordingRepository(
            responder: (_, _, _) async => const BroadcastControlResult(
              success: false,
              errorCode: BroadcastControlErrorCode.networkError,
            ),
          );
          final List<AppMessage> emitted = <AppMessage>[];
          final DateTime now = DateTime.utc(2026, 1, 1, 12);
          final AutoExtendBroadcastController controller =
              AutoExtendBroadcastController(
                repository: repo,
                emitMessage: emitted.add,
                onEndTimeUpdated: (_) {},
                successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
                failureMessage: '自動延長に失敗しました',
                clock: () => async.getClock(now).now(),
              );
          addTearDown(controller.dispose);

          controller.update(
            enabled: true,
            programId: 'lv1',
            userSession: 'sess',
            endAt: now.add(const Duration(minutes: 30)),
          );
          // Cross the threshold + drain all 6 retries (5 backoff
          // windows of 30 s each = 150 s after the first attempt).
          async.elapse(const Duration(minutes: 30));
          async.flushMicrotasks();
          // After all 6 retries:
          expect(repo.calls, hasLength(6));
          expect(emitted, hasLength(1));

          // Wait another hour — no further attempts. The controller is
          // idle until the host pushes a new endAt or toggles off/on.
          async.elapse(const Duration(hours: 1));
          async.flushMicrotasks();
          expect(repo.calls, hasLength(6));
        });
      },
    );

    test('disable cancels any scheduled timer', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        expect(controller.hasScheduledTimerForTesting, isTrue);

        controller.update(
          enabled: false,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        expect(controller.hasScheduledTimerForTesting, isFalse);

        // No firing even after the original threshold time.
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);
      });
    });

    test('endAt update reschedules the timer', () {
      // Mimics the manual-extend feedback loop: host updates endAt,
      // controller re-schedules.
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );

        // Host extends manually → endAt pushed forward to now + 60min.
        async.elapse(const Duration(minutes: 10));
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 60)),
        );

        // Original fire time (now + 25min) is in 15min from "now+10".
        // It must NOT fire because the timer was rescheduled to
        // (now+60 - 5min) = now + 55 min, which is 45 min from "now+10".
        async.elapse(const Duration(minutes: 16));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);

        // Reach the new fire time.
        async.elapse(const Duration(minutes: 30));
        async.flushMicrotasks();
        expect(repo.calls, hasLength(1));
      });
    });

    test('past threshold endAt fires immediately', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        // endAt is 1 minute away — already past the 5-min threshold.
        // Fire is dispatched as a zero-delay Timer.
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 1)),
        );
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(repo.calls, hasLength(1));
      });
    });

    test('pause cancels timer; resume re-schedules', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        expect(controller.hasScheduledTimerForTesting, isTrue);

        controller.pause();
        expect(controller.hasScheduledTimerForTesting, isFalse);

        // Even past the threshold, paused controller does not fire.
        async.elapse(const Duration(minutes: 30));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);

        // Resume — already past threshold so it fires immediately.
        controller.resume();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(repo.calls, hasLength(1));
      });
    });

    test('dispose cancels in-flight timer and prevents future calls', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        controller.dispose();

        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);

        // Re-call after dispose is silently ignored — no scheduling.
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 1)),
        );
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);
      });
    });

    test('null endAt or empty programId/userSession skips scheduling', () {
      fakeAsync((FakeAsync async) {
        final _RecordingRepository repo = _RecordingRepository();
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: (_) {},
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        // No endAt yet (FollowProgram still loading).
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: null,
        );
        expect(controller.hasScheduledTimerForTesting, isFalse);

        // No session yet.
        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: '',
          endAt: now.add(const Duration(minutes: 30)),
        );
        expect(controller.hasScheduledTimerForTesting, isFalse);

        // No programId.
        controller.update(
          enabled: true,
          programId: '',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        expect(controller.hasScheduledTimerForTesting, isFalse);

        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();
        expect(repo.calls, isEmpty);
      });
    });

    test('repository throwing is treated as a failed attempt', () {
      // Defensive: anything escaping the repository (Error subtypes,
      // host-side state mutation throwing in tests) must not crash the
      // retry chain — it should retry like any other failure.
      fakeAsync((FakeAsync async) {
        int callCount = 0;
        final _RecordingRepository repo = _RecordingRepository(
          responder: (_, _, _) async {
            callCount += 1;
            throw StateError('boom #$callCount');
          },
        );
        final List<AppMessage> emitted = <AppMessage>[];
        final DateTime now = DateTime.utc(2026, 1, 1, 12);
        final AutoExtendBroadcastController controller =
            AutoExtendBroadcastController(
              repository: repo,
              emitMessage: emitted.add,
              onEndTimeUpdated: (_) {},
              successMessageBuilder: (int m) => '自動延長が成功しました（+$m 分）',
              failureMessage: '自動延長に失敗しました',
              clock: () => async.getClock(now).now(),
            );
        addTearDown(controller.dispose);

        controller.update(
          enabled: true,
          programId: 'lv1',
          userSession: 'sess',
          endAt: now.add(const Duration(minutes: 30)),
        );
        async.elapse(const Duration(minutes: 30));
        async.flushMicrotasks();

        // All 6 attempts ran; failure message emitted.
        expect(repo.calls, hasLength(6));
        expect(emitted, hasLength(1));
        expect(
          emitted.single.id.startsWith(kSystemAutoExtendFailureMessageIdPrefix),
          isTrue,
        );
      });
    });
  });
}

/// Records every `extendBroadcast` invocation and lets tests pre-seed a
/// [responder] to control the result. Other inherited HTTP methods stay
/// at their base-class implementations because we only exercise
/// `extendBroadcast` from this controller.
class _RecordingRepository extends BroadcastControlRepository {
  _RecordingRepository({this.responder});

  final Future<BroadcastControlResult> Function(
    String programId,
    String userSession,
    int minutes,
  )?
  responder;

  final List<({String programId, String userSession, int minutes})> calls =
      <({String programId, String userSession, int minutes})>[];

  @override
  Future<BroadcastControlResult> extendBroadcast({
    required String programId,
    required String userSession,
    int minutes = 30,
  }) async {
    calls.add((
      programId: programId,
      userSession: userSession,
      minutes: minutes,
    ));
    return responder?.call(programId, userSession, minutes) ??
        const BroadcastControlResult(success: true);
  }
}
