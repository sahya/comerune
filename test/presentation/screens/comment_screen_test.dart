import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_method.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/data/comment_log/comment_log_writer.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/user_name_resolution.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';
import 'package:comerune/presentation/screens/comment_screen_config.dart';
import 'package:comerune/presentation/theme/app_theme.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../_support/rich_text_finders.dart';

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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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

      final Text lastReceived = tester.widget(
        find.byKey(const Key('status-last-received')),
      );
      expect(lastReceived.data, isNot('最終受信: -'));
      expect(lastReceived.data, contains(':'));
    });

    testWidgets('comment row colors are applied by message type', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-1', type: AppMessageType.chat, content: '通常コメント'),
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
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      final Container operatorRow = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-operator-1')),
          matching: find.byType(Container),
        ),
      );
      expect(operatorRow.color, Colors.yellow.shade100);

      final Container notificationRow = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-notification-1')),
          matching: find.byType(Container),
        ),
      );
      expect(notificationRow.color, Colors.lightBlue.shade50);

      final Container legacyRow = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-legacy-1')),
          matching: find.byType(Container),
        ),
      );
      expect(legacyRow.color, Colors.lightBlue.shade50);
      expect(
        find.textContaining(kLegacyUnsupportedFormatMessage),
        findsOneWidget,
      );
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
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      final Container row = tester.widget(
        find.descendant(
          of: find.byKey(
            const Key(
              'comment-row-${kSystemBroadcastEndedMessageIdPrefix}1234567890',
            ),
          ),
          matching: find.byType(Container),
        ),
      );
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
            .widgetList<Text>(
              find.descendant(of: totalRow, matching: find.byType(Text)),
            )
            .toList();
        expect(totalRowTexts.last.data, '1');
      },
    );

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
        _message(id: 'gift-hidden', type: AppMessageType.gift, content: 'ギフト'),
        _message(
          id: 'nicoad-hidden',
          type: AppMessageType.nicoad,
          content: 'ニコニ広告',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
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

    testWidgets('stop button is disabled while idle', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );

      final ElevatedButton stopButton = tester.widget(
        find.byKey(const Key('stop-button')),
      );
      expect(stopButton.onPressed, isNull);
    });

    testWidgets('save button uses an archive icon and label', (
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

      final IconButton button = tester.widget(
        find.byKey(const Key('save-comment-log-button')),
      );
      final Icon icon = button.icon as Icon;
      expect(icon.icon, Icons.archive_outlined);
      expect(button.tooltip, 'コメントログを保存');
    });

    testWidgets('wakelock is released 45 seconds after ENDED', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
      'auto-scroll pauses while user scrolls up and resumes at bottom',
      (WidgetTester tester) async {
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

        final ListView listView = tester.widget(
          find.byKey(const Key('comment-list')),
        );
        final ScrollController controller = listView.controller!;

        expect(
          (controller.position.maxScrollExtent - controller.offset).abs() < 2,
          isTrue,
        );

        await tester.drag(
          find.byKey(const Key('comment-list')),
          const Offset(0, 300),
        );
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
          find.byKey(const Key('comment-list')),
          const Offset(0, -1200),
        );
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
      },
    );

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

        final ListView listView = tester.widget(
          find.byKey(const Key('comment-list')),
        );
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
      },
    );

    testWidgets('shows snackbar on transition to FAILED', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );

      expect(
        supervisor.fail(ConnectionErrorCode.endpointResolveFailed),
        isTrue,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('コメントサーバーの取得に失敗しました 再接続ボタンで再試行できます。'), findsOneWidget);
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
      expect(
        find.textContaining('原因: HandshakeException: 401 Unauthorized'),
        findsOneWidget,
      );
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
        supervisor.fail(ConnectionErrorCode.endpointResolveFailed),
        isTrue,
      );
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
                            programInfo: const CommentProgramInfo(lv: 'lv999'),
                            connectionSupervisor: supervisor,
                            messages: const <AppMessage>[],
                            callbacks: CommentCallbacks(
                              onStopAllConnections: () async {
                                stopCalls += 1;
                              },
                              onReconnectSameLv: () async {},
                              onDifferentLvConnected: (_, _) async {},
                            ),
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
      expect(find.byKey(const Key('status-broadcaster-name')), findsOneWidget);
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
      expect(find.byKey(const Key('appbar-title-text')), findsOneWidget);
      expect(find.text('lv345678901'), findsAtLeast(1));

      expect(find.byKey(const Key('program-title-bar')), findsOneWidget);
      expect(find.text('タイトルのみ'), findsOneWidget);

      // Status bar does not show broadcaster name when null.
      expect(find.byKey(const Key('status-broadcaster-name')), findsNothing);
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
      expect(find.byKey(const Key('status-broadcaster-user-id')), findsNothing);
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
      expect(find.byKey(const Key('status-broadcaster-user-id')), findsNothing);
    });

    testWidgets('hides program title bar when title is null', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
        _buildScreen(supervisor: supervisor, messages: messages),
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

      // Text.rich is used; check the content span (last child) for font size.
      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-font-msg')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan root = textWidget.textSpan! as TextSpan;
      final TextSpan contentSpan = root.children!.last as TextSpan;
      expect(contentSpan.style?.fontSize, 18);
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
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-default-font-msg')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan root = textWidget.textSpan! as TextSpan;
      final TextSpan contentSpan = root.children!.last as TextSpan;
      expect(contentSpan.style?.fontSize, 14);
    });

    testWidgets('clamps timestamp and user ID font size at minimum', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'small-font-msg',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: 'small font test',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          commentFontSize: 10,
        ),
      );

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-small-font-msg')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan root = textWidget.textSpan! as TextSpan;
      // Timestamp span (first child): 10 * 0.85 = 8.5 → clamped to 9.0
      final TextSpan timestampSpan = root.children!.first as TextSpan;
      expect(timestampSpan.style?.fontSize, 9.0);
      // Content span (last child): not clamped, stays at 10
      final TextSpan contentSpan = root.children!.last as TextSpan;
      expect(contentSpan.style?.fontSize, 10);
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

      // Text.rich is used; check the content span (last child) for color.
      final Text coloredText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-color-msg')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan coloredRoot = coloredText.textSpan! as TextSpan;
      final TextSpan coloredContentSpan =
          coloredRoot.children!.last as TextSpan;
      expect(coloredContentSpan.style?.color, colorFromARGB32(0xFFE53935));

      final Text defaultText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-no-color-msg')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan defaultRoot = defaultText.textSpan! as TextSpan;
      final TextSpan defaultContentSpan =
          defaultRoot.children!.last as TextSpan;
      expect(defaultContentSpan.style?.color, isNull);
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

      expect(find.byKey(const Key('comment-row-chat-normal')), findsOneWidget);
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

      expect(
        find.byKey(const Key('comment-row-chat-clean-preset')),
        findsOneWidget,
      );
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

    testWidgets('NG filtering handles expanded look-alike table entries', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-lookalike-expanded',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: '冂リ匚ンネタ',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['ロリコン'],
        ),
      );

      expect(
        find.byKey(const Key('comment-row-chat-lookalike-expanded')),
        findsNothing,
      );
    });

    testWidgets('NG filtering handles half-width voiced katakana bypass', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'chat-halfwidth-voiced',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'ﾊﾞﾅﾅネタ',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['バナナ'],
        ),
      );

      expect(
        find.byKey(const Key('comment-row-chat-halfwidth-voiced')),
        findsNothing,
      );
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
        find.byKey(const Key('comment-row-chat-light-ero')),
        findsOneWidget,
      );
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
      expect(find.text('コメントをコピー'), findsOneWidget);
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
        _buildScreen(supervisor: supervisor, messages: messages),
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
        _buildScreen(supervisor: supervisor, messages: messages),
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

    testWidgets('multiple comments can be pinned', (WidgetTester tester) async {
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
        _buildScreen(supervisor: supervisor, messages: messages),
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
        _buildScreen(supervisor: supervisor, messages: messages),
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

    testWidgets(
      'copy comment action writes content to clipboard and shows snackbar',
      (WidgetTester tester) async {
        // Intercept the Clipboard method channel so we can observe what the
        // app writes without relying on pumpAndSettle (which can hang on the
        // SnackBar auto-dismiss timer).
        String? clipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              final Map<String, dynamic> args =
                  (methodCall.arguments as Map<Object?, Object?>)
                      .cast<String, dynamic>();
              clipboardText = args['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });

        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-copy',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'u1',
            content: 'コピー対象のコメント',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        await tester.longPress(find.byKey(const Key('comment-row-msg-copy')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action-copy-comment')));
        // Pump a few frames but do NOT call pumpAndSettle — the SnackBar
        // auto-dismiss timer can keep the scheduler busy for the entire
        // pumpAndSettle timeout.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(clipboardText, 'コピー対象のコメント');
        expect(
          find.byKey(const Key('comment-copied-snackbar')),
          findsOneWidget,
        );
      },
    );

    testWidgets('copy action is hidden when comment content is empty', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'u1',
          content: '',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      await tester.longPress(find.byKey(const Key('comment-row-msg-empty')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('action-copy-comment')), findsNothing);
    });

    group('URL short-tap behavior', () {
      late UrlLauncherPlatform previousUrlLauncher;
      late _FakeUrlLauncher fakeUrlLauncher;

      setUp(() {
        previousUrlLauncher = UrlLauncherPlatform.instance;
        fakeUrlLauncher = _FakeUrlLauncher();
        UrlLauncherPlatform.instance = fakeUrlLauncher;
      });

      tearDown(() {
        UrlLauncherPlatform.instance = previousUrlLauncher;
      });

      testWidgets(
        'tapping a comment that contains a URL opens the confirmation dialog',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'msg-url',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: '見てね https://example.com だよ',
              type: AppMessageType.chat,
            ),
          ];

          await tester.pumpWidget(
            _buildScreen(supervisor: supervisor, messages: messages),
          );

          await tester.tap(find.byKey(const Key('comment-row-msg-url')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('url-confirm-dialog')), findsOneWidget);
          expect(find.byKey(const Key('url-confirm-open')), findsOneWidget);
          expect(find.byKey(const Key('url-confirm-cancel')), findsOneWidget);
          final SelectableText urlText = tester.widget(
            find.byKey(const Key('url-confirm-url-text')),
          );
          expect(urlText.data, 'https://example.com');
          expect(fakeUrlLauncher.launchedUrls, isEmpty);
        },
      );

      testWidgets(
        'confirming the dialog launches the URL in external browser mode',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'msg-url-confirm',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: 'https://example.com',
              type: AppMessageType.chat,
            ),
          ];

          await tester.pumpWidget(
            _buildScreen(supervisor: supervisor, messages: messages),
          );

          await tester.tap(
            find.byKey(const Key('comment-row-msg-url-confirm')),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('url-confirm-open')));
          await tester.pumpAndSettle();

          expect(fakeUrlLauncher.launchedUrls, <String>['https://example.com']);
          expect(
            fakeUrlLauncher.lastLaunchMode,
            PreferredLaunchMode.externalApplication,
          );
          expect(find.byKey(const Key('url-confirm-dialog')), findsNothing);
        },
      );

      testWidgets('cancelling the dialog does NOT launch the URL', (
        WidgetTester tester,
      ) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-url-cancel',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'u1',
            content: 'https://example.com',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        await tester.tap(find.byKey(const Key('comment-row-msg-url-cancel')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('url-confirm-cancel')));
        await tester.pumpAndSettle();

        expect(fakeUrlLauncher.launchedUrls, isEmpty);
        expect(find.byKey(const Key('url-confirm-dialog')), findsNothing);
      });

      testWidgets('tapping a comment without a URL does not open any dialog', (
        WidgetTester tester,
      ) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-no-url',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'u1',
            content: 'ただのコメント',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        await tester.tap(find.byKey(const Key('comment-row-msg-no-url')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('url-confirm-dialog')), findsNothing);
        expect(find.byKey(const Key('url-picker-dialog')), findsNothing);
        expect(fakeUrlLauncher.launchedUrls, isEmpty);
      });

      testWidgets(
        'javascript: pseudo-URL is never recognized as a tappable link',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'msg-js',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: 'click javascript:alert(1)',
              type: AppMessageType.chat,
            ),
          ];

          await tester.pumpWidget(
            _buildScreen(supervisor: supervisor, messages: messages),
          );

          await tester.tap(find.byKey(const Key('comment-row-msg-js')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('url-confirm-dialog')), findsNothing);
          expect(fakeUrlLauncher.launchedUrls, isEmpty);
        },
      );

      testWidgets('comment with two URLs shows a picker dialog', (
        WidgetTester tester,
      ) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-multi',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'u1',
            content: 'a https://a.example b http://b.example c',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        await tester.tap(find.byKey(const Key('comment-row-msg-multi')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('url-picker-dialog')), findsOneWidget);
        expect(find.byKey(const Key('url-picker-option-0')), findsOneWidget);
        expect(find.byKey(const Key('url-picker-option-1')), findsOneWidget);

        // Selecting the second URL launches it.
        await tester.tap(find.byKey(const Key('url-picker-option-1')));
        await tester.pumpAndSettle();

        expect(fakeUrlLauncher.launchedUrls, <String>['http://b.example']);
      });

      testWidgets(
        'URL portion of the comment is rendered with underline decoration',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'msg-deco',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: '見て https://example.com だよ',
              type: AppMessageType.chat,
            ),
          ];

          await tester.pumpWidget(
            _buildScreen(supervisor: supervisor, messages: messages),
          );

          final Text textWidget = tester.widget(
            find.descendant(
              of: find.byKey(const Key('comment-row-msg-deco')),
              matching: find.byType(Text),
            ),
          );
          final TextSpan root = textWidget.textSpan! as TextSpan;

          // Collect all leaf TextSpans and find the one whose text is the URL.
          final List<TextSpan> leaves = <TextSpan>[];
          void walk(InlineSpan span) {
            if (span is TextSpan) {
              if (span.text != null) {
                leaves.add(span);
              }
              for (final InlineSpan child
                  in span.children ?? const <InlineSpan>[]) {
                walk(child);
              }
            }
          }

          walk(root);
          final TextSpan urlSpan = leaves.firstWhere(
            (TextSpan span) => span.text == 'https://example.com',
            orElse: () => throw StateError('URL span not found'),
          );
          expect(urlSpan.style?.decoration, TextDecoration.underline);
        },
      );

      testWidgets('failing launchUrl shows a failure snackbar', (
        WidgetTester tester,
      ) async {
        fakeUrlLauncher.shouldSucceed = false;
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-fail',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'u1',
            content: 'https://example.com',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        await tester.tap(find.byKey(const Key('comment-row-msg-fail')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('url-confirm-open')));
        // The SnackBar auto-dismiss timer can hang pumpAndSettle, so pump
        // a few explicit frames instead.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.byKey(const Key('url-launch-failed-snackbar')),
          findsOneWidget,
        );
      });

      testWidgets(
        'URL confirm dialog shows host in a dedicated emphasised slot',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'msg-host',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: 'https://example.com/some/path?q=1',
              type: AppMessageType.chat,
            ),
          ];

          await tester.pumpWidget(
            _buildScreen(supervisor: supervisor, messages: messages),
          );

          await tester.tap(find.byKey(const Key('comment-row-msg-host')));
          await tester.pumpAndSettle();

          final SelectableText hostText = tester.widget(
            find.byKey(const Key('url-confirm-host-text')),
          );
          expect(hostText.data, 'example.com');
          final SelectableText urlText = tester.widget(
            find.byKey(const Key('url-confirm-url-text')),
          );
          expect(urlText.data, 'https://example.com/some/path?q=1');
        },
      );

      testWidgets(
        'star-hidden comment still reveals on tap and is not treated as URL',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final List<AppMessage> messages = <AppMessage>[
            AppMessage(
              id: 'star-url',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'u1',
              content: '☆ネタバレ https://spoilers.example',
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

          // First tap reveals the body, does NOT open the URL dialog.
          await tester.tap(find.byKey(const Key('comment-row-star-url')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('url-confirm-dialog')), findsNothing);
          expect(fakeUrlLauncher.launchedUrls, isEmpty);

          // After reveal, a second tap opens the URL dialog as usual.
          await tester.tap(find.byKey(const Key('comment-row-star-url')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('url-confirm-dialog')), findsOneWidget);
        },
      );
    });

    testWidgets(
      'two-line mode renders content on separate line from timestamp',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-tl-1',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-1',
            content: '二段表示テスト',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            commentTwoLineEnabled: true,
            resolveUserName: (_) => 'ユーザー名',
          ),
        );

        // In two-line mode, both the username and content should be visible
        // as separate text widgets (not merged into a single line).
        expect(find.textContaining('ユーザー名'), findsOneWidget);
        expect(find.textContaining('二段表示テスト'), findsOneWidget);
      },
    );

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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
      },
    );

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
      },
    );

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
        _buildScreen(supervisor: supervisor, messages: messages),
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

      // Text.rich is used for hidden comments; check content span style.
      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-star-style')),
          matching: find.byType(Text),
        ),
      );
      final TextSpan hiddenRoot = textWidget.textSpan! as TextSpan;
      final TextSpan hiddenContentSpan = hiddenRoot.children!.last as TextSpan;
      expect(hiddenContentSpan.style?.fontStyle, FontStyle.italic);
      expect(hiddenContentSpan.style?.color, Colors.grey);

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
      final TextSpan revealedRoot = revealedText.textSpan! as TextSpan;
      final TextSpan revealedContentSpan =
          revealedRoot.children!.last as TextSpan;
      expect(revealedContentSpan.style?.fontStyle, isNull);
      expect(revealedContentSpan.style?.color, isNull);
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

    testWidgets(
      'displays nickname in comment row when userNicknameMap is set',
      (WidgetTester tester) async {
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
      },
    );

    testWidgets(
      'nickname takes priority over resolvedUserName in comment display',
      (WidgetTester tester) async {
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
      },
    );

    testWidgets('empty userName falls back to resolved username', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty-name',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          userName: '',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => 'リゾルブ名',
        ),
      );

      expect(find.textContaining('リゾルブ名'), findsOneWidget);
    });

    testWidgets('empty userName with no resolution shows userId', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty-name-no-resolve',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-2',
          userName: '',
          content: 'テスト',
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

      expect(find.textContaining('user-2'), findsOneWidget);
    });

    testWidgets('empty nickname in map falls back to userName or resolution', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty-nickname',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          userNicknameMap: const <String, String>{'user-1': ''},
          resolveUserName: (_) => 'API名',
        ),
      );

      // Empty nickname should be skipped, API-resolved name shown instead.
      expect(find.textContaining('API名'), findsOneWidget);
    });

    testWidgets('empty userId message shows content without user column', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty-userid',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => 'API名',
        ),
      );

      // Empty userId: should not show username column at all.
      expect(find.textContaining('API名'), findsNothing);
    });

    testWidgets('null userName with valid userId falls back to resolved name', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-null-name',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-3',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => 'リゾルブ名',
        ),
      );

      expect(find.textContaining('リゾルブ名'), findsOneWidget);
    });

    testWidgets('empty resolve result falls back gracefully', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-empty-resolve',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-4',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => '',
        ),
      );

      // Empty resolve result should not be displayed as name.
      // userId should be shown instead.
      expect(find.textContaining('user-4'), findsOneWidget);
    });

    testWidgets(
      'null userName and null userId shows content without user column',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-null-all',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            content: 'テスト',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            resolveUserName: (_) => 'API名',
          ),
        );

        // Both null: no user name column should appear.
        expect(find.textContaining('API名'), findsNothing);
      },
    );

    testWidgets('valid userName without nickname shows userName directly', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-valid-name-no-nick',
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
          resolveUserName: (_) => 'リゾルブ名',
        ),
      );

      // userName should be shown; resolve should not be needed.
      expect(find.textContaining('プロトバフ名'), findsOneWidget);
      expect(find.textContaining('リゾルブ名'), findsNothing);
    });

    testWidgets('valid userName with empty userId does not show user column', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        AppMessage(
          id: 'msg-name-empty-userid',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: '',
          userName: 'プロトバフ名',
          content: 'テスト',
          type: AppMessageType.chat,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          resolveUserName: (_) => 'リゾルブ名',
        ),
      );

      // Empty userId: widget skips user column entirely regardless of userName.
      expect(find.textContaining('プロトバフ名'), findsNothing);
      expect(find.textContaining('リゾルブ名'), findsNothing);
    });

    testWidgets(
      'all empty strings: empty userName, empty userId, empty resolve',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'msg-all-empty',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: '',
            userName: '',
            content: 'テスト',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            resolveUserName: (_) => '',
          ),
        );

        // All empty: no user name should appear.
        expect(find.textContaining('リゾルブ名'), findsNothing);
        expect(find.textContaining('API名'), findsNothing);
      },
    );

    testWidgets('@name comment triggers onNicknameChanged callback', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_NicknameCommentScreenHostState> hostKey =
          GlobalKey<_NicknameCommentScreenHostState>();

      await tester.pumpWidget(
        _NicknameCommentScreenHost(key: hostKey, supervisor: supervisor),
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
        _NicknameCommentScreenHost(key: hostKey, supervisor: supervisor),
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

    testWidgets(
      'does not process @name when autoNicknameRegistration is false',
      (WidgetTester tester) async {
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
      },
    );

    testWidgets(
      'shows elapsed time in H:MM:SS format when beginAt is provided',
      (WidgetTester tester) async {
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
      },
    );

    testWidgets('hides elapsed label when beginAt is null or in the future', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      // null case
      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );

      expect(elapsedFinder, findsNothing);

      // Verify the timer no longer fires unnecessary rebuilds.
      await tester.pump(const Duration(seconds: 2));
      expect(elapsedFinder, findsNothing);
    });

    testWidgets(
      'restarts elapsed timer when beginAt changes to a different value',
      (WidgetTester tester) async {
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
      },
    );

    testWidgets('FAB is hidden when auto-scroll is enabled (initial state)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-fab-hidden',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'fab-hidden-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scroll-to-latest-button')), findsNothing);
    });

    testWidgets('FAB is shown after scrolling away from latest', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-fab-shown',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'fab-shown-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll up (positive offset = scroll towards top).
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scroll-to-latest-button')), findsOneWidget);
    });

    testWidgets('tapping FAB scrolls to latest and hides FAB', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-fab-tap',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'fab-tap-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll up to show FAB.
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scroll-to-latest-button')), findsOneWidget);

      // Tap the FAB.
      await tester.tap(find.byKey(const Key('scroll-to-latest-button')));
      await tester.pumpAndSettle();

      // FAB should be hidden after tapping.
      expect(find.byKey(const Key('scroll-to-latest-button')), findsNothing);

      // Verify scrolled back to the bottom.
      final ListView listView = tester.widget(
        find.byKey(const Key('comment-list')),
      );
      final ScrollController controller = listView.controller!;
      expect(
        (controller.position.maxScrollExtent - controller.offset).abs() < 2,
        isTrue,
      );
    });

    testWidgets('FAB shows arrow_downward icon in ascending sort order', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-fab-icon-asc',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'fab-icon-asc-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll up to disable auto-scroll and show the FAB.
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();

      // In ascending order (default), FAB should show arrow_downward.
      final Icon icon = tester.widget(
        find.descendant(
          of: find.byKey(const Key('scroll-to-latest-button')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.arrow_downward);
    });

    testWidgets('FAB shows arrow_upward icon in descending sort order', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-fab-icon-desc',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'fab-icon-desc-$index',
              type: AppMessageType.chat,
              content: 'comment-$index',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Toggle sort order to descending.
      await tester.tap(find.byKey(const Key('sort-toggle-button')));
      await tester.pumpAndSettle();

      // Scroll down to disable auto-scroll and show the FAB.
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      // In descending order, FAB should show arrow_upward.
      final Icon icon = tester.widget(
        find.descendant(
          of: find.byKey(const Key('scroll-to-latest-button')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, Icons.arrow_upward);
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
        _buildScreen(supervisor: supervisor, messages: messages),
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
        _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
        _message(id: 'c2', type: AppMessageType.chat, content: 'world'),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
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
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('コメント統計サマリ'), findsNothing);
    });
  });

  group('Message-type display toggles', () {
    testWidgets('hides operator messages when showOperatorComment is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
        _message(
          id: 'operator-hidden',
          type: AppMessageType.operator,
          content: '運営コメント',
          userId: null,
          userName: '運営',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          showOperatorComment: false,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
      expect(
        find.byKey(const Key('comment-row-operator-hidden')),
        findsNothing,
      );
    });

    testWidgets('hides system messages when showSystemMessage is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
        _message(
          id: 'system-hidden',
          type: AppMessageType.system,
          content: '市場通知',
          userId: null,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          showSystemMessage: false,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-system-hidden')), findsNothing);
    });

    testWidgets('hides emotion messages when showEmotion is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
        _message(
          id: 'emotion-hidden',
          type: AppMessageType.emotion,
          content: 'エモーション',
          userId: null,
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          showEmotion: false,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-emotion-hidden')), findsNothing);
    });

    testWidgets(
      'operator=OFF, system=ON, emotion=OFF keeps only system + chat',
      (WidgetTester tester) async {
        // Combo coverage: individual-OFF tests pass independently even when
        // the toggles are checked in isolation. This combination ensures that
        // when two toggles are OFF at the same time, the remaining ON toggle
        // still functions (no accidental AND/OR short-circuit in the filter).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
          _message(
            id: 'operator-hidden',
            type: AppMessageType.operator,
            content: '運営コメント',
            userId: null,
            userName: '運営',
          ),
          _message(
            id: 'system-vis',
            type: AppMessageType.system,
            content: '市場通知',
            userId: null,
          ),
          _message(
            id: 'emotion-hidden',
            type: AppMessageType.emotion,
            content: 'エモーション',
            userId: null,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            showOperatorComment: false,
            showSystemMessage: true,
            showEmotion: false,
          ),
        );

        // chat and system remain; operator and emotion are suppressed.
        expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-system-vis')), findsOneWidget);
        expect(
          find.byKey(const Key('comment-row-operator-hidden')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('comment-row-emotion-hidden')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'all-OFF (operator=OFF, system=OFF, emotion=OFF) keeps only chat',
      (WidgetTester tester) async {
        // Combo coverage: when all three message-type display toggles are OFF
        // simultaneously, only chat messages must remain. Guards against a
        // regression where the combined filter accidentally lets a category
        // through (e.g. short-circuit after the first false).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
          _message(
            id: 'operator-hidden',
            type: AppMessageType.operator,
            content: '運営コメント',
            userId: null,
            userName: '運営',
          ),
          _message(
            id: 'system-hidden',
            type: AppMessageType.system,
            content: '市場通知',
            userId: null,
          ),
          _message(
            id: 'emotion-hidden',
            type: AppMessageType.emotion,
            content: 'エモーション',
            userId: null,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            showOperatorComment: false,
            showSystemMessage: false,
            showEmotion: false,
          ),
        );

        expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
        expect(
          find.byKey(const Key('comment-row-operator-hidden')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('comment-row-system-hidden')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('comment-row-emotion-hidden')),
          findsNothing,
        );
      },
    );

    testWidgets('operator message body is rendered with operatorTextColor', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      // Use distinct strings for the label and the body so this test can
      // independently assert that the userName label span is rendered.
      // (Previously both strings contained "運営" which made the label
      // assertion pass from body substring alone.)
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'operator-red',
          type: AppMessageType.operator,
          content: 'お知らせ',
          userId: null,
          userName: '公式',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);

      // The body text (exact match) should be styled with operatorTextColor
      // regardless of the default chat color.
      final RichText bodyRichText = findRichTextContaining(tester, 'お知らせ');
      final Color? bodyColor = findSpanColor(bodyRichText.text, 'お知らせ');
      expect(bodyColor, themeColors.operatorTextColor);

      // The operator userName label ("公式") must also render -- operator
      // messages normalize with userId=null, so the label only appears if
      // the renderer falls back to message.userName. We verify a span whose
      // text EXACTLY equals the label string, to guard against false-positive
      // substring matches from the body.
      final RichText metaRichText = findRichTextContaining(tester, '公式');
      final Color? labelColor = findSpanColor(metaRichText.text, '公式');
      expect(
        labelColor,
        themeColors.operatorTextColor,
        reason: 'operator userName label must render with operatorTextColor',
      );
    });

    testWidgets(
      'operator message without userName does not render a label span',
      (WidgetTester tester) async {
        // Documents the fallback: when an operator message has no userName,
        // no label is drawn (the renderer must NOT substitute a placeholder).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-no-name',
            type: AppMessageType.operator,
            content: 'ラベルなし本文',
            userId: null,
            userName: null,
          ),
          _message(
            id: 'operator-empty-name',
            type: AppMessageType.operator,
            content: '空ラベル本文',
            userId: null,
            userName: '',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        // Both rows must still render (operator toggle defaults to true).
        expect(
          find.byKey(const Key('comment-row-operator-no-name')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('comment-row-operator-empty-name')),
          findsOneWidget,
        );

        // Verify no span contains the literal string "null" (i.e. the
        // renderer did not accidentally stringify a null userName).
        final RichText nullCaseRich = findRichTextContaining(tester, 'ラベルなし本文');
        expect(nullCaseRich.text.toPlainText().contains('null'), isFalse);
        // Verify the body still renders so the row is not entirely empty.
        expect(nullCaseRich.text.toPlainText().contains('ラベルなし本文'), isTrue);
        final RichText emptyCaseRich = findRichTextContaining(tester, '空ラベル本文');
        expect(emptyCaseRich.text.toPlainText().contains('空ラベル本文'), isTrue);
      },
    );

    testWidgets('operator messages are suppressed by ngUserIds', (
      WidgetTester tester,
    ) async {
      // Operator + NG-user: even though operator comments have userId=null
      // normally, if a non-null userId is present and it is NG-listed, the
      // row must be hidden. Documents interaction of filter paths.
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'operator-ng-user',
          type: AppMessageType.operator,
          content: 'NGユーザー運営メッセージ',
          userId: 'ng-user-1',
          userName: '運営',
        ),
        _message(id: 'chat-visible', type: AppMessageType.chat, content: '通常'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngUserIds: const <String>{'ng-user-1'},
        ),
      );

      expect(
        find.byKey(const Key('comment-row-operator-ng-user')),
        findsNothing,
      );
      expect(find.byKey(const Key('comment-row-chat-visible')), findsOneWidget);
    });

    testWidgets('operator messages are suppressed by ngWords', (
      WidgetTester tester,
    ) async {
      // Operator + NG-word: operator body matched by NG word must be hidden.
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(
          id: 'operator-ng-word',
          type: AppMessageType.operator,
          content: 'スパム告知',
          userId: null,
          userName: '運営',
        ),
        _message(id: 'chat-visible', type: AppMessageType.chat, content: '通常'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          ngWords: const <String>['スパム'],
        ),
      );

      expect(
        find.byKey(const Key('comment-row-operator-ng-word')),
        findsNothing,
      );
      expect(find.byKey(const Key('comment-row-chat-visible')), findsOneWidget);
    });

    testWidgets(
      'pinned operator row renders userName label even when userId is null',
      (WidgetTester tester) async {
        // Regression: pinned rows must use the shared display-name resolver
        // so operator (運営) rows that normalize with userId=null still show
        // the label. Uses distinct label/body strings.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'pinned-operator',
            type: AppMessageType.operator,
            content: '告知本文',
            userId: null,
            userName: '公式',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        // Long-press and pin the operator row.
        await tester.longPress(
          find.byKey(const Key('comment-row-pinned-operator')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('action-pin-pinned-operator')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('pinned-row-pinned-operator')),
          findsOneWidget,
        );
        // The pinned row's meta/body text must contain the label "公式" —
        // if the renderer dropped it because userId is null, this fails.
        final Finder pinnedRowFinder = find.byKey(
          const Key('pinned-row-pinned-operator'),
        );
        expect(
          find.descendant(
            of: pinnedRowFinder,
            matching: find.textContaining('公式'),
          ),
          findsWidgets,
          reason:
              'pinned operator row must render userName label ("公式") even when userId is null',
        );

        // Regression: the pinned (single-line) row must keep the theme's
        // operator text color on the body. In an earlier revision
        // `_PinnedCommentRow.build` fell back to the per-user [userColor],
        // which is null for operator messages (they normalize with
        // userId=null), causing the red "warning" tone to degrade to the
        // default Text color inside the pinned panel. A plain-text
        // `textContaining` check cannot detect that color regression.
        final AppThemeColors themeColors = AppTheme.colorsFor(
          AppThemeMode.light,
        );
        final Text pinnedBodyText = tester.widget<Text>(
          find.descendant(
            of: pinnedRowFinder,
            matching: find.textContaining('告知本文'),
          ),
        );
        expect(
          pinnedBodyText.style?.color,
          themeColors.operatorTextColor,
          reason:
              'pinned operator (single-line) body must render with operatorTextColor',
        );
      },
    );

    testWidgets(
      'pinned operator row (two-line) keeps operatorTextColor on body and label',
      (WidgetTester tester) async {
        // Two-line pinned path: `_buildTwoLinePinned` renders the meta row
        // as Text.rich where the displayName span must carry the operator
        // red, and the body Text must also carry it. Cover both so a
        // future tweak that only wires one side cannot pass silently.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'pinned-operator-2l',
            type: AppMessageType.operator,
            content: '2行告知本文',
            userId: null,
            userName: '2行公式',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            commentTwoLineEnabled: true,
          ),
        );

        await tester.longPress(
          find.byKey(const Key('comment-row-pinned-operator-2l')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('action-pin-pinned-operator-2l')),
        );
        await tester.pumpAndSettle();

        final Finder pinnedRowFinder = find.byKey(
          const Key('pinned-row-pinned-operator-2l'),
        );
        expect(pinnedRowFinder, findsOneWidget);

        final AppThemeColors themeColors = AppTheme.colorsFor(
          AppThemeMode.light,
        );

        // Body Text (second line) is a plain Text widget with color set
        // on its TextStyle.
        final Text pinnedBodyText = tester.widget<Text>(
          find.descendant(
            of: pinnedRowFinder,
            matching: find.textContaining('2行告知本文'),
          ),
        );
        expect(
          pinnedBodyText.style?.color,
          themeColors.operatorTextColor,
          reason:
              'pinned operator (two-line) body must render with operatorTextColor',
        );

        // Meta row is Text.rich; walk its spans to find the displayName
        // label span and assert its color.
        final RichText metaRichText = findRichTextContaining(tester, '2行公式');
        final Color? labelColor = findSpanColor(metaRichText.text, '2行公式');
        expect(
          labelColor,
          themeColors.operatorTextColor,
          reason:
              'pinned operator (two-line) meta label must render with operatorTextColor',
        );
      },
    );

    testWidgets(
      'operator message body is rendered with operatorTextColor under protanopia theme',
      (WidgetTester tester) async {
        // Existing operator-red assertions only cover the light theme. The
        // color-vision-deficient themes (P/D/T) define a distinct
        // operatorTextColor value each; verify at least one of them is wired
        // through the renderer so that a theme-palette regression cannot
        // silently ship with a light-only assertion suite.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-red-ptype',
            type: AppMessageType.operator,
            content: 'P告知本文',
            userId: null,
            userName: 'P公式',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            themeMode: AppThemeMode.protanopia,
          ),
        );

        final AppThemeColors themeColors = AppTheme.colorsFor(
          AppThemeMode.protanopia,
        );

        final RichText bodyRichText = findRichTextContaining(tester, 'P告知本文');
        final Color? bodyColor = findSpanColor(bodyRichText.text, 'P告知本文');
        expect(
          bodyColor,
          themeColors.operatorTextColor,
          reason:
              'operator body must render with protanopia operatorTextColor (#BF360C)',
        );

        final RichText metaRichText = findRichTextContaining(tester, 'P公式');
        final Color? labelColor = findSpanColor(metaRichText.text, 'P公式');
        expect(
          labelColor,
          themeColors.operatorTextColor,
          reason:
              'operator userName label must also render with protanopia operatorTextColor',
        );
      },
    );

    test('clipboard formatting (one-line) for operator message', () {
      // Pins the exact clipboard line format the user would copy for an
      // operator (運営) message. The message normalizes with `userId=null`
      // but `userName='運営'`, so the formatter must still emit the label
      // via the shared display-name resolver (Policy A — broadcaster-supplied
      // name is preserved verbatim).
      final AppMessage operatorMessage = AppMessage(
        id: 'op-clip-1',
        timestamp: DateTime(2026, 3, 22, 12, 0, 0),
        userId: null,
        userName: '運営',
        content: 'お知らせ',
        type: AppMessageType.operator,
      );

      final String oneLine = commentLineTextForTesting(
        message: operatorMessage,
        showUserName: true,
      );
      expect(oneLine, '12:00:00  運営  お知らせ');
    });

    test('clipboard formatting (two-line) for operator message', () {
      final AppMessage operatorMessage = AppMessage(
        id: 'op-clip-2',
        timestamp: DateTime(2026, 3, 22, 12, 0, 0),
        userId: null,
        userName: '運営',
        content: 'お知らせ',
        type: AppMessageType.operator,
      );

      final String twoLine = commentLineTextForTesting(
        message: operatorMessage,
        showUserName: true,
        twoLine: true,
      );
      expect(twoLine, '12:00:00  運営\nお知らせ');
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
        programInfo: const CommentProgramInfo(lv: 'lv123'),
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (_, _) async {},
          onNicknameChanged: (String userId, String nickname) {
            lastNicknameUserId = userId;
            lastNickname = nickname;
          },
          onNicknameRemoved: (String userId) {
            lastRemovedUserId = userId;
            lastNickname = null;
          },
        ),
        autoNicknameRegistration: widget.autoNicknameRegistration,
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
        programInfo: CommentProgramInfo(lv: _lv),
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (String previous, String next) async {
            differentLvCallbackCount += 1;
            previousLv = previous;
            nextLv = next;
          },
        ),
        filterConfig: CommentFilterConfig(
          starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
        ),
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
  bool commentTwoLineEnabled = false,
  DateTime? beginAt,
  CommentLogWriter? commentLogWriter,
  bool autoSaveCommentLog = false,
  String autoSaveCommentLogPath = '',
  bool showOperatorComment = true,
  bool showSystemMessage = true,
  bool showEmotion = true,
  AppThemeMode themeMode = AppThemeMode.light,
}) {
  final UserNameResolution? userNameResolution = resolveUserName == null
      ? null
      : UserNameResolution(
          resolve: resolveUserName,
          requestResolve: (_) {},
          listenable: _NoopListenable.instance,
        );

  return MaterialApp(
    home: CommentScreen(
      programInfo: CommentProgramInfo(
        lv: lv,
        programTitle: programTitle,
        broadcasterName: broadcasterName,
        broadcasterUserId: broadcasterUserId,
        beginAt: beginAt,
        connectionMethod: connectionMethod,
      ),
      connectionSupervisor: supervisor,
      messages: messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: onStopAllConnections ?? () async {},
        onReconnectSameLv: onReconnectSameLv ?? () async {},
        onDifferentLvConnected: (_, _) async {},
        onOpenSettings: onOpenSettings,
      ),
      debugMode: debugMode,
      userNameResolution: userNameResolution,
      commentTwoLineEnabled: commentTwoLineEnabled,
      commentFontSize: commentFontSize,
      themeMode: themeMode,
      statistics: CommentStatisticsConfig(
        enabled: statisticsEnabled,
        viewerCommentEnabled: statisticsViewerCommentEnabled,
        activeUserEnabled: statisticsActiveUserEnabled,
        viewerCount: viewerCount,
        totalCommentCount: totalCommentCount,
        activeUserCount: activeUserCount,
      ),
      filterConfig: CommentFilterConfig(
        ngUserIds: ngUserIds,
        ngWords: ngWords,
        presetNgWords: presetNgWords,
        userColorMap: userColorMap,
        userNicknameMap: userNicknameMap,
        starPrefixHidingEnabled: starPrefixHidingEnabled,
        showOperatorComment: showOperatorComment,
        showSystemMessage: showSystemMessage,
        showEmotion: showEmotion,
      ),
      logConfig: CommentLogConfig(
        commentLogWriter: commentLogWriter,
        autoSaveCommentLog: autoSaveCommentLog,
        autoSaveCommentLogPath: autoSaveCommentLogPath,
      ),
    ),
  );
}

class _NoopListenable implements Listenable {
  const _NoopListenable._();

  static const _NoopListenable instance = _NoopListenable._();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
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
  String? userId = 'user-1',
  String? userName,
}) {
  return AppMessage(
    id: id,
    timestamp: DateTime(2026, 3, 22, 12, 0, 0),
    userId: userId,
    userName: userName,
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

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];
  PreferredLaunchMode? lastLaunchMode;
  bool shouldSucceed = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    lastLaunchMode = options.mode;
    return shouldSucceed;
  }
}
