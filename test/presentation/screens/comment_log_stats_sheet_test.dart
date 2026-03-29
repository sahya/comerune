import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/comment_log/comment_log_stats.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_log_stats_sheet.dart';
import 'package:comerune/presentation/theme/app_theme.dart';

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
  });
}
