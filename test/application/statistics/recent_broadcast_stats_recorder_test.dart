import 'package:comerune/application/statistics/recent_broadcast_stats_holder.dart';
import 'package:comerune/application/statistics/recent_broadcast_stats_recorder.dart';
import 'package:comerune/domain/comment_log/recent_broadcast_stats.dart';
import 'package:flutter_test/flutter_test.dart';

RecentBroadcastStats _snapshot({
  required String lv,
  required bool isBroadcaster,
}) {
  return RecentBroadcastStats(
    lv: lv,
    endedAt: DateTime.utc(2026, 5, 1, 12, 0),
    totalComments: 5,
    uniqueUserCount: 2,
    durationSeconds: 60,
    isBroadcaster: isBroadcaster,
  );
}

void main() {
  group('recordRecentBroadcastStatsToHolder', () {
    test('records and notifies when isBroadcaster=true and lv non-empty', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      int notifyCount = 0;
      holder.addListener(() => notifyCount++);

      final bool wrote = recordRecentBroadcastStatsToHolder(
        snapshot: _snapshot(lv: 'lv1', isBroadcaster: true),
        holder: holder,
      );

      expect(wrote, isTrue);
      expect(holder.value, isNotNull);
      expect(holder.value!.lv, 'lv1');
      expect(notifyCount, 1);
    });

    test(
      'isBroadcaster=false drops the snapshot (viewer-only sessions ignored)',
      () {
        final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
        int notifyCount = 0;
        holder.addListener(() => notifyCount++);

        final bool wrote = recordRecentBroadcastStatsToHolder(
          snapshot: _snapshot(lv: 'lv1', isBroadcaster: false),
          holder: holder,
        );

        expect(wrote, isFalse);
        expect(holder.value, isNull);
        expect(notifyCount, 0);
      },
    );

    test('empty lv drops the snapshot (defense)', () {
      final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
      final bool wrote = recordRecentBroadcastStatsToHolder(
        snapshot: _snapshot(lv: '', isBroadcaster: true),
        holder: holder,
      );

      expect(wrote, isFalse);
      expect(holder.value, isNull);
    });

    test(
      'second valid snapshot replaces the first (only 1 entry in memory)',
      () {
        final RecentBroadcastStatsHolder holder = RecentBroadcastStatsHolder();
        recordRecentBroadcastStatsToHolder(
          snapshot: _snapshot(lv: 'lv1', isBroadcaster: true),
          holder: holder,
        );
        recordRecentBroadcastStatsToHolder(
          snapshot: _snapshot(lv: 'lv2', isBroadcaster: true),
          holder: holder,
        );

        expect(holder.value!.lv, 'lv2');
      },
    );
  });
}
