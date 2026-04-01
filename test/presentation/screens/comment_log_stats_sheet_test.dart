import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/comment_log/comment_log_stats.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_log_stats_sheet.dart';

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
  group('CommentLogStatsSheet', () {
    testWidgets('displays all stat rows', (WidgetTester tester) async {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 150,
        uniqueUserCount: 42,
        duration: const Duration(hours: 1, minutes: 30),
        peakMinuteLabel: '開始25分',
        peakMinuteCount: 18,
        commentsPerMinute: const <int, int>{25: 18},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                        programTitle: 'テスト配信',
                        lv: 'lv123',
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('1時間30分'), findsOneWidget);
      expect(find.text('開始25分 (18コメント)'), findsOneWidget);
    });

    testWidgets('hides peak row when no peak data', (
      WidgetTester tester,
    ) async {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 0,
        uniqueUserCount: 0,
        duration: Duration.zero,
        peakMinuteLabel: null,
        peakMinuteCount: 0,
        commentsPerMinute: const <int, int>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stats-peak')), findsNothing);
    });

    testWidgets('copy button copies text to clipboard', (
      WidgetTester tester,
    ) async {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 10,
        uniqueUserCount: 5,
        duration: const Duration(minutes: 15),
        peakMinuteLabel: '開始5分',
        peakMinuteCount: 4,
        commentsPerMinute: const <int, int>{5: 4},
      );

      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardContent =
                (call.arguments as Map<String, dynamic>)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                        programTitle: 'テスト',
                        lv: 'lv999',
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Scroll down to make the copy button visible (chart pushes it down).
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stats-copy-button')));
      await tester.pumpAndSettle();

      expect(clipboardContent, isNotNull);
      expect(clipboardContent, contains('総コメント数: 10'));
      expect(clipboardContent, contains('テスト'));

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    testWidgets('close button dismisses sheet', (WidgetTester tester) async {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 5,
        uniqueUserCount: 2,
        duration: const Duration(minutes: 3),
        peakMinuteLabel: '開始1分',
        peakMinuteCount: 3,
        commentsPerMinute: const <int, int>{1: 3},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stats-close-button')));
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsNothing);
    });

    testWidgets('displays frequency chart when data is available', (
      WidgetTester tester,
    ) async {
      final CommentLogStats stats = CommentLogStats(
        totalComments: 20,
        uniqueUserCount: 5,
        duration: const Duration(minutes: 10),
        peakMinuteLabel: '開始5分',
        peakMinuteCount: 10,
        commentsPerMinute: const <int, int>{0: 2, 5: 10, 10: 8},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('frequency-chart-title')), findsOneWidget);
      expect(find.byKey(const Key('frequency-chart')), findsOneWidget);
    });

    testWidgets('displays highlight peaks when enabled', (
      WidgetTester tester,
    ) async {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        for (int i = 0; i < 15; i++)
          _msg(
            id: 'p$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i * 3)),
            userId: 'u${i % 3}',
            content: 'peak $i',
          ),
        _msg(
          id: 'e1',
          timestamp: base.add(const Duration(minutes: 10)),
          userId: 'u1',
        ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                        highlightPickupEnabled: true,
                        messages: messages,
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Scroll down to reveal the highlight pickup section.
      final Finder listView = find.byType(ListView);
      if (listView.evaluate().isNotEmpty) {
        await tester.drag(listView, const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const Key('highlight-pickup-title')), findsOneWidget);
      expect(find.byKey(const Key('highlight-peak-0')), findsOneWidget);
    });

    testWidgets('does not show highlight peaks when disabled', (
      WidgetTester tester,
    ) async {
      final DateTime base = DateTime(2026, 3, 28, 12, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        _msg(id: '1', timestamp: base, userId: 'u1'),
        for (int i = 0; i < 15; i++)
          _msg(
            id: 'p$i',
            timestamp: base.add(Duration(minutes: 5, seconds: i * 3)),
            userId: 'u${i % 3}',
            content: 'peak $i',
          ),
      ];

      final CommentLogStats stats = CommentLogStats.fromMessages(messages);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CommentLogStatsSheet(
                        stats: stats,
                        themeMode: AppThemeMode.light,
                        highlightPickupEnabled: false,
                        messages: messages,
                      ),
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('highlight-pickup-title')), findsNothing);
    });
  });
}
