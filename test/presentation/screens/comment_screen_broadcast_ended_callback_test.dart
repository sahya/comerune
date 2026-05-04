import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ConnectionSupervisor _buildStreamingSupervisor() {
  final ConnectionSupervisor s = ConnectionSupervisor();
  s.startConnection();
  s.onSessionWsConnected();
  s.onNdgrEndpointResolved();
  return s;
}

AppMessage _chat(String id, String body) {
  return AppMessage(
    id: id,
    timestamp: DateTime.utc(
      2026,
      5,
      1,
      12,
      0,
      0,
    ).add(Duration(seconds: int.parse(id.substring(1)))),
    userId: 'u-$id',
    content: body,
    type: AppMessageType.chat,
  );
}

Widget _wrap({
  required ConnectionSupervisor supervisor,
  required List<AppMessage> messages,
  BroadcastEndedStatsCallback? onBroadcastEndedStats,
}) {
  return MaterialApp(
    home: CommentScreen(
      programInfo: const CommentProgramInfo(
        lv: 'lv12345',
        programTitle: 'タイトル',
        broadcasterUserId: 'b-1',
        broadcasterName: '放送者',
      ),
      connectionSupervisor: supervisor,
      messages: messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, _) async {},
        onBroadcastEndedStats: onBroadcastEndedStats,
      ),
      themeMode: AppThemeMode.light,
    ),
  );
}

void main() {
  group('CommentScreen.onBroadcastEndedStats wiring (Issue #766)', () {
    testWidgets(
      'fires once when the broadcast ends and snapshot carries program metadata',
      (WidgetTester tester) async {
        final List<BroadcastEndedStatsSnapshot> captured =
            <BroadcastEndedStatsSnapshot>[];
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        addTearDown(supervisor.dispose);

        await tester.pumpWidget(
          _wrap(
            supervisor: supervisor,
            messages: <AppMessage>[_chat('c1', 'hi'), _chat('c2', 'hello')],
            onBroadcastEndedStats: captured.add,
          ),
        );

        expect(supervisor.endBroadcast(), isTrue);
        // Apply state change + post-frame for the panel to mount.
        await tester.pump();
        await tester.pump();

        expect(captured, hasLength(1));
        final BroadcastEndedStatsSnapshot s = captured.single;
        expect(s.lv, 'lv12345');
        expect(s.programTitle, 'タイトル');
        expect(s.broadcasterUserId, 'b-1');
        expect(s.broadcasterName, '放送者');
        expect(s.totalComments, 2);
        // 視聴セッション扱い (テストは broadcaster 判定を走らせていない)。
        expect(s.isBroadcaster, isFalse);
      },
    );

    testWidgets('callback null is a no-op (panel still appears)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      addTearDown(supervisor.dispose);

      await tester.pumpWidget(
        _wrap(
          supervisor: supervisor,
          messages: <AppMessage>[_chat('c1', 'hi')],
        ),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('stats-panel-expanded')),
        findsOneWidget,
        reason: 'panel must still be shown when callback is null',
      );
    });

    testWidgets(
      'a throwing callback is caught and does not tear down the panel',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        addTearDown(supervisor.dispose);

        await tester.pumpWidget(
          _wrap(
            supervisor: supervisor,
            messages: <AppMessage>[_chat('c1', 'hi')],
            onBroadcastEndedStats: (_) => throw StateError('intentional'),
          ),
        );

        expect(supervisor.endBroadcast(), isTrue);
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('stats-panel-expanded')), findsOneWidget);
      },
    );
  });
}
