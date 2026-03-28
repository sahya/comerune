import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_method.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';

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

      final Container operatorRow = tester.widget(find.descendant(
        of: find.byKey(const Key('comment-row-operator-1')),
        matching: find.byType(Container),
      ));
      expect(operatorRow.color, Colors.yellow.shade100);

      final Container notificationRow = tester.widget(find.descendant(
        of: find.byKey(const Key('comment-row-notification-1')),
        matching: find.byType(Container),
      ));
      expect(notificationRow.color, Colors.lightBlue.shade50);

      final Container legacyRow = tester.widget(find.descendant(
        of: find.byKey(const Key('comment-row-legacy-1')),
        matching: find.byType(Container),
      ));
      expect(legacyRow.color, Colors.lightBlue.shade50);
      expect(
          find.textContaining(kLegacyUnsupportedFormatMessage), findsOneWidget);
    });

    testWidgets('does not render gift and nicoad messages on v1.2', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'chat-visible',
          type: AppMessageType.chat,
          content: '通常コメント',
        ),
        _message(
          id: 'gift-hidden',
          type: AppMessageType.gift,
          content: 'ギフト',
        ),
        _message(
          id: 'nicoad-hidden',
          type: AppMessageType.nicoad,
          content: 'ニコニ広告',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-visible')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-gift-hidden')), findsNothing);
      expect(find.byKey(const Key('comment-row-nicoad-hidden')), findsNothing);
      expect(find.text('ギフト'), findsNothing);
      expect(find.text('ニコニ広告'), findsNothing);
    });

    testWidgets('shows stop button during active connection', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int stopCalls = 0;

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onStopAllConnections: () async {
            stopCalls += 1;
          },
        ),
      );

      expect(find.byKey(const Key('stop-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('stop-button')));
      await tester.pumpAndSettle();
      expect(stopCalls, 1);
      expect(supervisor.status, ConnectionStatus.stopped);
    });

    testWidgets('shows reconnect button on ENDED and allows retry tap', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int reconnectCalls = 0;

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onReconnectSameLv: () async {
            reconnectCalls += 1;
          },
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('reconnect-button')), findsOneWidget);
      expect(find.byKey(const Key('stop-button')), findsNothing);

      await tester.tap(find.byKey(const Key('reconnect-button')));
      await tester.pumpAndSettle();
      expect(reconnectCalls, 1);
    });

    testWidgets('stop button is disabled while idle',
        (WidgetTester tester) async {
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

    testWidgets(
        'auto-scroll pauses while user scrolls up and resumes at bottom', (
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

      await tester.drag(
          find.byKey(const Key('comment-list')), const Offset(0, 300));
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

      await tester.drag(
          find.byKey(const Key('comment-list')), const Offset(0, -1200));
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

    testWidgets(
        'auto-scroll keeps working when ring-buffer update keeps same length',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      final List<AppMessage> initialMessages = List<AppMessage>.generate(
        40,
        (int index) => _message(
          id: 'rb-initial-$index',
          type: AppMessageType.chat,
          content: 'comment-$index',
        ),
      );

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-ring',
          initialMessages: initialMessages,
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

      final List<AppMessage> rotated = <AppMessage>[
        ...initialMessages.sublist(1),
        _message(
          id: 'rb-new-tail',
          type: AppMessageType.chat,
          content: 'new tail\nline2\nline3\nline4\nline5',
        ),
      ];
      hostKey.currentState!.replaceMessages(rotated);
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

      expect(
          supervisor.fail(ConnectionErrorCode.endpointResolveFailed), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('コメントサーバーの取得に失敗しました 再接続ボタンで再試行できます。'),
        findsOneWidget,
      );
    });

    testWidgets('shows failure detail in snackbar and debug status bar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          debugMode: true,
        ),
      );

      expect(
        supervisor.fail(
          ConnectionErrorCode.sessionWsConnectFailed,
          errorDetail: 'HandshakeException: 401 Unauthorized',
        ),
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('code: SESSION_WS_CONNECT_FAILED'),
        findsOneWidget,
      );
      expect(find.textContaining('原因: HandshakeException: 401 Unauthorized'),
          findsOneWidget);
      expect(find.byKey(const Key('status-last-error-detail')), findsOneWidget);
      expect(find.textContaining('エラー詳細: HandshakeException'), findsOneWidget);
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

      expect(
          supervisor.fail(ConnectionErrorCode.endpointResolveFailed), isTrue);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reconnect-button')), findsOneWidget);
      expect(find.byKey(const Key('stop-button')), findsNothing);

      final BuildContext context = tester.element(find.byType(CommentScreen));
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await tester.pumpAndSettle();

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

    testWidgets('displays program title bar when provided', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          programTitle: 'テスト番組',
        ),
      );

      expect(find.byKey(const Key('program-title-bar')), findsOneWidget);
      expect(find.text('テスト番組'), findsOneWidget);
      // lv is in the AppBar title separately.
      expect(find.text('lv345678901'), findsAtLeast(1));
    });

    testWidgets('shows broadcaster name with lv in AppBar title', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          programTitle: 'テスト番組',
          broadcasterName: 'テスト配信者',
        ),
      );

      // AppBar shows "放送者名 ─ lv" in a single line.
      expect(
        find.byKey(const Key('appbar-title-text')),
        findsOneWidget,
      );
      expect(find.text('テスト配信者 | lv345678901'), findsOneWidget);

      // Program title bar shows only the title, no broadcaster name.
      expect(find.byKey(const Key('program-title-bar')), findsOneWidget);
      expect(find.text('テスト番組'), findsOneWidget);
    });

    testWidgets('shows lv only in AppBar when broadcasterName is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          programTitle: 'タイトルのみ',
        ),
      );

      // lv is shown as the title when no broadcaster name.
      expect(
        find.byKey(const Key('appbar-title-text')),
        findsOneWidget,
      );
      expect(find.text('lv345678901'), findsAtLeast(1));

      expect(find.byKey(const Key('program-title-bar')), findsOneWidget);
      expect(find.text('タイトルのみ'), findsOneWidget);
    });

    testWidgets('hides program title bar when title is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      expect(find.byKey(const Key('program-title-bar')), findsNothing);
      expect(find.text('lv345678901'), findsAtLeast(1));
    });

    testWidgets('sort toggle button reverses comment order', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'first',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'first comment',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'second',
          timestamp: DateTime(2026, 3, 22, 12, 0, 10),
          userId: 'u2',
          content: 'second comment',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // Default: ascending (first comment is first in list)
      final Finder firstRow = find.byKey(const Key('comment-row-first'));
      final Finder secondRow = find.byKey(const Key('comment-row-second'));
      expect(firstRow, findsOneWidget);
      expect(secondRow, findsOneWidget);

      // First row should be above second row.
      final double firstY = tester.getTopLeft(firstRow).dy;
      final double secondY = tester.getTopLeft(secondRow).dy;
      expect(firstY, lessThan(secondY));

      // Tap sort toggle to switch to descending.
      await tester.tap(find.byKey(const Key('sort-toggle-button')));
      await tester.pumpAndSettle();

      // Now second comment should be above first.
      final double firstYAfter = tester.getTopLeft(firstRow).dy;
      final double secondYAfter = tester.getTopLeft(secondRow).dy;
      expect(secondYAfter, lessThan(firstYAfter));
    });

    testWidgets('displays resolved user name with user ID', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-name',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '12345',
          content: 'hello',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (String userId) {
            if (userId == '12345') {
              return 'テストさん';
            }
            return null;
          },
        ),
      );

      expect(find.textContaining('テストさん (12345)'), findsOneWidget);
      expect(find.textContaining('hello'), findsOneWidget);
    });

    testWidgets('displays raw user ID when not resolved', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-raw',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '99999',
          content: 'world',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => null,
        ),
      );

      expect(find.textContaining('99999'), findsOneWidget);
      expect(find.textContaining('world'), findsOneWidget);
    });

    testWidgets('applies configured font size to comment rows', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'font-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'font size test',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          commentFontSize: CommentFontSize.xl,
        ),
      );

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-font-msg')),
          matching: find.byType(Text),
        ),
      );
      expect(textWidget.style?.fontSize, 18);
    });

    testWidgets('default font size is medium (14px)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'default-font-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'default font test',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-default-font-msg')),
          matching: find.byType(Text),
        ),
      );
      expect(textWidget.style?.fontSize, 14);
    });

    testWidgets('hides NG user comments from display', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-visible',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-ok',
          content: '表示コメント',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'chat-hidden',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-ng',
          content: 'NGコメント',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngUserIds: const <String>{'user-ng'},
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-visible')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-chat-hidden')), findsNothing);
      expect(find.text('NGコメント'), findsNothing);
    });

    testWidgets('long-press on comment row opens user detail sheet', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-lp',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '12345',
          content: 'long-press test',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => 'テストさん',
        ),
      );

      await tester.longPress(find.byKey(const Key('comment-row-msg-lp')));
      await tester.pumpAndSettle();

      expect(find.text('ユーザー詳細'), findsOneWidget);
      expect(find.text('ID: 12345'), findsOneWidget);
      expect(find.text('名前: テストさん'), findsOneWidget);
    });

    testWidgets('shows settings button when onOpenSettings is provided', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onOpenSettings: () async {},
        ),
      );

      expect(find.byKey(const Key('settings-button')), findsOneWidget);
    });

    testWidgets('tapping settings button invokes onOpenSettings callback', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      int settingsCalls = 0;

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          onOpenSettings: () async {
            settingsCalls += 1;
          },
        ),
      );

      await tester.tap(find.byKey(const Key('settings-button')));
      await tester.pumpAndSettle();
      expect(settingsCalls, 1);
    });

    testWidgets('hides settings button when onOpenSettings is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      expect(find.byKey(const Key('settings-button')), findsNothing);
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

  void replaceMessages(List<AppMessage> messages) {
    setState(() {
      _messages = List<AppMessage>.from(messages);
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
  Future<void> Function()? onOpenSettings,
  bool debugMode = false,
  ConnectionMethod? connectionMethod,
  String? programTitle,
  String? broadcasterName,
  String? Function(String userId)? resolveUserName,
  CommentFontSize commentFontSize = CommentFontSize.medium,
  Set<String> ngUserIds = const <String>{},
}) {
  return MaterialApp(
    home: CommentScreen(
      lv: lv,
      connectionSupervisor: supervisor,
      messages: messages,
      onStopAllConnections: onStopAllConnections ?? () async {},
      onReconnectSameLv: onReconnectSameLv ?? () async {},
      onDifferentLvConnected: (_, __) async {},
      onOpenSettings: onOpenSettings,
      debugMode: debugMode,
      connectionMethod: connectionMethod,
      programTitle: programTitle,
      broadcasterName: broadcasterName,
      resolveUserName: resolveUserName,
      commentFontSize: commentFontSize,
      ngUserIds: ngUserIds,
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
