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
          messages.add(_msg(
            id: 'm${minute}_$c',
            timestamp: base.add(Duration(minutes: minute, seconds: c)),
            userId: 'u$c',
          ));
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

  // ---------------------------------------------------------------------------
  // Regression tests for _filterDisplayable() refactoring
  //
  // Both fromMessages() and detectPeaks() delegate to the shared private
  // _filterDisplayable() method.  These tests pin the exact filter behaviour
  // so that future changes cannot silently diverge the two call-sites.
  // ---------------------------------------------------------------------------

  group('_filterDisplayable – fromMessages regression', () {
    test('gift messages are excluded from total count', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(id: '2', timestamp: base, userId: 'u2', type: AppMessageType.gift),
        _msg(id: '3', timestamp: base, userId: 'u3', type: AppMessageType.gift),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.totalComments, 1,
          reason: 'gift messages must not be counted');
    });

    test('nicoad messages are excluded from total count', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
            id: '2',
            timestamp: base,
            userId: 'u2',
            type: AppMessageType.nicoad),
        _msg(
            id: '3',
            timestamp: base,
            userId: 'u3',
            type: AppMessageType.nicoad),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.totalComments, 1,
          reason: 'nicoad messages must not be counted');
    });

    test('NG user messages are excluded from total count and unique users', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'ng1'),
        _msg(id: '2', timestamp: base, userId: 'ng2'),
        _msg(id: '3', timestamp: base, userId: 'u1'),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(
        messages,
        ngUserIds: <String>{'ng1', 'ng2'},
      );

      expect(stats.totalComments, 1,
          reason: 'NG user messages must not be counted');
      expect(stats.uniqueUserCount, 1,
          reason: 'NG users must not appear in unique user count');
    });

    test('normal chat messages are included', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(id: '2', timestamp: base, userId: 'u2'),
        _msg(id: '3', timestamp: base, userId: 'u3'),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.totalComments, 3,
          reason: 'all normal chat messages must be counted');
    });

    test('returns zero stats when message list is empty', () {
      final CommentLogStats stats =
          CommentLogStats.fromMessages(const <AppMessage>[]);

      expect(stats.totalComments, 0);
      expect(stats.uniqueUserCount, 0);
      expect(stats.duration, Duration.zero);
      expect(stats.peakMinuteLabel, isNull);
      expect(stats.peakMinuteCount, 0);
      expect(stats.commentsPerMinute, isEmpty);
    });

    test('returns zero stats when all messages are filtered out', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      // All gift, nicoad, or NG — nothing should remain after filtering.
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1', type: AppMessageType.gift),
        _msg(
            id: '2',
            timestamp: base,
            userId: 'u2',
            type: AppMessageType.nicoad),
        _msg(id: '3', timestamp: base, userId: 'ng1'),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(
        messages,
        ngUserIds: <String>{'ng1'},
      );

      expect(stats.totalComments, 0,
          reason: 'all messages were filtered; total must be 0');
      expect(stats.uniqueUserCount, 0);
      expect(stats.duration, Duration.zero);
      expect(stats.peakMinuteLabel, isNull);
      expect(stats.peakMinuteCount, 0);
      expect(stats.commentsPerMinute, isEmpty);
    });

    test('mixed message types produce correct counts', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      // 2 chat + 1 operator + 1 notification = 4 displayable
      // 2 gift + 1 nicoad + 1 NG = 4 excluded
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'), // chat  – included
        _msg(id: '2', timestamp: base, userId: 'u2'), // chat  – included
        _msg(
            id: '3',
            timestamp: base,
            userId: 'u3',
            type: AppMessageType.operator), // included
        _msg(
            id: '4',
            timestamp: base,
            userId: 'u4',
            type: AppMessageType.notification), // included
        _msg(
            id: '5',
            timestamp: base,
            userId: 'u5',
            type: AppMessageType.gift), // excluded
        _msg(
            id: '6',
            timestamp: base,
            userId: 'u6',
            type: AppMessageType.gift), // excluded
        _msg(
            id: '7',
            timestamp: base,
            userId: 'u7',
            type: AppMessageType.nicoad), // excluded
        _msg(id: '8', timestamp: base, userId: 'ng1'), // excluded (NG)
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(
        messages,
        ngUserIds: <String>{'ng1'},
      );

      expect(stats.totalComments, 4,
          reason: 'only chat/operator/notification from non-NG users counted');
      expect(stats.uniqueUserCount, 4, reason: '4 distinct displayable users');
    });

    test(
        'gift/nicoad senders are not counted as unique users even if userId set',
        () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        _msg(
            id: '2',
            timestamp: base,
            userId: 'donor1',
            type: AppMessageType.gift),
        _msg(
            id: '3',
            timestamp: base,
            userId: 'donor2',
            type: AppMessageType.nicoad),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      expect(stats.uniqueUserCount, 1,
          reason: 'gift/nicoad senders must not count as unique users');
    });
  });

  group('_filterDisplayable – detectPeaks regression', () {
    test('gift messages are excluded from representative comments', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      // Minute 0: 1 chat. Minute 5: 8 gift + 2 chat (peak).
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: 'base', timestamp: base, userId: 'u0'),
        for (int i = 0; i < 8; i++)
          _msg(
            id: 'gift$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i)),
            userId: 'donor$i',
            type: AppMessageType.gift,
          ),
        _msg(
            id: 'chat1',
            timestamp: base.add(const Duration(minutes: 5, seconds: 8)),
            userId: 'u1'),
        _msg(
            id: 'chat2',
            timestamp: base.add(const Duration(minutes: 5, seconds: 9)),
            userId: 'u2'),
      ];

      // commentsPerMinute reflects the already-filtered count (2 chat at min 5)
      // but we pass the full map that would include gifts to exercise the filter.
      final Map<int, int> cpm = <int, int>{0: 1, 5: 10};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
      );

      if (peaks.isNotEmpty) {
        for (final AppMessage msg in peaks.first.representativeComments) {
          expect(msg.type, isNot(AppMessageType.gift),
              reason:
                  'gift messages must not appear as representative comments');
        }
      }
    });

    test('nicoad messages are excluded from representative comments', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: 'base', timestamp: base, userId: 'u0'),
        for (int i = 0; i < 8; i++)
          _msg(
            id: 'nicoad$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i)),
            userId: 'donor$i',
            type: AppMessageType.nicoad,
          ),
        _msg(
            id: 'chat1',
            timestamp: base.add(const Duration(minutes: 5, seconds: 8)),
            userId: 'u1'),
        _msg(
            id: 'chat2',
            timestamp: base.add(const Duration(minutes: 5, seconds: 9)),
            userId: 'u2'),
      ];

      final Map<int, int> cpm = <int, int>{0: 1, 5: 10};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
      );

      if (peaks.isNotEmpty) {
        for (final AppMessage msg in peaks.first.representativeComments) {
          expect(msg.type, isNot(AppMessageType.nicoad),
              reason:
                  'nicoad messages must not appear as representative comments');
        }
      }
    });

    test('NG users excluded from representative comments in peaks', () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: 'base', timestamp: base, userId: 'u0'),
        for (int i = 0; i < 10; i++)
          _msg(
            id: 'p$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i)),
            userId: i < 5 ? 'ng$i' : 'u$i',
            content: 'comment $i',
          ),
      ];

      final Map<int, int> cpm = <int, int>{0: 1, 5: 10};
      final Set<String> ngIds = <String>{'ng0', 'ng1', 'ng2', 'ng3', 'ng4'};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
        ngUserIds: ngIds,
      );

      if (peaks.isNotEmpty) {
        for (final AppMessage msg in peaks.first.representativeComments) {
          expect(ngIds.contains(msg.userId), isFalse,
              reason:
                  'NG user messages must not appear in representative comments');
        }
      }
    });

    test(
        'detectPeaks consistency: same filter as fromMessages on identical input',
        () {
      // This test verifies that _filterDisplayable is truly shared: the set of
      // user IDs seen in representative comments from detectPeaks must be a
      // subset of the user IDs counted by fromMessages.
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);

      // Mix: chat (included), gift (excluded), nicoad (excluded), NG (excluded).
      final List<AppMessage> messages = <AppMessage>[
        // Minute 0: 1 chat
        _msg(id: 'c0', timestamp: base, userId: 'uA'),
        // Minute 5: 10 chat (peak)
        for (int i = 0; i < 8; i++)
          _msg(
            id: 'chat5_$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i * 5)),
            userId: 'u$i',
            content: 'peak $i',
          ),
        // Minute 5: gift – must be excluded
        _msg(
            id: 'gift5',
            timestamp: base.add(const Duration(minutes: 5, seconds: 50)),
            userId: 'donor',
            type: AppMessageType.gift),
        // Minute 5: nicoad – must be excluded
        _msg(
            id: 'nicoad5',
            timestamp: base.add(const Duration(minutes: 5, seconds: 55)),
            userId: 'ad_user',
            type: AppMessageType.nicoad),
        // Minute 5: NG user – must be excluded
        _msg(
            id: 'ng5',
            timestamp: base.add(const Duration(minutes: 5, seconds: 58)),
            userId: 'ngUser'),
      ];

      const Set<String> ngIds = <String>{'ngUser'};

      // Derive the set of displayable user IDs via fromMessages.
      final CommentLogStats stats =
          CommentLogStats.fromMessages(messages, ngUserIds: ngIds);
      // Build cpm from fromMessages result for consistency.
      final Map<int, int> cpm = stats.commentsPerMinute;

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
        ngUserIds: ngIds,
      );

      // Every representative comment's userId must not be from an excluded
      // category (gift sender, nicoad sender, NG user).
      const Set<String> excludedIds = <String>{'donor', 'ad_user', 'ngUser'};
      for (final HighlightPeak peak in peaks) {
        for (final AppMessage msg in peak.representativeComments) {
          expect(excludedIds.contains(msg.userId), isFalse,
              reason: 'detectPeaks must apply the same filter as fromMessages: '
                  'found excluded userId=${msg.userId}');
          expect(msg.type, isNot(AppMessageType.gift));
          expect(msg.type, isNot(AppMessageType.nicoad));
        }
      }
    });

    test('returns empty list when all messages are filtered (gift/nicoad/NG)',
        () {
      final DateTime base = DateTime(2026, 3, 31, 10, 0, 0);
      // All messages are excluded; filtered list will be empty.
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1', type: AppMessageType.gift),
        _msg(
            id: '2',
            timestamp: base,
            userId: 'u2',
            type: AppMessageType.nicoad),
        _msg(id: '3', timestamp: base, userId: 'ng1'),
      ];

      // Provide a non-empty cpm so the early-exit branch is not triggered.
      final Map<int, int> cpm = <int, int>{0: 3};

      final List<HighlightPeak> peaks = CommentLogStats.detectPeaks(
        messages,
        commentsPerMinute: cpm,
        ngUserIds: <String>{'ng1'},
      );

      // After filtering all messages, detectPeaks should return empty.
      expect(peaks, isEmpty,
          reason:
              'when all messages are filtered out, detectPeaks must return empty');
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
