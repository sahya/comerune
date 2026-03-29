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
    });

    test('recordComment increments totalCommentCount', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      expect(store.totalCommentCount, 1);

      store.recordComment(_chatMessage(id: '2', userId: 'u2'));
      expect(store.totalCommentCount, 2);
    });

    test('recordComment tracks unique active users', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      store.recordComment(_chatMessage(id: '2', userId: 'u2'));
      store.recordComment(_chatMessage(id: '3', userId: 'u1'));
      expect(store.activeUserCount, 2);
    });

    test('recordComment ignores null or empty userId for active count', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: null));
      store.recordComment(_chatMessage(id: '2', userId: ''));
      expect(store.activeUserCount, 0);
      expect(store.totalCommentCount, 2);
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
    });

    test('updateViewerCount sets viewerCount', () {
      final StatisticsStore store = StatisticsStore();

      store.updateViewerCount(42);
      expect(store.viewerCount, 42);

      store.updateViewerCount(100);
      expect(store.viewerCount, 100);
    });

    test('updateViewerCount does not notify when value unchanged', () {
      final StatisticsStore store = StatisticsStore();
      store.updateViewerCount(10);

      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.updateViewerCount(10);
      expect(notifyCount, 0);
    });

    test('reset clears all state', () {
      final StatisticsStore store = StatisticsStore();

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));
      store.updateViewerCount(50);

      store.reset();

      expect(store.totalCommentCount, 0);
      expect(store.viewerCount, isNull);
      expect(store.activeUserCount, 0);
    });

    test('notifies listeners on recordComment', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.recordComment(_chatMessage(id: '1', userId: 'u1'));

      expect(notifyCount, 1);
    });

    test('notifies listeners on updateViewerCount', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.updateViewerCount(5);

      expect(notifyCount, 1);
    });

    test('notifies listeners on reset', () {
      final StatisticsStore store = StatisticsStore();
      int notifyCount = 0;
      store.addListener(() => notifyCount += 1);

      store.reset();

      expect(notifyCount, 1);
    });
  });
}
