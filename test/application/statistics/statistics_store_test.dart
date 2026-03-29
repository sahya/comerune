import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/statistics/statistics_store.dart';

void main() {
  group('StatisticsStore', () {
    test('initial values are zero', () {
      final StatisticsStore store = StatisticsStore();

      expect(store.viewerCount, 0);
      expect(store.totalCommentCount, 0);
      expect(store.activeUserCount, 0);
    });

    test('updateViewerCount updates and notifies', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount++);

      store.updateViewerCount(42);

      expect(store.viewerCount, 42);
      expect(notifyCount, 1);
    });

    test('updateViewerCount does not notify when value unchanged', () {
      final StatisticsStore store = StatisticsStore();
      store.updateViewerCount(10);

      int notifyCount = 0;
      store.addListener(() => notifyCount++);

      store.updateViewerCount(10);

      expect(notifyCount, 0);
    });

    test('recordComment increments totalCommentCount', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(userId: 'user1');
      store.recordComment(userId: 'user2');
      store.recordComment();

      expect(store.totalCommentCount, 3);
    });

    test('recordComment tracks active users within window', () {
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(userId: 'user1');
      fakeNow = DateTime(2026, 1, 1, 12, 1, 0);
      store.recordComment(userId: 'user2');
      fakeNow = DateTime(2026, 1, 1, 12, 2, 0);
      store.recordComment(userId: 'user1');

      expect(store.activeUserCount, 2);
    });

    test('active users expire after window elapses', () {
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(userId: 'user1');
      fakeNow = DateTime(2026, 1, 1, 12, 3, 0);
      store.recordComment(userId: 'user2');

      // Advance past user1's window
      fakeNow = DateTime(2026, 1, 1, 12, 6, 0);
      expect(store.activeUserCount, 1);
    });

    test('all users expire when window fully elapses', () {
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(userId: 'user1');
      store.recordComment(userId: 'user2');

      fakeNow = DateTime(2026, 1, 1, 12, 10, 0);
      expect(store.activeUserCount, 0);
    });

    test('null or empty userId is not tracked as active', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment();
      store.recordComment(userId: '');

      expect(store.totalCommentCount, 2);
      expect(store.activeUserCount, 0);
    });

    test('clear resets all counters', () {
      final StatisticsStore store = StatisticsStore();

      store.updateViewerCount(10);
      store.recordComment(userId: 'user1');
      store.recordComment(userId: 'user2');

      store.clear();

      expect(store.viewerCount, 0);
      expect(store.totalCommentCount, 0);
      expect(store.activeUserCount, 0);
    });

    test('user with renewed activity stays active after old activity expires',
        () {
      DateTime fakeNow = DateTime(2026, 1, 1, 12, 0, 0);
      final StatisticsStore store = StatisticsStore(
        activeWindow: const Duration(minutes: 5),
        now: () => fakeNow,
      );

      store.recordComment(userId: 'user1');

      // user1 comments again at 3 minutes
      fakeNow = DateTime(2026, 1, 1, 12, 3, 0);
      store.recordComment(userId: 'user1');

      // At 6 minutes, old activity expired but user1 has recent activity
      fakeNow = DateTime(2026, 1, 1, 12, 6, 0);
      expect(store.activeUserCount, 1);
    });
  });
}
