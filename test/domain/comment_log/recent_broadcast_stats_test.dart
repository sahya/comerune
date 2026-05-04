import 'package:comerune/domain/comment_log/comment_log_stats.dart';
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

  group('RecentBroadcastStats.resolvePeakMinuteOffset', () {
    test('returns null when peakMinuteCount is 0', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 0,
        uniqueUserCount: 0,
        duration: Duration.zero,
        peakMinuteLabel: null,
        peakMinuteCount: 0,
        commentsPerMinute: const <int, int>{},
      );
      expect(RecentBroadcastStats.resolvePeakMinuteOffset(stats), isNull);
    });

    test('returns null when peakMinuteLabel is null', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 1,
        uniqueUserCount: 1,
        duration: const Duration(minutes: 1),
        peakMinuteLabel: null,
        peakMinuteCount: 5,
        commentsPerMinute: const <int, int>{0: 5},
      );
      expect(RecentBroadcastStats.resolvePeakMinuteOffset(stats), isNull);
    });

    test('returns the smallest minute key matching peakMinuteCount', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 12,
        uniqueUserCount: 4,
        duration: const Duration(minutes: 25),
        peakMinuteLabel: '開始3分',
        peakMinuteCount: 5,
        commentsPerMinute: const <int, int>{20: 5, 3: 5, 1: 2},
      );
      expect(RecentBroadcastStats.resolvePeakMinuteOffset(stats), 3);
    });

    test('handles single peak minute correctly', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 10,
        uniqueUserCount: 4,
        duration: const Duration(minutes: 30),
        peakMinuteLabel: '開始10分',
        peakMinuteCount: 5,
        commentsPerMinute: const <int, int>{0: 1, 5: 2, 10: 5, 20: 2},
      );
      expect(RecentBroadcastStats.resolvePeakMinuteOffset(stats), 10);
    });
  });

  group('RecentBroadcastStats.== / hashCode', () {
    RecentBroadcastStats build({
      String lv = 'lv1',
      int totalComments = 5,
      bool isBroadcaster = true,
    }) {
      return RecentBroadcastStats(
        lv: lv,
        endedAt: DateTime.utc(2026, 5, 1, 12, 0),
        totalComments: totalComments,
        uniqueUserCount: 2,
        durationSeconds: 60,
        programTitle: 'タイトル',
        beginAt: DateTime.utc(2026, 5, 1, 11, 50),
        peakMinuteOffset: 5,
        peakMinuteCount: 3,
        peakMinuteLabel: '開始5分',
        isBroadcaster: isBroadcaster,
      );
    }

    test('equal instances compare equal and have the same hashCode', () {
      final RecentBroadcastStats a = build();
      final RecentBroadcastStats b = build();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('differing field makes instances unequal', () {
      expect(build(), isNot(equals(build(lv: 'lv2'))));
      expect(build(), isNot(equals(build(totalComments: 99))));
      expect(build(), isNot(equals(build(isBroadcaster: false))));
    });

    test('identical references are equal', () {
      final RecentBroadcastStats a = build();
      expect(a == a, isTrue);
    });
  });
}
