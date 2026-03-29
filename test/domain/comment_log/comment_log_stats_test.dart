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
      final CommentLogStats stats =
          CommentLogStats.fromMessages(const <AppMessage>[]);

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
        _msg(
          id: '3',
          timestamp: base,
          userId: 'u3',
          type: AppMessageType.gift,
        ),
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
          CommentLogStats.formatDuration(const Duration(seconds: 30)), '1分未満');
    });

    test('formats minutes only', () {
      expect(
          CommentLogStats.formatDuration(const Duration(minutes: 45)), '45分');
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
