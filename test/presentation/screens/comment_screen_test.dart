import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_method.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/data/comment_log/comment_log_writer.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/theme/app_theme.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

void main() {
  group('CommentScreen', () {
    late WakelockPlusPlatformInterface previousWakelockPlatform;
    late _FakeWakelockPlusPlatform fakeWakelock;

    setUp(() {
      previousWakelockPlatform = wakelockPlusPlatformInstance;
      fakeWakelock = _FakeWakelockPlusPlatform();
      wakelockPlusPlatformInstance = fakeWakelock;
    });

    tearDown(() {
      wakelockPlusPlatformInstance = previousWakelockPlatform;
    });

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

      final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);
      Icon wifiIcon = tester.widget(find.byKey(const Key('status-wifi-icon')));
      expect(wifiIcon.color, themeColors.statusConnected);

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      wifiIcon = tester.widget(find.byKey(const Key('status-wifi-icon')));
      expect(wifiIcon.color, themeColors.statusDisconnected);
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

    testWidgets('broadcast ended system message bypasses NG filters', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '${kSystemBroadcastEndedMessageIdPrefix}1234567890',
          timestamp: DateTime(2026, 3, 30, 12, 35, 0),
          userId: 'user-ng',
          content: '放送が終了しました',
          type: AppMessageType.notification,
        ),
        AppMessage(
          id: 'chat-hidden',
          timestamp: DateTime(2026, 3, 30, 12, 35, 1),
          userId: 'user-ng',
          content: '放送が終了しました',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngUserIds: const <String>{'user-ng'},
          ngWords: const <String>['終了'],
        ),
      );

      expect(
        find.byKey(
          const Key(
            'comment-row-${kSystemBroadcastEndedMessageIdPrefix}1234567890',
          ),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comment-row-chat-hidden')), findsNothing);
      expect(find.textContaining('放送が終了しました'), findsOneWidget);
    });

    testWidgets('broadcast ended message uses broadcastEndedBackground color', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: '${kSystemBroadcastEndedMessageIdPrefix}1234567890',
          timestamp: DateTime(2026, 3, 30, 12, 35, 0),
          content: '放送が終了しました',
          type: AppMessageType.notification,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      final Container row = tester.widget(find.descendant(
        of: find.byKey(const Key(
          'comment-row-${kSystemBroadcastEndedMessageIdPrefix}1234567890',
        )),
        matching: find.byType(Container),
      ));
      expect(row.color, themeColors.broadcastEndedBackground);
    });

    testWidgets(
        'broadcast ended notification is excluded from stats and saved logs',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final _FakeCommentLogWriter commentLogWriter = _FakeCommentLogWriter();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'chat-real',
          type: AppMessageType.chat,
          content: '通常コメント',
        ),
        AppMessage(
          id: '${kSystemBroadcastEndedMessageIdPrefix}1234567890',
          timestamp: DateTime(2026, 3, 30, 12, 35, 0),
          content: '放送が終了しました',
          type: AppMessageType.notification,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          autoSaveCommentLog: true,
          commentLogWriter: commentLogWriter,
        ),
      );
      await tester.pumpAndSettle();

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(commentLogWriter.lastSavedMessages, hasLength(1));
      expect(commentLogWriter.lastSavedMessages!.single.id, 'chat-real');

      final Finder totalRow = find.byKey(const Key('stats-total-comments'));
      expect(totalRow, findsOneWidget);
      final List<Text> totalRowTexts = tester
          .widgetList<Text>(find.descendant(
            of: totalRow,
            matching: find.byType(Text),
          ))
          .toList();
      expect(totalRowTexts.last.data, '1');
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

    testWidgets('save button uses a save icon and label', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: <AppMessage>[
            _message(
              id: 'chat-save',
              type: AppMessageType.chat,
              content: '保存テスト',
            ),
          ],
          commentLogWriter: _FakeCommentLogWriter(),
        ),
      );

      final IconButton button =
          tester.widget(find.byKey(const Key('save-comment-log-button')));
      final Icon icon = button.icon as Icon;
      expect(icon.icon, Icons.save_outlined);
      expect(button.tooltip, 'コメントログを保存');
    });

    testWidgets('wakelock is released 45 seconds after ENDED', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );
      await tester.pump();

      expect(fakeWakelock.toggles, contains(true));

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();
      expect(fakeWakelock.toggles.where((bool value) => !value), isEmpty);

      await tester.pump(const Duration(seconds: 44));
      expect(fakeWakelock.toggles.where((bool value) => !value), isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(fakeWakelock.toggles.where((bool value) => !value), hasLength(1));
    });

    testWidgets('wakelock release is cancelled when reconnecting', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );
      await tester.pump();

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();

      expect(supervisor.startConnection(), isTrue);
      expect(supervisor.onSessionWsConnected(), isTrue);
      expect(supervisor.onNdgrEndpointResolved(), isTrue);
      await tester.pump();

      await tester.pump(const Duration(seconds: 46));
      expect(fakeWakelock.toggles.where((bool value) => !value), isEmpty);
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
                            themeMode: AppThemeMode.light,
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

      // AppBar shows only the broadcaster name.
      final Text appBarText = tester.widget<Text>(
        find.byKey(const Key('appbar-title-text')),
      );
      expect(appBarText.data, 'テスト配信者');

      // Program title bar shows the title with broadcaster icon.
      expect(find.byKey(const Key('program-title-bar')), findsOneWidget);
      expect(find.text('テスト番組'), findsOneWidget);

      // Status bar also shows the broadcaster name.
      expect(
        find.byKey(const Key('status-broadcaster-name')),
        findsOneWidget,
      );
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

      // Status bar does not show broadcaster name when null.
      expect(
        find.byKey(const Key('status-broadcaster-name')),
        findsNothing,
      );
    });

    testWidgets('shows broadcaster user ID in expanded status bar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          broadcasterName: '配信者テスト',
          broadcasterUserId: '12345678',
        ),
      );
      expect(
        find.byKey(const Key('status-broadcaster-user-id')),
        findsOneWidget,
      );
      expect(find.text('放送者ID: 12345678'), findsOneWidget);
    });

    testWidgets('hides broadcaster user ID when null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          broadcasterName: '配信者テスト',
        ),
      );
      expect(
        find.byKey(const Key('status-broadcaster-user-id')),
        findsNothing,
      );
    });

    testWidgets('broadcaster user ID hidden after auto-collapse', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          broadcasterName: '配信者X',
          broadcasterUserId: '99999',
        ),
      );
      // Initially visible (status bar starts expanded).
      expect(
        find.byKey(const Key('status-broadcaster-user-id')),
        findsOneWidget,
      );
      // After auto-collapse timer fires, user ID should be hidden.
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.byKey(const Key('status-broadcaster-user-id')),
        findsNothing,
      );
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
          commentFontSize: 18,
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

    testWidgets('applies custom user color to comment text', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'color-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-colored',
          content: 'colored comment',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'no-color-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-default',
          content: 'default comment',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          userColorMap: const <String, int>{'user-colored': 0xFFE53935},
        ),
      );

      final Text coloredText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-color-msg')),
          matching: find.byType(Text),
        ),
      );
      expect(coloredText.style?.color, colorFromARGB32(0xFFE53935));

      final Text defaultText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-no-color-msg')),
          matching: find.byType(Text),
        ),
      );
      expect(defaultText.style?.color, isNull);
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

    testWidgets('hides comments containing NG words', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-clean',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '普通のコメント',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'chat-ng',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-2',
          content: 'これはspamです',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['spam'],
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-clean')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-chat-ng')), findsNothing);
      expect(find.text('これはspamです'), findsNothing);
    });

    testWidgets('NG word matching is case-insensitive', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-upper',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'SPAM message',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['spam'],
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-upper')), findsNothing);
    });

    testWidgets('filters by second NG word in multi-word list', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-ok',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '普通のコメント',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'chat-bad',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-2',
          content: 'この広告を見て',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['spam', '広告'],
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-ok')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-chat-bad')), findsNothing);
    });

    testWidgets('empty NG words list does not filter any comments', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-normal',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'spam message',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>[],
        ),
      );

      expect(
        find.byKey(const Key('comment-row-chat-normal')),
        findsOneWidget,
      );
    });

    testWidgets('preset NG words are also applied to display filtering', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-clean-preset',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '普通のコメント',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'chat-ng-preset',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-2',
          content: 'これは爆破予告です',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>[],
          presetNgWords: const <String>['爆破予告'],
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-clean-preset')),
          findsOneWidget);
      expect(find.byKey(const Key('comment-row-chat-ng-preset')), findsNothing);
    });

    testWidgets('NG filtering handles keyword hack patterns in display', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-hack-ng',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '工 口ネタ',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['エロ'],
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-hack-ng')), findsNothing);
    });

    testWidgets('light erotic joke is not blocked by default preset policy', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-light-ero',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'ちょびっとエロい話',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>[],
          presetNgWords: const <String>['爆破予告', '児童ポルノ'],
        ),
      );

      expect(
          find.byKey(const Key('comment-row-chat-light-ero')), findsOneWidget);
    });

    testWidgets('long-press on comment row opens actions sheet', (
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

      expect(find.byKey(const Key('comment-actions-sheet')), findsOneWidget);
      expect(find.text('ピン留め'), findsOneWidget);
      expect(find.text('ユーザー詳細'), findsOneWidget);
    });

    testWidgets('long-press actions sheet opens user detail when tapped', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-lp2',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '12345',
          content: 'user detail test',
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

      await tester.longPress(find.byKey(const Key('comment-row-msg-lp2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action-user-detail')));
      await tester.pumpAndSettle();

      expect(find.text('ユーザー詳細'), findsOneWidget);
      expect(find.text('ID: 12345'), findsOneWidget);
      expect(find.text('名前: テストさん'), findsOneWidget);
    });

    testWidgets('statistics row is hidden when statisticsEnabled is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          statisticsEnabled: false,
          viewerCount: 100,
          totalCommentCount: 50,
          activeUserCount: 10,
        ),
      );

      expect(find.byKey(const Key('status-viewer-count')), findsNothing);
      expect(find.byKey(const Key('status-comment-count')), findsNothing);
      expect(find.byKey(const Key('status-active-user-count')), findsNothing);
    });

    testWidgets('statistics row shows all stats when enabled', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          statisticsEnabled: true,
          statisticsViewerCommentEnabled: true,
          statisticsActiveUserEnabled: true,
          viewerCount: 100,
          totalCommentCount: 50,
          activeUserCount: 10,
        ),
      );

      expect(find.text('リスナー: 100'), findsOneWidget);
      expect(find.text('コメント: 50'), findsOneWidget);
      expect(find.text('5分アクティブ: 10'), findsOneWidget);
    });

    testWidgets('statistics hides viewer/comment when child toggle is off', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          statisticsEnabled: true,
          statisticsViewerCommentEnabled: false,
          statisticsActiveUserEnabled: true,
          viewerCount: 100,
          totalCommentCount: 50,
          activeUserCount: 10,
        ),
      );

      expect(find.byKey(const Key('status-viewer-count')), findsNothing);
      expect(find.byKey(const Key('status-comment-count')), findsNothing);
      expect(find.text('5分アクティブ: 10'), findsOneWidget);
    });

    testWidgets('statistics hides active user when child toggle is off', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          statisticsEnabled: true,
          statisticsViewerCommentEnabled: true,
          statisticsActiveUserEnabled: false,
          viewerCount: 100,
          totalCommentCount: 50,
          activeUserCount: 10,
        ),
      );

      expect(find.text('リスナー: 100'), findsOneWidget);
      expect(find.text('コメント: 50'), findsOneWidget);
      expect(find.byKey(const Key('status-active-user-count')), findsNothing);
    });

    testWidgets('pin comment from actions sheet shows pinned section', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-pin',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'pin me',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // No pinned section initially.
      expect(find.byKey(const Key('pinned-comments-section')), findsNothing);

      // Long-press and pin.
      await tester.longPress(find.byKey(const Key('comment-row-msg-pin')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action-pin-msg-pin')));
      await tester.pumpAndSettle();

      // Pinned section is now visible.
      expect(find.byKey(const Key('pinned-comments-section')), findsOneWidget);
      expect(find.byKey(const Key('pinned-row-msg-pin')), findsOneWidget);
    });

    testWidgets('unpin comment via close button hides pinned section', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-unpin',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'unpin me',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // Pin the comment.
      await tester.longPress(find.byKey(const Key('comment-row-msg-unpin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-pin-msg-unpin')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pinned-comments-section')), findsOneWidget);

      // Unpin via the close button.
      await tester.tap(find.byKey(const Key('unpin-button-msg-unpin')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pinned-comments-section')), findsNothing);
    });

    testWidgets('multiple comments can be pinned', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-a',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'comment A',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'msg-b',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'u2',
          content: 'comment B',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // Pin first comment.
      await tester.longPress(find.byKey(const Key('comment-row-msg-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-pin-msg-a')));
      await tester.pumpAndSettle();

      // Pin second comment.
      await tester.longPress(find.byKey(const Key('comment-row-msg-b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-pin-msg-b')));
      await tester.pumpAndSettle();

      // Both pinned rows are visible.
      expect(find.byKey(const Key('pinned-row-msg-a')), findsOneWidget);
      expect(find.byKey(const Key('pinned-row-msg-b')), findsOneWidget);
    });

    testWidgets('unpin from actions sheet works for pinned comment', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-toggle',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'toggle pin',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // Pin the comment.
      await tester.longPress(find.byKey(const Key('comment-row-msg-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-pin-msg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pinned-comments-section')), findsOneWidget);

      // Long-press again shows "ピン留め解除".
      await tester.longPress(find.byKey(const Key('comment-row-msg-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('ピン留め解除'), findsOneWidget);

      // Unpin via the actions sheet.
      await tester.tap(find.byKey(const Key('action-unpin-msg-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pinned-comments-section')), findsNothing);
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

    testWidgets(
        'star prefix hides comment body when starPrefixHidingEnabled is true',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'star-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '☆ラスボスは実は味方だった',
          type: AppMessageType.chat,
        ),
        AppMessage(
          id: 'normal-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-2',
          content: 'こんにちは',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          starPrefixHidingEnabled: true,
        ),
      );

      // Star-prefixed comment should show placeholder
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsOneWidget);
      expect(find.textContaining('☆ラスボスは実は味方だった'), findsNothing);

      // Normal comment should still be visible
      expect(find.textContaining('こんにちは'), findsOneWidget);
    });

    testWidgets('star prefix comment reveals body on tap', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'star-reveal',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '☆秘密のメッセージ',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          starPrefixHidingEnabled: true,
        ),
      );

      // Should show placeholder
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsOneWidget);

      // Tap to reveal
      await tester.tap(find.byKey(const Key('comment-row-star-reveal')));
      await tester.pumpAndSettle();

      // Should now show original content
      expect(find.textContaining('☆秘密のメッセージ'), findsOneWidget);
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsNothing);
    });

    testWidgets(
        'star prefix shows normal content when starPrefixHidingEnabled is false',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'star-no-hide',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '☆普通に表示される',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          starPrefixHidingEnabled: false,
        ),
      );

      // With setting OFF, should show normal content
      expect(find.textContaining('☆普通に表示される'), findsOneWidget);
      expect(find.textContaining('ネタバレ防止'), findsNothing);
    });

    testWidgets('slash prefix comment displays content normally', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'slash-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '/おやすみなさい',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      // Slash prefix should display normally (TTS skip only)
      expect(find.textContaining('/おやすみなさい'), findsOneWidget);
    });

    testWidgets('star prefix preserves user ID and timestamp when hidden', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'star-meta',
          timestamp: DateTime(2026, 3, 22, 12, 34, 56),
          userId: '12345',
          content: '☆ネタバレ内容',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          starPrefixHidingEnabled: true,
        ),
      );

      // Timestamp and user ID should still be visible
      expect(find.textContaining('12:34:56'), findsOneWidget);
      expect(find.textContaining('12345'), findsOneWidget);
      // But content should be hidden
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsOneWidget);
    });

    testWidgets('star prefix hidden comment uses italic grey style', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'star-style',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '☆隠されるコメント',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          starPrefixHidingEnabled: true,
        ),
      );

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-star-style')),
          matching: find.byType(Text),
        ),
      );
      expect(textWidget.style?.fontStyle, FontStyle.italic);
      expect(textWidget.style?.color, Colors.grey);

      // Tap to reveal
      await tester.tap(find.byKey(const Key('comment-row-star-style')));
      await tester.pumpAndSettle();

      // After reveal, style should return to normal
      final Text revealedText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-star-style')),
          matching: find.byType(Text),
        ),
      );
      expect(revealedText.style?.fontStyle, isNull);
      expect(revealedText.style?.color, isNull);
    });

    testWidgets('star prefix revealed state resets when message ID changes', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-star-reset',
          initialMessages: <AppMessage>[
            AppMessage(
              id: 'star-reset-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-1',
              content: '☆最初のネタバレ',
              type: AppMessageType.chat,
            ),
          ],
          starPrefixHidingEnabled: true,
        ),
      );

      // Initially hidden
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsOneWidget);

      // Tap to reveal
      await tester.tap(find.byKey(const Key('comment-row-star-reset-1')));
      await tester.pumpAndSettle();

      // Now revealed
      expect(find.textContaining('☆最初のネタバレ'), findsOneWidget);

      // Replace with a different message (simulating new message at same index)
      hostKey.currentState!.replaceMessages(<AppMessage>[
        AppMessage(
          id: 'star-reset-2',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-1',
          content: '☆次のネタバレ',
          type: AppMessageType.chat,
        ),
      ]);
      await tester.pumpAndSettle();

      // New message should be hidden again (revealed state reset)
      expect(find.textContaining('ネタバレ防止: タップで表示'), findsOneWidget);
      expect(find.textContaining('☆次のネタバレ'), findsNothing);
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

    testWidgets('displays nickname in comment row when userNicknameMap is set',
        (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'こんにちは',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          userNicknameMap: const <String, String>{'user-1': 'たろう'},
        ),
      );

      // The nickname should appear in the comment text.
      expect(find.textContaining('たろう'), findsOneWidget);
    });

    testWidgets(
        'nickname takes priority over resolvedUserName in comment display', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          userName: 'プロトバフ名',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          userNicknameMap: const <String, String>{'user-1': 'コテハン名'},
          resolveUserName: (_) => 'リゾルブ名',
        ),
      );

      expect(find.textContaining('コテハン名'), findsOneWidget);
      expect(find.textContaining('プロトバフ名'), findsNothing);
      expect(find.textContaining('リゾルブ名'), findsNothing);
    });

    testWidgets('@name comment triggers onNicknameChanged callback', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_NicknameCommentScreenHostState> hostKey =
          GlobalKey<_NicknameCommentScreenHostState>();

      await tester.pumpWidget(
        _NicknameCommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
        ),
      );

      // Add a message with @name
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '@たろう',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();

      expect(hostKey.currentState!.lastNicknameUserId, 'user-1');
      expect(hostKey.currentState!.lastNickname, 'たろう');
    });

    testWidgets('@only comment triggers onNicknameRemoved callback', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_NicknameCommentScreenHostState> hostKey =
          GlobalKey<_NicknameCommentScreenHostState>();

      await tester.pumpWidget(
        _NicknameCommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
        ),
      );

      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '@',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();

      expect(hostKey.currentState!.lastRemovedUserId, 'user-1');
      expect(hostKey.currentState!.lastNickname, isNull);
    });

    testWidgets('does not process @name when autoNicknameRegistration is false',
        (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_NicknameCommentScreenHostState> hostKey =
          GlobalKey<_NicknameCommentScreenHostState>();

      await tester.pumpWidget(
        _NicknameCommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          autoNicknameRegistration: false,
        ),
      );

      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '@たろう',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();

      expect(hostKey.currentState!.lastNicknameUserId, isNull);
      expect(hostKey.currentState!.lastNickname, isNull);
    });

    testWidgets('shows elapsed time in H:MM:SS format when beginAt is provided',
        (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime beginAt = DateTime.now().subtract(
        const Duration(hours: 2, minutes: 30, seconds: 15),
      );

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: beginAt,
        ),
      );

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      expect(elapsedFinder, findsOneWidget);
      final Text elapsedText = tester.widget(elapsedFinder);
      expect(elapsedText.data, matches(RegExp(r'^\d+:\d{2}:\d{2}$')));
    });

    testWidgets('hides elapsed label when beginAt is null or in the future', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      // null case
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );
      expect(find.byKey(const Key('status-elapsed')), findsNothing);

      // future case
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      expect(find.byKey(const Key('status-elapsed')), findsNothing);
    });

    testWidgets('elapsed timer fires periodic rebuild', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime beginAt = DateTime.now().subtract(
        const Duration(minutes: 45, seconds: 10),
      );

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: beginAt,
        ),
      );

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      expect(elapsedFinder, findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(elapsedFinder, findsOneWidget);
      final Text updated = tester.widget(elapsedFinder);
      expect(updated.data, matches(RegExp(r'^\d+:\d{2}:\d{2}$')));
    });

    testWidgets('shows elapsed time when beginAt arrives after initial build', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      // Initial build without beginAt.
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      expect(elapsedFinder, findsNothing);

      // Rebuild with beginAt provided (simulates late arrival).
      final DateTime beginAt = DateTime.now().subtract(
        const Duration(minutes: 10, seconds: 5),
      );
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: beginAt,
        ),
      );

      expect(elapsedFinder, findsOneWidget);
      final Text elapsedText = tester.widget(elapsedFinder);
      expect(elapsedText.data, matches(RegExp(r'^\d+:\d{2}:\d{2}$')));

      // Verify the periodic timer is running after late beginAt.
      await tester.pump(const Duration(seconds: 1));
      expect(elapsedFinder, findsOneWidget);
      final Text updated = tester.widget(elapsedFinder);
      expect(updated.data, matches(RegExp(r'^\d+:\d{2}:\d{2}$')));
    });

    testWidgets('hides elapsed label when beginAt changes to null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime beginAt = DateTime.now().subtract(
        const Duration(hours: 1),
      );

      // Initial build with beginAt.
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: beginAt,
        ),
      );

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      expect(elapsedFinder, findsOneWidget);

      // Rebuild without beginAt (simulates disconnect/reconnect).
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      expect(elapsedFinder, findsNothing);

      // Verify the timer no longer fires unnecessary rebuilds.
      await tester.pump(const Duration(seconds: 2));
      expect(elapsedFinder, findsNothing);
    });

    testWidgets(
        'restarts elapsed timer when beginAt changes to a different value', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime firstBeginAt = DateTime.now().subtract(
        const Duration(hours: 2),
      );

      // Initial build with first beginAt.
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: firstBeginAt,
        ),
      );

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      expect(elapsedFinder, findsOneWidget);
      final Text firstText = tester.widget(elapsedFinder);
      // Should show approximately 2:00:00.
      expect(firstText.data, startsWith('2:'));

      // Rebuild with a different beginAt (simulates reconnect to new stream).
      final DateTime secondBeginAt = DateTime.now().subtract(
        const Duration(minutes: 5),
      );
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: secondBeginAt,
        ),
      );

      expect(elapsedFinder, findsOneWidget);
      final Text secondText = tester.widget(elapsedFinder);
      // Should show approximately 0:05:00, not 2:00:00.
      expect(secondText.data, startsWith('0:'));

      // Verify the timer continues to fire after value change.
      await tester.pump(const Duration(seconds: 1));
      expect(elapsedFinder, findsOneWidget);
    });
  });

  group('Comment timestamp elapsed display', () {
    testWidgets('shows elapsed time in comment row when beginAt is provided', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'elapsed-msg',
          timestamp: DateTime(2026, 3, 22, 11, 23, 45),
          userId: 'u1',
          content: 'hello',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          beginAt: beginAt,
        ),
      );

      // Elapsed from 10:00:00 to 11:23:45 = 1:23:45
      expect(find.textContaining('1:23:45'), findsOneWidget);
    });

    testWidgets('falls back to local time when beginAt is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime msgTime = DateTime(2026, 3, 22, 14, 30, 15);
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'local-msg',
          timestamp: msgTime,
          userId: 'u1',
          content: 'world',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      final DateTime local = msgTime.toLocal();
      final String hh = local.hour.toString().padLeft(2, '0');
      final String mm = local.minute.toString().padLeft(2, '0');
      final String ss = local.second.toString().padLeft(2, '0');
      expect(find.textContaining('$hh:$mm:$ss'), findsOneWidget);
    });
  });

  group('Comment log stats', () {
    testWidgets('shows stats sheet when connection ends with messages', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'c1',
          type: AppMessageType.chat,
          content: 'hello',
        ),
        _message(
          id: 'c2',
          type: AppMessageType.chat,
          content: 'world',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
        ),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // total comments
    });

    testWidgets('does not show stats sheet when no displayable messages', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
        ),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsNothing);
    });
  });
}

class _NicknameCommentScreenHost extends StatefulWidget {
  const _NicknameCommentScreenHost({
    super.key,
    required this.supervisor,
    this.autoNicknameRegistration = true,
  });

  final ConnectionSupervisor supervisor;
  final bool autoNicknameRegistration;

  @override
  State<_NicknameCommentScreenHost> createState() =>
      _NicknameCommentScreenHostState();
}

class _NicknameCommentScreenHostState
    extends State<_NicknameCommentScreenHost> {
  List<AppMessage> _messages = const <AppMessage>[];
  String? lastNicknameUserId;
  String? lastNickname;
  String? lastRemovedUserId;

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        lv: 'lv123',
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        onStopAllConnections: () async {},
        onReconnectSameLv: () async {},
        onDifferentLvConnected: (_, __) async {},
        autoNicknameRegistration: widget.autoNicknameRegistration,
        onNicknameChanged: (String userId, String nickname) {
          lastNicknameUserId = userId;
          lastNickname = nickname;
        },
        onNicknameRemoved: (String userId) {
          lastRemovedUserId = userId;
          lastNickname = null;
        },
        themeMode: AppThemeMode.light,
      ),
    );
  }
}

class _CommentScreenHost extends StatefulWidget {
  const _CommentScreenHost({
    super.key,
    required this.supervisor,
    required this.initialLv,
    required this.initialMessages,
    this.starPrefixHidingEnabled = false,
  });

  final ConnectionSupervisor supervisor;
  final String initialLv;
  final List<AppMessage> initialMessages;
  final bool starPrefixHidingEnabled;

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
        starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
        themeMode: AppThemeMode.light,
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
  String? broadcasterUserId,
  String? Function(String userId)? resolveUserName,
  double commentFontSize = commentFontSizeDefault,
  Set<String> ngUserIds = const <String>{},
  List<String> ngWords = const <String>[],
  List<String> presetNgWords = const <String>[],
  Map<String, int> userColorMap = const <String, int>{},
  Map<String, String> userNicknameMap = const <String, String>{},
  bool statisticsEnabled = false,
  bool statisticsViewerCommentEnabled = true,
  bool statisticsActiveUserEnabled = true,
  int? viewerCount,
  int totalCommentCount = 0,
  int activeUserCount = 0,
  bool starPrefixHidingEnabled = false,
  DateTime? beginAt,
  CommentLogWriter? commentLogWriter,
  bool autoSaveCommentLog = false,
  String autoSaveCommentLogPath = '',
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
      broadcasterUserId: broadcasterUserId,
      resolveUserName: resolveUserName,
      commentFontSize: commentFontSize,
      beginAt: beginAt,
      ngUserIds: ngUserIds,
      ngWords: ngWords,
      presetNgWords: presetNgWords,
      userColorMap: userColorMap,
      userNicknameMap: userNicknameMap,
      starPrefixHidingEnabled: starPrefixHidingEnabled,
      themeMode: AppThemeMode.light,
      statisticsEnabled: statisticsEnabled,
      statisticsViewerCommentEnabled: statisticsViewerCommentEnabled,
      statisticsActiveUserEnabled: statisticsActiveUserEnabled,
      viewerCount: viewerCount,
      totalCommentCount: totalCommentCount,
      activeUserCount: activeUserCount,
      commentLogWriter: commentLogWriter,
      autoSaveCommentLog: autoSaveCommentLog,
      autoSaveCommentLogPath: autoSaveCommentLogPath,
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

class _FakeCommentLogWriter implements CommentLogWriter {
  List<AppMessage>? lastSavedMessages;
  List<AppMessage>? lastTempMessages;
  int saveCallCount = 0;
  int writeToTempFileCallCount = 0;

  @override
  Future<String?> save({
    required String lv,
    required List<AppMessage> messages,
    Directory? customDirectory,
  }) async {
    saveCallCount++;
    lastSavedMessages = List<AppMessage>.from(messages);
    return '/tmp/$lv.txt';
  }

  @override
  Future<String?> writeToTempFile({
    required String lv,
    required List<AppMessage> messages,
  }) async {
    writeToTempFileCallCount++;
    lastTempMessages = List<AppMessage>.from(messages);
    return '/tmp/$lv.tmp.txt';
  }
}

class _FakeWakelockPlusPlatform extends WakelockPlusPlatformInterface {
  final List<bool> toggles = <bool>[];
  bool _enabled = false;

  @override
  Future<bool> get enabled async => _enabled;

  @override
  Future<void> toggle({required bool enable}) async {
    toggles.add(enable);
    _enabled = enable;
  }
}
