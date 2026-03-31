import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/statistics/statistics_store.dart';
import 'package:comerune/domain/models/app_message.dart';

AppMessage _chatMessage({
  required String id,
  String? userId,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime.parse('2026-03-29T12:00:00Z'),
    userId: userId,
    content: 'hello',
    type: AppMessageType.chat,
  );
}

void main() {
  group('StatisticsStore', () {
    test('initial state has zero counts and null viewerCount', () {
      final StatisticsStore store = StatisticsStore();

      expect(store.totalCommentCount, 0);
      expect(store.viewerCount, isNull);
      expect(store.activeUserCount, 0);

      store.dispose();
    });

    test('recordComment increments totalCommentCount', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      expect(store.totalCommentCount, 1);

      store.recordComment(_chatMessage(id: '2', userId: 'u2'));
      expect(store.totalCommentCount, 2);

      store.dispose();
    });

    test('recordComment tracks unique active users', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      store.recordComment(_chatMessage(id: '2', userId: 'u2'));
      store.recordComment(_chatMessage(id: '3', userId: 'u1'));
      expect(store.activeUserCount, 2);

      store.dispose();
    });

    test('recordComment ignores null or empty userId for active count', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: null));
      store.recordComment(_chatMessage(id: '2', userId: ''));
      expect(store.activeUserCount, 0);
      expect(store.totalCommentCount, 2);

      store.dispose();
    });

    test('activeUserCount prunes entries outside the window', () {
      DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      expect(store.activeUserCount, 1);

      // Move time forward by 6 minutes.
      fakeNow = fakeNow.add(const Duration(minutes: 6));
      expect(store.activeUserCount, 0);

      store.dispose();
    });

    test('all users expire when window fully elapses', () {
      DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      store.recordComment(_chatMessage(id: '2', userId: 'u2'));

      fakeNow = fakeNow.add(const Duration(minutes: 10));
      expect(store.activeUserCount, 0);

      store.dispose();
    });

    test('user with renewed activity stays active after old activity expires',
        () {
      DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));

      // u1 comments again at 3 minutes
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      store.recordComment(_chatMessage(id: '2', userId: 'u1'));

      // At 6 minutes, old activity expired but u1 has recent activity
      fakeNow = fakeNow.add(const Duration(minutes: 3));
      expect(store.activeUserCount, 1);

      store.dispose();
    });

    test('updateViewerCount sets viewerCount', () {
      final StatisticsStore store = StatisticsStore();

      store.updateViewerCount(42);
      expect(store.viewerCount, 42);

      store.updateViewerCount(100);
      expect(store.viewerCount, 100);

      store.dispose();
    });

    test('updateViewerCount does not notify when value unchanged', () {
      final StatisticsStore store = StatisticsStore();
      store.updateViewerCount(10);

      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.updateViewerCount(10);
      expect(notifyCount, 0);

      store.dispose();
    });

    test('reset clears all state', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      store.updateViewerCount(50);

      store.reset();

      expect(store.totalCommentCount, 0);
      expect(store.viewerCount, isNull);
      expect(store.activeUserCount, 0);

      store.dispose();
    });

    test('notifies listeners on recordComment', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));

      expect(notifyCount, 1);

      store.dispose();
    });

    test('notifies listeners on updateViewerCount', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.updateViewerCount(5);

      expect(notifyCount, 1);

      store.dispose();
    });

    test('notifies listeners on reset', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.reset();

      expect(notifyCount, 1);

      store.dispose();
    });
  });

  group('StatisticsStore purge timer', () {
    test('purge timer notifies listeners when users expire', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));
        expect(store.activeUserCount, 1);

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        // Advance time past active window, then let the timer tick.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 30));

        expect(notifyCount, 1);
        expect(store.activeUserCount, 0);

        store.dispose();
      });
    });

    test('purge timer does not notify when no users expire', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        // Advance timer but not past the window.
        fakeNow = fakeNow.add(const Duration(minutes: 2));
        async.elapse(const Duration(seconds: 30));

        expect(notifyCount, 0);
        expect(store.activeUserCount, 1);

        store.dispose();
      });
    });

    test('purge timer stops when all users have expired', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        // Expire all users.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 30));
        expect(notifyCount, 1);

        // Further ticks should not produce notifications (timer stopped).
        async.elapse(const Duration(seconds: 60));
        expect(notifyCount, 1);

        store.dispose();
      });
    });

    test('purge timer restarts after new comment following full expiry', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));

        // Expire all users.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 30));
        expect(store.activeUserCount, 0);

        // New comment should restart the timer.
        fakeNow = fakeNow.add(const Duration(seconds: 1));
        store.recordComment(_chatMessage(id: '2', userId: 'u2'));
        expect(store.activeUserCount, 1);

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 30));

        expect(notifyCount, 1);
        expect(store.activeUserCount, 0);

        store.dispose();
      });
    });

    test('dispose cancels purge timer', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));
        store.dispose();

        // Elapsing time after dispose should not throw or notify.
        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 60));
        // If we get here without error, dispose properly cancelled the timer.
      });
    });

    test('reset cancels purge timer', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));
        store.reset();

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        fakeNow = fakeNow.add(const Duration(minutes: 6));
        async.elapse(const Duration(seconds: 60));

        // Timer was cancelled by reset, so no notifications.
        expect(notifyCount, 0);

        store.dispose();
      });
    });

    test('purge timer expires users gradually across ticks', () {
      fakeAsync((FakeAsync async) {
        DateTime fakeNow = DateTime.parse('2026-03-29T12:00:00Z');
        final StatisticsStore store = StatisticsStore(
          activeWindow: const Duration(minutes: 5),
          purgeInterval: const Duration(seconds: 30),
          now: () => fakeNow,
        );

        store.recordComment(_chatMessage(id: '1', userId: 'u1'));

        fakeNow = fakeNow.add(const Duration(minutes: 3));
        store.recordComment(_chatMessage(id: '2', userId: 'u2'));

        int notifyCount = 0;
        store.addListener(() => notifyCount += 1);

        // At 5.5 min: u1 expired, u2 still active.
        fakeNow = fakeNow.add(const Duration(minutes: 2, seconds: 30));
        async.elapse(const Duration(seconds: 30));

        expect(notifyCount, 1);
        expect(store.activeUserCount, 1);

        // At 8.5 min: u2 also expired.
        fakeNow = fakeNow.add(const Duration(minutes: 3));
        async.elapse(const Duration(seconds: 30));

        expect(notifyCount, 2);
        expect(store.activeUserCount, 0);

        store.dispose();
      });
    });
  });
}
