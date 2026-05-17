import 'package:comerune/domain/comment_log/recent_broadcast_stats.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectionSupervisor _supervisor() {
  final ConnectionSupervisor s = ConnectionSupervisor();
  s.startConnection();
  s.onSessionWsConnected();
  s.onNdgrEndpointResolved();
  return s;
}

Widget _wrap({
  required ConnectionSupervisor supervisor,
  required String currentLv,
  RecentBroadcastStats? recentBroadcastStats,
}) {
  return MaterialApp(
    home: CommentScreen(
      programInfo: CommentProgramInfo(
        lv: currentLv,
        programTitle: 'current title',
      ),
      connectionSupervisor: supervisor,
      messages: const <Object>[].cast(),
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
      ),
      themeMode: AppThemeMode.light,
      recentBroadcastStats: recentBroadcastStats,
    ),
  );
}

RecentBroadcastStats _stats({required String lv, String? title}) {
  return RecentBroadcastStats(
    lv: lv,
    endedAt: DateTime.utc(2026, 5, 1, 12, 0),
    totalComments: 10,
    uniqueUserCount: 4,
    durationSeconds: 600,
    programTitle: title,
    isBroadcaster: true,
  );
}

Future<void> _ensureStatusBarExpanded(WidgetTester tester) async {
  // _StatusBar auto-collapses 1500ms after initState; the issue #767
  // entry only renders while expanded. The first frame renders expanded,
  // so we just need to settle without waiting out the timer.
  await tester.pump();
}

void main() {
  group('CommentScreen 直前の統計を見る button (Issue #767)', () {
    testWidgets('hidden when recentBroadcastStats is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _wrap(supervisor: supervisor, currentLv: 'lv200'),
      );
      await _ensureStatusBarExpanded(tester);

      expect(
        find.byKey(const Key('show-recent-broadcast-stats-button')),
        findsNothing,
      );
    });

    testWidgets('hidden when recentBroadcastStats.lv equals current lv', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _wrap(
          supervisor: supervisor,
          currentLv: 'lv100',
          recentBroadcastStats: _stats(lv: 'lv100', title: 'previous'),
        ),
      );
      await _ensureStatusBarExpanded(tester);

      expect(
        find.byKey(const Key('show-recent-broadcast-stats-button')),
        findsNothing,
        reason: 'must not link to the current broadcast as its own previous',
      );
    });

    testWidgets('visible when recentBroadcastStats is set and lv differs', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _wrap(
          supervisor: supervisor,
          currentLv: 'lv200',
          recentBroadcastStats: _stats(lv: 'lv100', title: 'previous'),
        ),
      );
      await _ensureStatusBarExpanded(tester);

      expect(
        find.byKey(const Key('show-recent-broadcast-stats-button')),
        findsOneWidget,
      );
    });

    testWidgets('tap opens the recent stats modal sheet', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _supervisor();
      addTearDown(supervisor.dispose);
      await tester.pumpWidget(
        _wrap(
          supervisor: supervisor,
          currentLv: 'lv200',
          recentBroadcastStats: _stats(lv: 'lv100', title: 'previous title'),
        ),
      );
      await _ensureStatusBarExpanded(tester);

      await tester.tap(
        find.byKey(const Key('show-recent-broadcast-stats-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('recent-broadcast-stats-sheet')),
        findsOneWidget,
      );
    });
  });
}
