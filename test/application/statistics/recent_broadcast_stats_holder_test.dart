import 'package:comerune/application/statistics/recent_broadcast_stats_holder.dart';
import 'package:comerune/domain/comment_log/recent_broadcast_stats.dart';
import 'package:flutter_test/flutter_test.dart';

RecentBroadcastStats _stats(
  String lv, {
  DateTime? endedAt,
  int totalComments = 5,
}) {
  return RecentBroadcastStats(
    lv: lv,
    endedAt: endedAt ?? DateTime.utc(2026, 5, 1),
    totalComments: totalComments,
    uniqueUserCount: 2,
    durationSeconds: 60,
  );
}

void main() {
  group('RecentBroadcastStatsHolder', () {
    test('starts with a null value', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      expect(holder.value, isNull);
    });

    test('update sets value and notifies listeners', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      int notifyCount = 0;
      holder.addListener(() => notifyCount++);

      holder.update(_stats('lv1'));

      expect(holder.value, isNotNull);
      expect(holder.value!.lv, 'lv1');
      expect(notifyCount, 1);
    });

    test('update replaces the existing value (only 1 entry held)', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      holder.update(_stats('lv1', totalComments: 1));
      holder.update(_stats('lv2', totalComments: 999));

      expect(holder.value!.lv, 'lv2');
      expect(holder.value!.totalComments, 999);
    });

    test('clear removes the value and notifies once', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      int notifyCount = 0;
      holder.update(_stats('lv1'));
      holder.addListener(() => notifyCount++);

      holder.clear();

      expect(holder.value, isNull);
      expect(notifyCount, 1);
    });

    test('clear when already empty does not notify (no spurious rebuilds)', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      int notifyCount = 0;
      holder.addListener(() => notifyCount++);

      holder.clear();

      expect(holder.value, isNull);
      expect(notifyCount, 0);
    });
  });
}
