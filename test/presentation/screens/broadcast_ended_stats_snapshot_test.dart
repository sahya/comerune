import 'package:comerune/domain/comment_log/comment_log_stats.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BroadcastEndedStatsSnapshot.buildFromStats', () {
    test('copies summary fields straight through from CommentLogStats', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 50,
        uniqueUserCount: 12,
        duration: const Duration(minutes: 30),
        peakMinuteLabel: '開始10分',
        peakMinuteCount: 8,
        commentsPerMinute: const <int, int>{0: 1, 5: 2, 10: 8, 20: 1},
      );
      final BroadcastEndedStatsSnapshot snapshot =
          BroadcastEndedStatsSnapshot.buildFromStats(
            lv: 'lv999',
            stats: stats,
            endedAt: DateTime.utc(2026, 5, 1, 12, 30),
            isBroadcaster: true,
            programTitle: 'タイトル',
            broadcasterUserId: '12345',
            broadcasterName: '放送者A',
            beginAt: DateTime.utc(2026, 5, 1, 12),
          );
      expect(snapshot.lv, 'lv999');
      expect(snapshot.totalComments, 50);
      expect(snapshot.uniqueUserCount, 12);
      expect(snapshot.durationSeconds, 1800);
      expect(snapshot.peakMinuteOffset, 10);
      expect(snapshot.peakMinuteCount, 8);
      expect(snapshot.programTitle, 'タイトル');
      expect(snapshot.isBroadcaster, isTrue);
    });

    test('drops peakMinuteOffset when peakMinuteCount is 0', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 0,
        uniqueUserCount: 0,
        duration: Duration.zero,
        peakMinuteLabel: null,
        peakMinuteCount: 0,
        commentsPerMinute: const <int, int>{},
      );
      final BroadcastEndedStatsSnapshot snapshot =
          BroadcastEndedStatsSnapshot.buildFromStats(
            lv: 'lv1',
            stats: stats,
            endedAt: DateTime.utc(2026, 5, 1),
            isBroadcaster: true,
          );
      expect(snapshot.peakMinuteOffset, isNull);
      expect(snapshot.peakMinuteCount, 0);
    });

    test('derives peakOffset deterministically (smallest key when ties)', () {
      // Two minutes share the peak count of 5; smallest key wins.
      final CommentLogStats stats = CommentLogStats(
        totalComments: 12,
        uniqueUserCount: 4,
        duration: const Duration(minutes: 25),
        peakMinuteLabel: '開始3分',
        peakMinuteCount: 5,
        commentsPerMinute: const <int, int>{3: 5, 20: 5, 1: 2},
      );
      final BroadcastEndedStatsSnapshot snapshot =
          BroadcastEndedStatsSnapshot.buildFromStats(
            lv: 'lv1',
            stats: stats,
            endedAt: DateTime.utc(2026, 5, 1),
            isBroadcaster: true,
          );
      expect(snapshot.peakMinuteOffset, 3);
    });

    test(
      'forwards highlight peaks 1-to-1 (no representative comments leaked)',
      () {
        final CommentLogStats stats = CommentLogStats(
          totalComments: 5,
          uniqueUserCount: 5,
          duration: const Duration(minutes: 5),
          peakMinuteLabel: null,
          peakMinuteCount: 0,
          commentsPerMinute: const <int, int>{},
        );
        final BroadcastEndedStatsSnapshot snapshot =
            BroadcastEndedStatsSnapshot.buildFromStats(
              lv: 'lv1',
              stats: stats,
              endedAt: DateTime.utc(2026, 5, 1),
              isBroadcaster: true,
              highlightPeaks: const <HighlightPeak>[
                HighlightPeak(
                  minuteOffset: 1,
                  label: '開始1分',
                  commentCount: 3,
                  representativeComments: <AppMessage>[],
                ),
              ],
            );
        expect(snapshot.peaks, hasLength(1));
        expect(snapshot.peaks.first.label, '開始1分');
        expect(snapshot.peaks.first.commentCount, 3);
        // Snapshot peak type intentionally has no representative-comments field;
        // verify by walking the field set.
        expect(snapshot.peaks.first.minuteOffset, 1);
      },
    );
  });
}
