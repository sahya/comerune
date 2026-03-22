import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/connection/connection_supervisor.dart';
import '../../../lib/domain/models/app_message.dart';
import '../../../lib/presentation/screens/comment_screen.dart';

void main() {
  group('CommentScreen', () {
    testWidgets('Wi-Fi icon color follows connection status', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      Icon wifiIcon = tester.widget(find.byKey(const Key('status-wifi-icon')));
      expect(wifiIcon.color, Colors.green);

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      wifiIcon = tester.widget(find.byKey(const Key('status-wifi-icon')));
      expect(wifiIcon.color, Colors.red);
    });

    testWidgets('status bar shows normal and debug fields', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      supervisor.recordReceivedAt(DateTime(2026, 3, 22, 12, 34, 56));
      expect(
        supervisor.onStreamDisconnected(ConnectionErrorCode.ndgrStreamFailed),
        isTrue,
      );

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          lv: 'lv777',
          debugMode: true,
          connectionMethod: ConnectionMethod.ndgr,
        ),
      );

      expect(find.text('lv: lv777'), findsOneWidget);
      expect(find.text('再接続: 1回'), findsOneWidget);
      expect(find.text('エラー: NDGR_STREAM_FAILED'), findsOneWidget);
      expect(find.text('方式: NDGR'), findsOneWidget);
      expect(find.text('フェーズ: RECONNECTING'), findsOneWidget);

      final Text lastReceived =
          tester.widget(find.byKey(const Key('status-last-received')));
      expect(lastReceived.data, isNot('最終受信: -'));
      expect(lastReceived.data, contains(':'));
    });

    testWidgets('comment row colors are applied by message type', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'chat-1',
          type: AppMessageType.chat,
          content: '通常コメント',
        ),
        _message(
          id: 'operator-1',
          type: AppMessageType.operator,
          content: '運営コメント',
        ),
        _message(
          id: 'notification-1',
          type: AppMessageType.notification,
          content: '通知コメント',
        ),
        _message(
          id: 'legacy-1',
          type: AppMessageType.notification,
          content: kLegacyUnsupportedFormatMessage,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      final Container operatorRow =
          tester.widget(find.byKey(const Key('comment-row-operator-1')));
      expect(operatorRow.color, Colors.yellow.shade100);

      final Container notificationRow =
          tester.widget(find.byKey(const Key('comment-row-notification-1')));
      expect(notificationRow.color, Colors.lightBlue.shade50);

      final Container legacyRow =
          tester.widget(find.byKey(const Key('comment-row-legacy-1')));
      expect(legacyRow.color, Colors.lightBlue.shade50);
      expect(find.textContaining(kLegacyUnsupportedFormatMessage), findsOneWidget);
    });

    testWidgets('shows stop button during active connection and reconnect button on ENDED', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int stopCalls = 0;
      int reconnectCalls = 0;

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onStopAllConnections: () async {
            stopCalls += 1;
          },
          onReconnectSameLv: () async {
            reconnectCalls += 1;
          },
        ),
      );

      expect(find.byKey(const Key('stop-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stop-button')));
      await tester.pumpAndSettle();
      expect(stopCalls, 1);

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reconnect-button')), findsOneWidget);
      expect(find.byKey(const Key('stop-button')), findsNothing);

      await tester.tap(find.byKey(const Key('reconnect-button')));
      await tester.pumpAndSettle();
      expect(reconnectCalls, 1);
    });

    testWidgets('stop button is disabled while idle', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      final ElevatedButton stopButton =
          tester.widget(find.byKey(const Key('stop-button')));
      expect(stopButton.onPressed, isNull);
    });

    testWidgets('auto-scroll pauses while user scrolls up and resumes at bottom', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv100',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'initial-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ListView listView =
          tester.widget(find.byKey(const Key('comment-list')));
      final ScrollController controller = listView.controller!;

      expect(
        (controller.position.maxScrollExtent - controller.offset).abs() < 2,
        isTrue,
      );

      await tester.drag(find.byKey(const Key('comment-list')), const Offset(0, 300));
      await tester.pumpAndSettle();
      final double pausedOffset = controller.offset;

      hostKey.currentState!.addMessage(
        _message(
          id: 'new-1',
          type: AppMessageType.chat,
          content: 'new-comment-1',
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.offset, closeTo(pausedOffset, 2));

      await tester.drag(find.byKey(const Key('comment-list')), const Offset(0, -1200));
      await tester.pumpAndSettle();

      hostKey.currentState!.addMessage(
        _message(
          id: 'new-2',
          type: AppMessageType.chat,
          content: 'new-comment-2',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        (controller.position.maxScrollExtent - controller.offset).abs() < 2,
        isTrue,
      );
    });

    testWidgets('shows snackbar on transition to FAILED', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      expect(supervisor.fail(ConnectionErrorCode.endpointResolveFailed), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('コメントサーバーの取得に失敗しました'), findsOneWidget);
    });

    testWidgets('shows reconnect button on FAILED and allows retry tap', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int reconnectCalls = 0;

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onReconnectSameLv: () async {
            reconnectCalls += 1;
          },
        ),
      );

      expect(supervisor.fail(ConnectionErrorCode.endpointResolveFailed), isTrue);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reconnect-button')), findsOneWidget);
      expect(find.byKey(const Key('stop-button')), findsNothing);

      await tester.tap(find.byKey(const Key('reconnect-button')));
      await tester.pumpAndSettle();
      expect(reconnectCalls, 1);
    });

    testWidgets('back navigation stops all connections and returns', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int stopCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CommentScreen(
                            lv: 'lv999',
                            connectionSupervisor: supervisor,
                            messages: const <AppMessage>[],
                            onStopAllConnections: () async {
                              stopCalls += 1;
                            },
                            onReconnectSameLv: () async {},
                            onDifferentLvConnected: (_, __) async {},
                          ),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(stopCalls, 1);
      expect(supervisor.status, ConnectionStatus.stopped);
      expect(find.byType(CommentScreen), findsNothing);
    });

    testWidgets('invokes callback when lv changes (different lv connection)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv111',
          initialMessages: <AppMessage>[
            _message(
              id: 'msg-1',
              type: AppMessageType.chat,
              content: 'message-1',
            ),
          ],
        ),
      );

      hostKey.currentState!.changeLv('lv222');
      await tester.pumpAndSettle();

      expect(hostKey.currentState!.differentLvCallbackCount, 1);
      expect(hostKey.currentState!.previousLv, 'lv111');
      expect(hostKey.currentState!.nextLv, 'lv222');
    });
  });
}

class _CommentScreenHost extends StatefulWidget {
  const _CommentScreenHost({
    super.key,
    required this.supervisor,
    required this.initialLv,
    required this.initialMessages,
  });

  final ConnectionSupervisor supervisor;
  final String initialLv;
  final List<AppMessage> initialMessages;

  @override
  State<_CommentScreenHost> createState() => _CommentScreenHostState();
}

class _CommentScreenHostState extends State<_CommentScreenHost> {
  late String _lv;
  late List<AppMessage> _messages;

  int differentLvCallbackCount = 0;
  String? previousLv;
  String? nextLv;

  @override
  void initState() {
    super.initState();
    _lv = widget.initialLv;
    _messages = List<AppMessage>.from(widget.initialMessages);
  }

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  void changeLv(String lv) {
    setState(() {
      _lv = lv;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        lv: _lv,
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (String previous, String next) async {
          differentLvCallbackCount += 1;
          previousLv = previous;
          nextLv = next;
        },
      ),
    );
  }
}

Widget _buildScreen({
  required ConnectionSupervisor supervisor,
  required List<AppMessage> messages,
  String lv = 'lv345678901',
  Future<void> Function()? onStopAllConnections,
  Future<void> Function()? onReconnectSameLv,
  bool debugMode = false,
  ConnectionMethod? connectionMethod,
}) {
  return MaterialApp(
    home: CommentScreen(
      lv: lv,
      connectionSupervisor: supervisor,
      messages: messages,
      onStopAllConnections: onStopAllConnections ?? () async {},
      onReconnectSameLv: onReconnectSameLv ?? () async {},
      onDifferentLvConnected: (_, __) async {},
      debugMode: debugMode,
      connectionMethod: connectionMethod,
    ),
  );
}

ConnectionSupervisor _buildStreamingSupervisor() {
  final ConnectionSupervisor supervisor = ConnectionSupervisor();
  expect(supervisor.startConnection(), isTrue);
  expect(supervisor.onSessionWsConnected(), isTrue);
  expect(supervisor.onNdgrEndpointResolved(), isTrue);
  return supervisor;
}

AppMessage _message({
  required String id,
  required AppMessageType type,
  required String content,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime(2026, 3, 22, 12, 0, 0),
    userId: 'user-1',
    content: content,
    type: type,
  );
}
