import 'package:comerune/domain/comment_log/recent_broadcast_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecentBroadcastStats', () {
    test('duration getter mirrors durationSeconds', () {
      final RecentBroadcastStats stats = RecentBroadcastStats(
        lv: 'lv1',
        endedAt: DateTime.utc(2026, 5, 1),
        totalComments: 0,
        uniqueUserCount: 0,
        durationSeconds: 1800,
      );
      expect(stats.duration, const Duration(seconds: 1800));
      expect(stats.duration, const Duration(minutes: 30));
    });

    test('all metadata fields default to null where appropriate', () {
      final RecentBroadcastStats stats = RecentBroadcastStats(
        lv: 'lv1',
        endedAt: DateTime.utc(2026, 5, 1),
        totalComments: 0,
        uniqueUserCount: 0,
        durationSeconds: 0,
      );
      expect(stats.programTitle, isNull);
      expect(stats.beginAt, isNull);
      expect(stats.peakMinuteOffset, isNull);
      expect(stats.peakMinuteCount, 0);
      expect(stats.peakMinuteLabel, isNull);
    });
  });
}
