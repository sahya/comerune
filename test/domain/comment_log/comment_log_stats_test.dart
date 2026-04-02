import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/comment_log/comment_log_stats.dart';
import 'package:comerune/domain/models/app_message.dart';

AppMessage _msg({
  required String id,
  required DateTime timestamp,
  String? userId,
  String content = 'test',
  AppMessageType type = AppMessageType.chat,
}) {
  return AppMessage(
    id: id,
    timestamp: timestamp,
    userId: userId,
    content: content,
    type: type,
  );
}

void main() {
  group('CommentLogStats.fromMessages', () {
    test('returns zero stats for empty list', () {
      final CommentLogStats stats = CommentLogStats.fromMessages(
        const <AppMessage>[],
      );

      expect(stats.totalComments, 0);
      expect(stats.uniqueUserCount, 0);
      expect(stats.duration, Duration.zero);
      expect(stats.peakMinuteLabel, isNull);
      expect(stats.peakMinuteCount, 0);
      expect(stats.commentsPerMinute, isEmpty);
    });

    test('counts total comments excluding gift and nicoad', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(id: '2', timestamp: base, userId: 'u2'),
        _msg(id: '3', timestamp: base, userId: 'u3', type: AppMessageType.gift),
        _msg(
          id: '4',
          timestamp: base,
          userId: 'u4',
          type: AppMessageType.nicoad,
        ),
        _msg(
          id: '5',
          timestamp: base,
          userId: 'u5',
          type: AppMessageType.operator,
        ),
        _msg(
          id: '6',
          timestamp: base,
          userId: 'u6',
          type: AppMessageType.notification,
        ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.totalComments, 4);
    });

    test('counts unique users', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(id: '2', timestamp: base, userId: 'u2'),
        _msg(id: '3', timestamp: base, userId: 'u1'),
        _msg(id: '4', timestamp: base),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.uniqueUserCount, 2);
    });

    test('calculates duration from first to last message', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
          id: '2',
          timestamp: base.add(const Duration(minutes: 30)),
          userId: 'u2',
        ),
        _msg(
          id: '3',
          timestamp: base.add(const Duration(minutes: 65)),
          userId: 'u3',
        ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.duration, const Duration(minutes: 65));
    });

    test('identifies peak minute', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        // Minute 0: 1 comment
        _msg(id: '1', timestamp: base, userId: 'u1'),
        // Minute 5: 3 comments
        _msg(
          id: '2',
          timestamp: base.add(const Duration(minutes: 5)),
          userId: 'u1',
        ),
        _msg(
          id: '3',
          timestamp: base.add(const Duration(minutes: 5, seconds: 10)),
          userId: 'u2',
        ),
        _msg(
          id: '4',
          timestamp: base.add(const Duration(minutes: 5, seconds: 30)),
          userId: 'u3',
        ),
        // Minute 10: 1 comment
        _msg(
          id: '5',
          timestamp: base.add(const Duration(minutes: 10)),
          userId: 'u1',
        ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.peakMinuteLabel, '開始5分');
      expect(stats.peakMinuteCount, 3);
    });

    test('excludes NG users', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(id: '2', timestamp: base, userId: 'blocked'),
        _msg(id: '3', timestamp: base, userId: 'u2'),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(
        messages,
        ngUserIds: <String>{'blocked'},
      );

      expect(stats.totalComments, 2);
      expect(stats.uniqueUserCount, 2);
    });

    test('handles single message', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.totalComments, 1);
      expect(stats.uniqueUserCount, 1);
      expect(stats.duration, Duration.zero);
      expect(stats.peakMinuteCount, 1);
    });

    test('builds commentsPerMinute map for reuse by graph feature', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
          id: '2',
          timestamp: base.add(const Duration(minutes: 2, seconds: 20)),
          userId: 'u2',
        ),
        _msg(
          id: '3',
          timestamp: base.add(const Duration(minutes: 2, seconds: 40)),
          userId: 'u3',
        ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.commentsPerMinute, <int, int>{0: 1, 2: 2});
    });
  });

  group('CommentLogStats.formatDuration', () {
    test('formats less than 1 minute', () {
      expect(
        CommentLogStats.formatDuration(const Duration(seconds: 30)),
        '1分未満',
      );
    });

    test('formats minutes only', () {
      expect(
        CommentLogStats.formatDuration(const Duration(minutes: 45)),
        '45分',
      );
    });

    test('formats hours only', () {
      expect(CommentLogStats.formatDuration(const Duration(hours: 2)), '2時間');
    });

    test('formats hours and minutes', () {
      expect(
        CommentLogStats.formatDuration(const Duration(hours: 1, minutes: 30)),
        '1時間30分',
      );
    });
  });

  group('CommentLogStats.detectPeaks', () {
    test('returns empty list for empty commentsPerMinute', () {
      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        const <AppMessage>[],
        commentsPerMinute: const <int, int>{},
      );

      expect(peaks, isEmpty);
    });

    test('returns empty list when all minutes have equal counts', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
          id: '2',
          timestamp: base.add(const Duration(minutes: 1)),
          userId: 'u2',
        ),
        _msg(
          id: '3',
          timestamp: base.add(const Duration(minutes: 2)),
          userId: 'u3',
        ),
        _msg(
          id: '4',
          timestamp: base.add(const Duration(minutes: 3)),
          userId: 'u4',
        ),
      ];

      // Flat distribution: stddev=0, all counts equal to mean.
      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: const <int, int>{0: 1, 1: 1, 2: 1, 3: 1},
      );

      expect(peaks, isEmpty);
    });

    test('returns empty list when no minute exceeds threshold', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
          id: '2',
          timestamp: base.add(const Duration(minutes: 1)),
          userId: 'u2',
        ),
      ];

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: const <int, int>{0: 1, 1: 1},
      );

      expect(peaks, isEmpty);
    });

    test('detects peaks above mean + stddev', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        // Minute 0: 1 comment
        _msg(id: '1', timestamp: base, userId: 'u1'),
        // Minute 5: 10 comments (peak)
        for (int i = 0; i < 10; i++)
          _msg(
            id: 'p${5}_$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i * 5)),
            userId: 'u${i % 3}',
            content: 'peak comment $i',
          ),
        // Minute 10: 2 comments
        _msg(
          id: 'a1',
          timestamp: base.add(const Duration(minutes: 10)),
          userId: 'u1',
        ),
        _msg(
          id: 'a2',
          timestamp: base.add(const Duration(minutes: 10, seconds: 10)),
          userId: 'u2',
        ),
      ];

      final Map<int, int> cpm = <int, int>{0: 1, 5: 10, 10: 2};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
      );

      expect(peaks, isNotEmpty);
      expect(peaks.first.minuteOffset, 5);
      expect(peaks.first.commentCount, 10);
      expect(peaks.first.label, '開始5分');
      expect(peaks.first.representativeComments.length, 3);
    });

    test('limits to maxPeaks', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[];
      final Map<int, int> cpm = <int, int>{};
      // Create 5 peak minutes with high counts, rest low.
      for (int minute = 0; minute < 30; minute++) {
        final int count = (minute % 6 == 0) ? 20 : 1;
        cpm[minute] = count;
        for (int c = 0; c < count; c++) {
          messages.add(
            _msg(
              id: 'm${minute}_$c',
              timestamp: base.add(Duration(minutes: minute, seconds: c)),
              userId: 'u$c',
            ),
          );
        }
      }

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
        maxPeaks: 2,
      );

      expect(peaks.length, 2);
    });

    test('excludes NG users from representative comments', () {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        for (int i = 0; i < 10; i++)
          _msg(
            id: 'p$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i)),
            userId: i == 0 ? 'blocked' : 'u${i + 1}',
            content: 'msg $i',
          ),
      ];

      final Map<int, int> cpm = <int, int>{0: 1, 5: 10};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
        ngUserIds: <String>{'blocked'},
      );

      if (peaks.isNotEmpty) {
        for (final AppMessage msg in peaks.first.representativeComments) {
          expect(msg.userId, isNot('blocked'));
        }
      }
    });
  });

  group('CommentLogStats.toShareText', () {
    test('includes program title and lv when provided', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 100,
        uniqueUserCount: 25,
        duration: const Duration(hours: 1, minutes: 30),
        peakMinuteLabel: '開始25分',
        peakMinuteCount: 15,
        commentsPerMinute: const <int, int>{25: 15},
      );

      final String text = stats.toShareText(programTitle: 'テスト配信', lv: 'lv123');

      expect(text, contains('テスト配信'));
      expect(text, contains('lv123'));
      expect(text, contains('総コメント数: 100'));
      expect(text, contains('ユニークユーザー数: 25'));
      expect(text, contains('配信時間: 1時間30分'));
      expect(text, contains('ピーク時間帯: 開始25分 (15コメント)'));
    });

    test('omits peak when count is zero', () {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 0,
        uniqueUserCount: 0,
        duration: Duration.zero,
        peakMinuteLabel: null,
        peakMinuteCount: 0,
        commentsPerMinute: const <int, int>{},
      );

      final String text = stats.toShareText();

      expect(text, isNot(contains('ピーク時間帯')));
    });
  });
}
