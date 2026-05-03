import 'dart:collection';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/data/comment_log/comment_log_writer.dart';
import 'package:comerune/domain/matchers/ng_matcher.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:comerune/domain/models/ng_policy.dart';
import 'package:comerune/domain/models/ng_preset_category.dart';
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
      supervisor.recordReceivedAt(timestamp: DateTime(2026, 3, 22, 12, 34, 56));
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
        ),
      );

      expect(find.text('lv: lv777'), findsOneWidget);
      expect(find.text('再接続: 1回'), findsOneWidget);

      final Text lastReceived = tester.widget(
        find.byKey(const Key('status-last-received')),
      );
      expect(lastReceived.data, '最終受信: 12:34:56');
    });

    testWidgets(
      'debug row consolidates broadcasterId / lastReceived / reconnect',
      (WidgetTester tester) async {
        // UX request (2026-04-25): keep the comment list as tall as
        // possible by collapsing the debug-only metadata into a single
        // wrapping row instead of two stacked rows.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        supervisor.recordReceivedAt(
          timestamp: DateTime(2026, 3, 22, 12, 34, 56),
        );

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: const <AppMessage>[],
            debugMode: true,
            broadcasterUserId: '12345678',
          ),
        );

        final Finder broadcasterId = find.byKey(
          const Key('status-broadcaster-user-id'),
        );
        final Finder lastReceived = find.byKey(
          const Key('status-last-received'),
        );
        final Finder reconnect = find.byKey(
          const Key('status-reconnect-count'),
        );

        expect(broadcasterId, findsOneWidget);
        expect(lastReceived, findsOneWidget);
        expect(reconnect, findsOneWidget);

        Wrap ancestorWrapOf(Finder child) {
          return tester.widget<Wrap>(
            find.ancestor(of: child, matching: find.byType(Wrap)).first,
          );
        }

        // All three live under the same parent Wrap.
        expect(
          ancestorWrapOf(broadcasterId),
          same(ancestorWrapOf(lastReceived)),
        );
        expect(ancestorWrapOf(lastReceived), same(ancestorWrapOf(reconnect)));

        // Style consistency: all three share the same subtle debug
        // font size + color so the row reads as one piece of metadata
        // rather than as three different signals.
        TextStyle styleOf(Finder f) =>
            tester.widget<Text>(f).style ?? const TextStyle();
        final TextStyle bidStyle = styleOf(broadcasterId);
        expect(bidStyle.fontSize, 12);
        expect(styleOf(lastReceived).fontSize, bidStyle.fontSize);
        expect(styleOf(reconnect).fontSize, bidStyle.fontSize);
        expect(styleOf(lastReceived).color, bidStyle.color);
        expect(styleOf(reconnect).color, bidStyle.color);
      },
    );

    testWidgets('comment row colors are applied by message type', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final AppThemeColors themeColors = AppTheme.colorsFor(AppThemeMode.light);
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
      expect(operatorRow.color, themeColors.operatorMessageBackground);

      final Container notificationRow = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-notification-1')),
          matching: find.byType(Container),
        ),
      );
      expect(notificationRow.color, themeColors.notificationMessageBackground);

      final Container legacyRow = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-legacy-1')),
          matching: find.byType(Container),
        ),
      );
      expect(legacyRow.color, themeColors.notificationMessageBackground);
      expect(
        find.textContaining(kLegacyUnsupportedFormatMessage),
        findsOneWidget,
      );
    });

    // Dark-mode regression lock: the largest palette shift in the "soften
    // comment-row backgrounds" change lives in dark mode (notification
    // #0D47A1 -> #282A2E). A light-only UI test would silently pass even if
    // the dark palette or its renderer path regressed, so cover dark here.
    testWidgets(
      'comment row colors use dark-theme palette when themeMode=dark',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final AppThemeColors darkColors = AppTheme.colorsFor(AppThemeMode.dark);
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'chat-1', type: AppMessageType.chat, content: '通常'),
          _message(
            id: 'operator-1',
            type: AppMessageType.operator,
            content: '運営',
          ),
          _message(
            id: 'notification-1',
            type: AppMessageType.notification,
            content: '通知',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            themeMode: AppThemeMode.dark,
          ),
        );

        final Container operatorRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-operator-1')),
            matching: find.byType(Container),
          ),
        );
        expect(operatorRow.color, darkColors.operatorMessageBackground);

        final Container notificationRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-notification-1')),
            matching: find.byType(Container),
          ),
        );
        expect(notificationRow.color, darkColors.notificationMessageBackground);
      },
    );

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

    testWidgets(
      'gift and nicoad messages are excluded from saved comment logs',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final _FakeCommentLogWriter commentLogWriter = _FakeCommentLogWriter();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'chat-real',
            type: AppMessageType.chat,
            content: '通常コメント',
          ),
          _message(id: 'gift-1', type: AppMessageType.gift, content: 'ギフト'),
          _message(
            id: 'nicoad-1',
            type: AppMessageType.nicoad,
            content: 'ニコニ広告',
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

        // Only the plain chat message should be persisted; gift / nicoad are
        // excluded to preserve the CommentLogWriter contract even though they
        // now bypass NG filters and are visible in the UI.
        expect(commentLogWriter.lastSavedMessages, hasLength(1));
        expect(commentLogWriter.lastSavedMessages!.single.id, 'chat-real');
      },
    );

    group('log writer exclusion table', () {
      // Table-driven coverage for _shouldIncludeInStatsAndLogs: for each
      // message type we verify whether it is persisted into the saved comment
      // log. chat / operator / notification pass through; gift / nicoad and
      // the system broadcast-ended row are excluded.
      final List<({String label, AppMessage input, bool expectedPersisted})>
      cases = <({String label, AppMessage input, bool expectedPersisted})>[
        (
          label: 'chat is persisted',
          input: _message(
            id: 'chat-1',
            type: AppMessageType.chat,
            content: '通常コメント',
          ),
          expectedPersisted: true,
        ),
        (
          label: 'operator is persisted',
          input: _message(
            id: 'operator-1',
            type: AppMessageType.operator,
            content: '運営コメント',
          ),
          expectedPersisted: true,
        ),
        (
          label: 'notification is persisted',
          input: _message(
            id: 'notification-1',
            type: AppMessageType.notification,
            content: 'お知らせ',
          ),
          expectedPersisted: true,
        ),
        (
          label: 'system broadcast-ended notification is excluded',
          input: AppMessage(
            id: '${kSystemBroadcastEndedMessageIdPrefix}42',
            timestamp: DateTime(2026, 3, 22, 12, 35, 0),
            content: '放送が終了しました',
            type: AppMessageType.notification,
          ),
          expectedPersisted: false,
        ),
        (
          label: 'gift is excluded',
          input: _message(
            id: 'gift-1',
            type: AppMessageType.gift,
            content: 'ギフト',
          ),
          expectedPersisted: false,
        ),
        (
          label: 'nicoad is excluded',
          input: _message(
            id: 'nicoad-1',
            type: AppMessageType.nicoad,
            content: 'ニコニ広告',
          ),
          expectedPersisted: false,
        ),
      ];

      for (final ({String label, AppMessage input, bool expectedPersisted})
          testCase
          in cases) {
        testWidgets('${testCase.label} in saved comment log', (
          WidgetTester tester,
        ) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final _FakeCommentLogWriter commentLogWriter =
              _FakeCommentLogWriter();

          await tester.pumpWidget(
            _buildScreen(
              supervisor: supervisor,
              messages: <AppMessage>[testCase.input],
              autoSaveCommentLog: true,
              commentLogWriter: commentLogWriter,
            ),
          );
          await tester.pumpAndSettle();

          expect(supervisor.endBroadcast(), isTrue);
          await tester.pumpAndSettle();

          final List<AppMessage> saved =
              commentLogWriter.lastSavedMessages ?? const <AppMessage>[];
          final bool persisted = saved.any(
            (AppMessage m) => m.id == testCase.input.id,
          );
          expect(
            persisted,
            testCase.expectedPersisted,
            reason:
                'type=${testCase.input.type} id=${testCase.input.id} '
                'expectedPersisted=${testCase.expectedPersisted}',
          );
        });
      }
    });

    testWidgets(
      'renders gift and nicoad messages with shaded background when emphasize is enabled',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final AppThemeColors themeColors = AppTheme.colorsFor(
          AppThemeMode.light,
        );
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'chat-visible',
            type: AppMessageType.chat,
            content: '通常コメント',
          ),
          _message(id: 'gift-1', type: AppMessageType.gift, content: 'ギフト'),
          _message(
            id: 'nicoad-1',
            type: AppMessageType.nicoad,
            content: 'ニコニ広告',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        expect(
          find.byKey(const Key('comment-row-chat-visible')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('comment-row-gift-1')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-nicoad-1')), findsOneWidget);
        expect(find.textContaining('ギフト'), findsWidgets);
        expect(find.textContaining('ニコニ広告'), findsWidgets);

        final Container giftRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-gift-1')),
            matching: find.byType(Container),
          ),
        );
        expect(giftRow.color, themeColors.giftMessageBackground);

        final Container nicoadRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-nicoad-1')),
            matching: find.byType(Container),
          ),
        );
        expect(nicoadRow.color, themeColors.nicoadMessageBackground);

        // Leading type icons should be rendered.
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-gift-1')),
            matching: find.byIcon(Icons.card_giftcard),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-nicoad-1')),
            matching: find.byIcon(Icons.campaign),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'gift and nicoad messages render like chat when emphasize is disabled',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'gift-1', type: AppMessageType.gift, content: 'ギフト'),
          _message(
            id: 'nicoad-1',
            type: AppMessageType.nicoad,
            content: 'ニコニ広告',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            emphasizeGiftNicoadComment: false,
          ),
        );

        expect(find.byKey(const Key('comment-row-gift-1')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-nicoad-1')), findsOneWidget);

        final Container giftRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-gift-1')),
            matching: find.byType(Container),
          ),
        );
        expect(giftRow.color, isNull);

        final Container nicoadRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-nicoad-1')),
            matching: find.byType(Container),
          ),
        );
        expect(nicoadRow.color, isNull);

        // No leading type icons should be rendered when emphasis is off.
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-gift-1')),
            matching: find.byIcon(Icons.card_giftcard),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-nicoad-1')),
            matching: find.byIcon(Icons.campaign),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'enabling emphasize does not add icons to non-gift/nicoad rows',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final AppThemeColors themeColors = AppTheme.colorsFor(
          AppThemeMode.light,
        );
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'chat-1', type: AppMessageType.chat, content: 'A'),
          _message(
            id: 'operator-1',
            type: AppMessageType.operator,
            content: 'B',
          ),
          _message(
            id: 'notification-1',
            type: AppMessageType.notification,
            content: 'C',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        // Chat / operator / notification rows must not gain gift/nicoad icons.
        expect(find.byIcon(Icons.card_giftcard), findsNothing);
        expect(find.byIcon(Icons.campaign), findsNothing);

        // Existing backgrounds should be unchanged.
        final Container operatorRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-operator-1')),
            matching: find.byType(Container),
          ),
        );
        expect(operatorRow.color, themeColors.operatorMessageBackground);

        final Container notificationRow = tester.widget(
          find.descendant(
            of: find.byKey(const Key('comment-row-notification-1')),
            matching: find.byType(Container),
          ),
        );
        expect(
          notificationRow.color,
          themeColors.notificationMessageBackground,
        );
      },
    );

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

      // The save action now lives inside the AppBar overflow menu. Open the
      // menu first, then assert the menu entry carries the archive icon and
      // label.
      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();

      final Finder saveItem = find.byKey(const Key('save-comment-log-button'));
      expect(saveItem, findsOneWidget);
      expect(
        find.descendant(
          of: saveItem,
          matching: find.byIcon(Icons.archive_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: saveItem, matching: find.text('コメントログを保存')),
        findsOneWidget,
      );
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

    // Issue #671: auto-scroll regression contracts.
    //
    // These tests pin four axes that PR #664 did not explicitly cover:
    //   (1) descending sort — `_scrollToEdge` uses offset 0 and the edge is
    //       judged by `_isNearTop`; a new message arrival must still follow
    //       the edge (top = most recent).
    //   (2) search active — auto-scroll must be suppressed; a new message
    //       arrival must not move `pixels`.
    //   (3) empty → non-empty → empty → non-empty cursor transitions — the
    //       `_lastAutoScrollObservedLastId` seed/reset must handle nulls
    //       without forcing a scroll-to-edge on a non-new tail.
    //   (4) lv change cursor reseed — swapping `programInfo.lv` via
    //       [_CommentScreenHostState.changeLv] should reseed the cursor so
    //       messages already present on the new lv do not replay a scroll.
    //
    // Tolerance decisions: 1.0 px is enough to absorb sub-pixel rounding on
    // `jumpTo`/`animateTo` without masking a real regression. Where the
    // `_scrollToEdge` animation runs (180 ms easeOut), the tests pump with
    // `pumpAndSettle` to reach steady state deterministically instead of
    // relying on `Future.delayed`.
    testWidgets(
      'auto-scroll follows top edge in descending sort when new messages arrive',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_CommentScreenHostState> hostKey =
            GlobalKey<_CommentScreenHostState>();

        await tester.pumpWidget(
          _CommentScreenHost(
            key: hostKey,
            supervisor: supervisor,
            initialLv: 'lv-desc',
            initialMessages: List<AppMessage>.generate(
              40,
              (int index) => _message(
                id: 'desc-initial-$index',
                type: AppMessageType.chat,
                content: 'comment-$index',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Switch to descending sort. The post-frame `_scrollToEdge` after
        // toggling should settle the viewport at offset 0 (top), because in
        // descending sort the tail of the data list is rendered at the top
        // of the ListView.
        await tester.tap(find.byKey(const Key('sort-toggle-button')));
        await tester.pumpAndSettle();

        final ListView listView = tester.widget(
          find.byKey(const Key('comment-list')),
        );
        final ScrollController controller = listView.controller!;

        expect(
          controller.position.pixels,
          closeTo(0, 1),
          reason:
              'descending sort should place the viewport at offset 0 '
              '(top = most recent) after the toggle settles',
        );

        // A new live message lands — in descending sort the new tail becomes
        // the new top row, and auto-scroll must keep offset pinned to 0.
        hostKey.currentState!.addMessage(
          _message(
            id: 'desc-new-1',
            type: AppMessageType.chat,
            content: 'new-comment-1',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          controller.position.pixels,
          closeTo(0, 1),
          reason:
              'new message arrival in descending sort must keep offset at '
              'the top edge (0), not drift toward maxScrollExtent',
        );
      },
    );

    testWidgets('auto-scroll is suppressed while search is active', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_CommentScreenHostState> hostKey =
          GlobalKey<_CommentScreenHostState>();

      await tester.pumpWidget(
        _CommentScreenHost(
          key: hostKey,
          supervisor: supervisor,
          initialLv: 'lv-search',
          initialMessages: List<AppMessage>.generate(
            40,
            (int index) => _message(
              id: 'search-initial-$index',
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

      // Enter search mode via the overflow menu (same path as users).
      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('comment-search-field')),
        findsOneWidget,
        reason: 'search field must be mounted for _isSearching=true',
      );

      // Scroll away from the tail so a potential auto-scroll would be
      // visible as a pixel change. In ascending sort "away from tail"
      // means scrolling up.
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, 300),
      );
      await tester.pumpAndSettle();
      final double pixelsBefore = controller.position.pixels;

      // A new message arrives while search is active. Auto-scroll must
      // NOT run, so `pixels` must remain at `pixelsBefore`.
      hostKey.currentState!.addMessage(
        _message(
          id: 'search-new-1',
          type: AppMessageType.chat,
          content: 'new-comment-while-searching',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        controller.position.pixels,
        closeTo(pixelsBefore, 1),
        reason:
            'while _isSearching=true, a new message arrival must not move '
            'the scroll position',
      );
    });

    testWidgets(
      'auto-scroll cursor handles empty → non-empty → empty → non-empty transitions',
      (WidgetTester tester) async {
        // Issue #671 scenario 3: when messages go empty and then non-empty
        // again, `_lastAutoScrollObservedLastId` must be reset to null so
        // that the next arrival is correctly treated as "new" exactly once,
        // without replaying prior ids. The regression surface is that if
        // the cursor were left at the previous list's last id, the first
        // message on the *new* non-empty tail would still be compared
        // against a stale cursor — we assert here that re-appearing the
        // *same* id after an empty transition does not cause an auto-scroll
        // loop (no crash, pixel stays at the tail edge).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_CommentScreenHostState> hostKey =
            GlobalKey<_CommentScreenHostState>();

        await tester.pumpWidget(
          _CommentScreenHost(
            key: hostKey,
            supervisor: supervisor,
            initialLv: 'lv-empty',
            initialMessages: const <AppMessage>[],
          ),
        );
        await tester.pumpAndSettle();

        final ListView listView = tester.widget(
          find.byKey(const Key('comment-list')),
        );
        final ScrollController controller = listView.controller!;

        // empty → non-empty: first message should not trip on a null cursor
        // and the viewport must follow the edge.
        hostKey.currentState!.replaceMessages(<AppMessage>[
          _message(
            id: 'transition-1',
            type: AppMessageType.chat,
            content: 'first-message',
          ),
        ]);
        await tester.pumpAndSettle();
        expect(
          controller.position.pixels,
          closeTo(controller.position.maxScrollExtent, 1),
          reason:
              'first non-empty transition should leave viewport at the '
              'bottom edge in ascending sort',
        );

        // non-empty → empty: cursor seed must tolerate the list shrinking
        // back to zero without crashing.
        hostKey.currentState!.replaceMessages(const <AppMessage>[]);
        await tester.pumpAndSettle();

        // empty → non-empty again, reusing the *same* id. The cursor must
        // have been reset (or must not force a replay), so the viewport
        // still ends at the bottom edge and no exception is thrown.
        hostKey.currentState!.replaceMessages(<AppMessage>[
          _message(
            id: 'transition-1',
            type: AppMessageType.chat,
            content: 'first-message',
          ),
          _message(
            id: 'transition-2',
            type: AppMessageType.chat,
            content: 'second-message',
          ),
        ]);
        await tester.pumpAndSettle();

        expect(
          controller.position.pixels,
          closeTo(controller.position.maxScrollExtent, 1),
          reason:
              'after empty → non-empty → empty → non-empty, the viewport '
              'must still follow the tail edge',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'empty/non-empty transitions must not throw',
        );
      },
    );

    testWidgets(
      'lv change reseeds auto-scroll cursor so prefilled tail does not replay',
      (WidgetTester tester) async {
        // Issue #671 scenario 4: `didUpdateWidget` must reset
        // `_lastAutoScrollObservedLastId` to the new lv's current tail id
        // when `programInfo.lv` changes. Otherwise a stale cursor from the
        // previous lv could match (or mismatch) against the new tail and
        // cause spurious scroll jumps. We exercise the reseed via the
        // in-test `_CommentScreenHost` helper rather than a real Navigator
        // push, so the `CommentScreen` is rebuilt in place.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_CommentScreenHostState> hostKey =
            GlobalKey<_CommentScreenHostState>();

        await tester.pumpWidget(
          _CommentScreenHost(
            key: hostKey,
            supervisor: supervisor,
            initialLv: 'lv-before',
            initialMessages: List<AppMessage>.generate(
              40,
              (int index) => _message(
                id: 'before-$index',
                type: AppMessageType.chat,
                content: 'before-$index',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ListView listView = tester.widget(
          find.byKey(const Key('comment-list')),
        );
        final ScrollController controller = listView.controller!;

        // Scroll up so that, if the lv change incorrectly reuses the old
        // cursor and treats the prefilled tail as "new", a spurious
        // `_scrollToEdge` would visibly snap the viewport back to the
        // bottom. We capture the current position as the baseline to
        // defend against that.
        await tester.drag(
          find.byKey(const Key('comment-list')),
          const Offset(0, 300),
        );
        await tester.pumpAndSettle();
        final double pixelsBeforeLvChange = controller.position.pixels;

        // Swap to a new lv whose message list already has a tail (the
        // cursor must be seeded to that tail, not left at the previous
        // lv's cursor). The two synchronous `setState` calls below are
        // coalesced by the framework into a single pending rebuild, so
        // the following `pumpAndSettle` delivers both deltas to
        // `CommentScreen.didUpdateWidget` in one frame — matching
        // production navigation where lv and messages change together.
        hostKey.currentState!.changeLv('lv-after');
        hostKey.currentState!.replaceMessages(
          List<AppMessage>.generate(
            30,
            (int index) => _message(
              id: 'after-$index',
              type: AppMessageType.chat,
              content: 'after-$index',
            ),
          ),
        );
        await tester.pumpAndSettle();

        // On lv change the screen explicitly scrolls to the edge after
        // the next frame, so after settling the viewport must be at the
        // bottom edge (not at `pixelsBeforeLvChange`). lv change
        // intentionally resets the view; the contract we pin is that
        // the cursor is reseeded and no further replay happens on the
        // *next* new message.
        expect(
          controller.position.pixels,
          closeTo(controller.position.maxScrollExtent, 1),
          reason:
              'lv change should settle the viewport at the new tail edge '
              'after the post-frame scroll-to-edge runs',
        );
        expect(
          controller.position.pixels,
          isNot(closeTo(pixelsBeforeLvChange, 1)),
          reason:
              'lv change must reset the view, so pixels must differ from '
              'the pre-change scroll position (guards against the cursor '
              'leaking across lvs and suppressing the reset)',
        );

        // A further ring-buffer rotation that keeps the list length but
        // swaps the tail must still trigger exactly one edge follow — the
        // reseeded cursor recognises the new tail id as new. If the cursor
        // had leaked across lvs, the comparison below would be fragile.
        final List<AppMessage> rotated = <AppMessage>[
          for (int index = 1; index < 30; index++)
            _message(
              id: 'after-$index',
              type: AppMessageType.chat,
              content: 'after-$index',
            ),
          _message(
            id: 'after-new-tail',
            type: AppMessageType.chat,
            content: 'after-new-tail',
          ),
        ];
        hostKey.currentState!.replaceMessages(rotated);
        await tester.pumpAndSettle();

        expect(
          controller.position.pixels,
          closeTo(controller.position.maxScrollExtent, 1),
          reason:
              'post-lv-change ring-buffer rotation must still follow the '
              'tail edge via the reseeded cursor',
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

    testWidgets('shows failure detail in snackbar', (
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
    });

    testWidgets('shows non-retryable notice when error code is not retryable', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: const <AppMessage>[]),
      );

      // lvParseFailed は再試行しても状況が変わらない分類。
      expect(supervisor.fail(ConnectionErrorCode.lvParseFailed), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('再接続しても解消しません。'), findsOneWidget);
      expect(find.textContaining('再接続ボタンで再試行できます。'), findsNothing);
    });

    testWidgets(
      'debug snackbar composes non-retryable notice with code and detail',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: const <AppMessage>[],
            debugMode: true,
          ),
        );

        // 非 retryable エラー + デバッグモードで、既存の
        // 「[code: ...] 原因: ...」形式を維持しつつ誘導文だけが切り替わる
        // ことを保証する（Issue #639 cause 3）。
        expect(
          supervisor.fail(
            ConnectionErrorCode.lvParseFailed,
            errorDetail: 'invalid lv format',
          ),
          isTrue,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('code: LV_PARSE_FAILED'), findsOneWidget);
        expect(find.textContaining('原因: invalid lv format'), findsOneWidget);
        expect(find.textContaining('再接続しても解消しません。'), findsOneWidget);
        expect(find.textContaining('再接続ボタンで再試行できます。'), findsNothing);
      },
    );

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
    });

    testWidgets(
      'shows broadcaster user ID in expanded status bar (debug mode)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: const <AppMessage>[],
            broadcasterName: '配信者テスト',
            broadcasterUserId: '12345678',
            debugMode: true,
          ),
        );
        expect(
          find.byKey(const Key('status-broadcaster-user-id')),
          findsOneWidget,
        );
        expect(find.text('放送者ID: 12345678'), findsOneWidget);
      },
    );

    testWidgets('hides broadcaster user ID when null (debug mode)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          broadcasterName: '配信者テスト',
          debugMode: true,
        ),
      );
      expect(find.byKey(const Key('status-broadcaster-user-id')), findsNothing);
    });

    testWidgets('broadcaster user ID hidden after auto-collapse (debug mode)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          broadcasterName: '配信者X',
          broadcasterUserId: '99999',
          debugMode: true,
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

    testWidgets('debug info hidden in normal mode', (
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
      expect(find.byKey(const Key('status-last-received')), findsNothing);
      expect(find.byKey(const Key('status-reconnect-count')), findsNothing);
      expect(find.byKey(const Key('status-broadcaster-user-id')), findsNothing);
      expect(find.text('放送者ID: 12345678'), findsNothing);
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

    testWidgets(
      'initial commentSortOrder=descending shows comments newest-first '
      'and sets the matching tooltip (#774)',
      (WidgetTester tester) async {
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
            commentSortOrder: CommentSortOrder.descending,
          ),
        );

        // Newest comment ("second") should be drawn above the older one
        // ("first") right from the first build, because the persisted
        // descending order is honored without needing a button tap.
        final Finder firstRow = find.byKey(const Key('comment-row-first'));
        final Finder secondRow = find.byKey(const Key('comment-row-second'));
        expect(firstRow, findsOneWidget);
        expect(secondRow, findsOneWidget);
        final double firstY = tester.getTopLeft(firstRow).dy;
        final double secondY = tester.getTopLeft(secondRow).dy;
        expect(secondY, lessThan(firstY));

        // Tooltip should reflect "古い順に切替" because we are currently
        // showing newest-first (descending).
        final IconButton button = tester.widget<IconButton>(
          find.byKey(const Key('sort-toggle-button')),
        );
        expect(button.tooltip, '古い順に切替');
      },
    );

    testWidgets(
      '_toggleSortOrder invokes onSortOrderChanged with the new order (#774)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<CommentSortOrder> received = <CommentSortOrder>[];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: const <AppMessage>[],
            onSortOrderChanged: received.add,
          ),
        );

        // Default starts at ascending. Tapping flips to descending.
        await tester.tap(find.byKey(const Key('sort-toggle-button')));
        await tester.pumpAndSettle();

        expect(received, <CommentSortOrder>[CommentSortOrder.descending]);

        // Tapping again flips back to ascending and the callback is
        // invoked with the new value (not just the toggle event).
        await tester.tap(find.byKey(const Key('sort-toggle-button')));
        await tester.pumpAndSettle();

        expect(received, <CommentSortOrder>[
          CommentSortOrder.descending,
          CommentSortOrder.ascending,
        ]);
      },
    );

    testWidgets('tapping the toggle when initial commentSortOrder=descending '
        'reverses the visible order back to ascending and emits ascending '
        'via the callback (#774)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<CommentSortOrder> received = <CommentSortOrder>[];
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
          commentSortOrder: CommentSortOrder.descending,
          onSortOrderChanged: received.add,
        ),
      );

      // Sanity check: starts in descending (newest-first).
      final Finder firstRow = find.byKey(const Key('comment-row-first'));
      final Finder secondRow = find.byKey(const Key('comment-row-second'));
      final double firstYBefore = tester.getTopLeft(firstRow).dy;
      final double secondYBefore = tester.getTopLeft(secondRow).dy;
      expect(secondYBefore, lessThan(firstYBefore));

      // Tap the toggle: should flip to ascending.
      await tester.tap(find.byKey(const Key('sort-toggle-button')));
      await tester.pumpAndSettle();

      // Visible order is reversed (older comment now on top).
      final double firstYAfter = tester.getTopLeft(firstRow).dy;
      final double secondYAfter = tester.getTopLeft(secondRow).dy;
      expect(firstYAfter, lessThan(secondYAfter));

      // Tooltip now reflects the inverse direction.
      final IconButton button = tester.widget<IconButton>(
        find.byKey(const Key('sort-toggle-button')),
      );
      expect(button.tooltip, '新しい順に切替');

      // Callback emitted exactly the new (ascending) value.
      expect(received, <CommentSortOrder>[CommentSortOrder.ascending]);
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

    testWidgets(
      'gift / nicoad messages bypass NG user filter and stay visible',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'gift-ng-user',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-ng',
            content: 'ギフト送信',
            type: AppMessageType.gift,
          ),
          AppMessage(
            id: 'nicoad-ng-user',
            timestamp: DateTime(2026, 3, 22, 12, 0, 1),
            userId: 'user-ng',
            content: 'ニコニ広告',
            type: AppMessageType.nicoad,
          ),
          AppMessage(
            id: 'chat-ng-user',
            timestamp: DateTime(2026, 3, 22, 12, 0, 2),
            userId: 'user-ng',
            content: 'NG ユーザーのチャット',
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

        // gift / nicoad must not be hidden even when their userId matches NG.
        expect(
          find.byKey(const Key('comment-row-gift-ng-user')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('comment-row-nicoad-ng-user')),
          findsOneWidget,
        );
        // Regular chat from the same NG user stays filtered (regression guard).
        expect(find.byKey(const Key('comment-row-chat-ng-user')), findsNothing);
      },
    );

    testWidgets(
      'gift / nicoad messages bypass NG word filter and stay visible',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          AppMessage(
            id: 'gift-ng-word',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-1',
            content: '広告主さんからのギフト',
            type: AppMessageType.gift,
          ),
          AppMessage(
            id: 'nicoad-ng-word',
            timestamp: DateTime(2026, 3, 22, 12, 0, 1),
            userId: 'user-2',
            content: '広告主さんのニコニ広告',
            type: AppMessageType.nicoad,
          ),
          AppMessage(
            id: 'chat-ng-word',
            timestamp: DateTime(2026, 3, 22, 12, 0, 2),
            userId: 'user-3',
            content: '広告主からのメッセージ',
            type: AppMessageType.chat,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            ngWords: const <String>['広告主'],
          ),
        );

        // gift / nicoad must not be hidden even when their content matches an
        // NG word (e.g. an advertiser name).
        expect(
          find.byKey(const Key('comment-row-gift-ng-word')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('comment-row-nicoad-ng-word')),
          findsOneWidget,
        );
        // Regular chat containing the same NG word stays filtered.
        expect(find.byKey(const Key('comment-row-chat-ng-word')), findsNothing);
      },
    );

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

    testWidgets('statistics hides リスナー row entirely when viewerCount is null', (
      WidgetTester tester,
    ) async {
      // The viewer count comes from NDGR
      // `NicoliveMessage.statistics.viewers`, which the proto
      // decoder does not yet extract (tracked in Issue #724). Until
      // that lands, surface no row at all so users do not mistake
      // the "-" placeholder for "0 listeners".
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          statisticsEnabled: true,
          statisticsViewerCommentEnabled: true,
          statisticsActiveUserEnabled: true,
          // viewerCount intentionally omitted (defaults to null).
          totalCommentCount: 50,
          activeUserCount: 10,
        ),
      );

      expect(find.byKey(const Key('status-viewer-count')), findsNothing);
      expect(find.textContaining('リスナー'), findsNothing);
      expect(find.text('コメント: 50'), findsOneWidget);
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

      // Settings now lives inside the AppBar overflow menu; open it first.
      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
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

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
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

      // Opening the overflow menu must not reveal a settings entry when the
      // callback is null.
      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
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

    // Issue #670: regression — when widget.messages is an UnmodifiableListView
    // over the same mutable list (the production shape used by TimelineStore),
    // the diff-based gate `oldWidget.messages != widget.messages` always
    // evaluated to "no change" and never invoked the nickname / NG-protection /
    // userName-resolve / debug-log callbacks. The fix introduces a
    // state-local tail cursor (`_lastProcessedTailMessageId`) so these
    // callbacks fire correctly even under the live-view aliasing.
    testWidgets(
      '@name comment fires nickname callback even with shared mutable list '
      '(Issue #670 regression)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_SharedListNicknameHostState> hostKey =
            GlobalKey<_SharedListNicknameHostState>();

        await tester.pumpWidget(
          _SharedListNicknameHost(key: hostKey, supervisor: supervisor),
        );

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'msg-shared-1',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-shared-1',
            content: '@はなこ',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();

        expect(hostKey.currentState!.lastNicknameUserId, 'user-shared-1');
        expect(hostKey.currentState!.lastNickname, 'はなこ');
      },
    );

    // Issue #670: regression — the cursor must be seeded with the tail of
    // the initial messages list so that historic backfill (e.g. past-comment
    // fetch already populated in TimelineStore before navigation) is NOT
    // retroactively replayed through the nickname pipeline on first mount.
    testWidgets('historic backfill present at mount does not trigger nickname '
        'callback (Issue #670 regression)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_SharedListNicknameHostState> hostKey =
          GlobalKey<_SharedListNicknameHostState>();

      // Seed backing list BEFORE pumpWidget so the initial CommentScreen
      // observes a non-empty messages list at initState — exactly the
      // backfill path TimelineStore exhibits in production after
      // past-comment fetch.
      await tester.pumpWidget(
        _SharedListNicknameHost(
          key: hostKey,
          supervisor: supervisor,
          initialMessages: <AppMessage>[
            AppMessage(
              id: 'msg-historic',
              timestamp: DateTime(2026, 3, 22, 11, 0, 0),
              userId: 'user-historic',
              content: '@昔の人',
              type: AppMessageType.chat,
            ),
          ],
        ),
      );
      await tester.pump();

      // Backfill must NOT fire the nickname callback retroactively.
      expect(hostKey.currentState!.lastNicknameUserId, isNull);
      expect(hostKey.currentState!.nicknameCallCount, 0);

      // A genuinely new comment after mount must still fire the callback.
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-fresh',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-fresh',
          content: '@新しい人',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();
      expect(hostKey.currentState!.lastNicknameUserId, 'user-fresh');
      expect(hostKey.currentState!.nicknameCallCount, 1);
    });

    // Issue #670 round-1 review (品質): ring-buffer rotation could evict
    // the cursor message itself, in which case `_sliceStartFromCursor`
    // falls back to processing the full tail. The nickname pipeline
    // de-duplicates by message id so a `@`-comment that survives the
    // rotation does not silently re-fire the callback (which would
    // otherwise overwrite a more recent registration with a stale value).
    testWidgets('ring-rotation eviction does not double-fire nickname callback '
        '(Issue #670 regression)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final GlobalKey<_SharedListNicknameHostState> hostKey =
          GlobalKey<_SharedListNicknameHostState>();

      await tester.pumpWidget(
        _SharedListNicknameHost(key: hostKey, supervisor: supervisor),
      );

      // Add a `@`-comment — fires once.
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-nick',
          timestamp: DateTime(2026, 3, 22, 12, 0, 0),
          userId: 'user-nick',
          content: '@A',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();
      expect(hostKey.currentState!.nicknameCallCount, 1);
      expect(hostKey.currentState!.lastNickname, 'A');

      // Round-2 review (品質): construct the genuine ring-rotation case
      // where the cursor anchor itself is evicted while the original
      // `@`-comment SURVIVES in the tail. _sliceStartFromCursor should
      // then fail to find the anchor, fall back to start=0, and iterate
      // over the surviving `@`-comment — which the de-dup set must
      // suppress.
      //
      //   1. Add 'msg-after' (regular text). Cursor advances to msg-after.
      //   2. Evict 'msg-nick' from the head. Tail is now [msg-after].
      //   3. Add a non-@ message 'msg-final' so a new arrival is observed
      //      AND in the same step evict the anchor 'msg-after' so the
      //      cursor anchor is missing while another @ still survives.
      //
      // To simulate "anchor missing while @-comment survives", we
      // re-add the previously evicted '@A' message id at the tail, so the
      // visible tail contains both 'msg-after' (anchor still present) +
      // 'msg-nick' (the surviving @-comment) — but with the anchor
      // evicted.
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-after',
          timestamp: DateTime(2026, 3, 22, 12, 0, 1),
          userId: 'user-other',
          content: 'hello',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();
      // Evict 'msg-nick' so the surviving tail is [msg-after].
      hostKey.currentState!.evictHead();
      await tester.pump();
      // Re-introduce a new message that contains the same '@A' content
      // but with a different id, simulating the same author re-issuing
      // the nickname comment AFTER rotation. This is a different message,
      // so it MUST fire (de-dup is by message id, not by user/content).
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-nick-2',
          timestamp: DateTime(2026, 3, 22, 12, 0, 2),
          userId: 'user-nick',
          content: '@B',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();
      // Now evict the cursor anchor 'msg-after' so a fresh arrival forces
      // the cursor-missing fallback path.
      hostKey.currentState!.evictHead();
      await tester.pump();
      // Force a fresh arrival. The de-dup set already contains 'msg-nick'
      // and 'msg-nick-2' (both fired earlier when they were observed as
      // genuinely new). _sliceStartFromCursor falls back to 0 because
      // the anchor 'msg-after' has been evicted; the loop revisits the
      // surviving `@`-message 'msg-nick-2' but the de-dup set blocks
      // a duplicate `onNicknameChanged` for it. The fresh, non-@
      // message itself does not fire either (different content).
      hostKey.currentState!.addMessage(
        AppMessage(
          id: 'msg-tail-fresh',
          timestamp: DateTime(2026, 3, 22, 12, 0, 3),
          userId: 'user-final',
          content: 'plain text',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();

      // Total nickname fires must be exactly 2: 'msg-nick' (@A) and
      // 'msg-nick-2' (@B) — each fired exactly once, even after
      // ring-rotation forced the fallback path.
      expect(hostKey.currentState!.nicknameCallCount, 2);
      expect(hostKey.currentState!.lastNickname, 'B');
    });

    // Issue #670 round-1 review (変化): a transition from non-empty to
    // empty messages (timeline clear) followed by re-population must NOT
    // retroactively replay the new tail through the nickname pipeline.
    // The cursor is null'd on empty and re-seeded on first non-empty
    // observation without firing callbacks.
    testWidgets(
      'timeline clear + re-population does not replay backfill through '
      'nickname callback (Issue #670 regression)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_SharedListNicknameHostState> hostKey =
            GlobalKey<_SharedListNicknameHostState>();

        await tester.pumpWidget(
          _SharedListNicknameHost(key: hostKey, supervisor: supervisor),
        );
        // Seed an arrival.
        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'msg-1',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-1',
            content: 'hello',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        expect(hostKey.currentState!.nicknameCallCount, 0);

        // Clear the timeline (mirrors `onReconnectSameLv` clearing
        // TimelineStore).
        hostKey.currentState!.evictHead();
        await tester.pump();
        // Re-populate with a `@`-comment as part of the new backfill.
        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'msg-backfill-nick',
            timestamp: DateTime(2026, 3, 22, 12, 0, 1),
            userId: 'user-bf',
            content: '@だれか',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        // Backfill should be absorbed silently (cursor seed only).
        expect(hostKey.currentState!.nicknameCallCount, 0);

        // A subsequent fresh `@`-comment after the seed must fire normally.
        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'msg-real',
            timestamp: DateTime(2026, 3, 22, 12, 0, 2),
            userId: 'user-real',
            content: '@リアル',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        expect(hostKey.currentState!.nicknameCallCount, 1);
        expect(hostKey.currentState!.lastNickname, 'リアル');
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

    testWidgets('broadcast end without messages still freezes elapsed timer', (
      WidgetTester tester,
    ) async {
      // Covers the path where the panel is never shown (no messages),
      // but `_endedAt` still needs to be set so the status-bar timer
      // stops ticking. Exercises the early-return side of
      // `_updateEndedAtForStatus`.
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final DateTime beginAt = DateTime.now().subtract(
        const Duration(minutes: 3),
      );

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: const <AppMessage>[],
          beginAt: beginAt,
        ),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();

      // No stats panel (no messages to summarize).
      expect(find.byKey(const Key('stats-panel')), findsNothing);

      // Elapsed label must be frozen even though the panel is absent.
      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      final String? frozen = (tester.widget(elapsedFinder) as Text).data;
      await tester.pump(const Duration(seconds: 3));
      expect((tester.widget(elapsedFinder) as Text).data, frozen);
    });

    testWidgets('shows end-of-broadcast SnackBar with "statistics" action', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      expect(supervisor.endBroadcast(), isTrue);
      // Pump once to apply state change, once more to flush the post-frame
      // callback that shows the SnackBar.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('broadcast-ended-stats-snackbar')),
        findsOneWidget,
      );
      expect(find.text('放送が終了しました'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, '統計を見る'), findsOneWidget);
    });

    testWidgets('SnackBar "統計を見る" action re-expands a minimized stats panel', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();
      await tester.pump();

      // Minimize the panel first.
      await tester.tap(find.byKey(const Key('stats-close-button')));
      await tester.pump();
      expect(find.byKey(const Key('stats-panel-minimized')), findsOneWidget);

      // Invoke the SnackBar action programmatically — tap via the
      // finder can fall outside the 800x600 test view, so we drive the
      // `onPressed` callback directly. This still exercises the wiring
      // between the SnackBarAction and the screen's re-open handler.
      final SnackBarAction action = tester.widget<SnackBarAction>(
        find.widgetWithText(SnackBarAction, '統計を見る'),
      );
      action.onPressed();
      await tester.pump();

      expect(find.byKey(const Key('stats-panel-expanded')), findsOneWidget);
      expect(find.byKey(const Key('stats-panel-minimized')), findsNothing);
    });

    testWidgets(
      'SnackBar action is a no-op after stats are cleared (reconnect)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        expect(supervisor.endBroadcast(), isTrue);
        await tester.pump();
        await tester.pump();

        final SnackBarAction action = tester.widget<SnackBarAction>(
          find.widgetWithText(SnackBarAction, '統計を見る'),
        );

        // Simulate a reconnect that clears pending stats before the user
        // taps the SnackBar action. Since `endBroadcast()` is a terminal
        // transition in the supervisor, we simply unmount the screen to
        // trigger the `mounted == false` / `_pendingStats == null` guard.
        await tester.pumpWidget(const SizedBox.shrink());

        // Must not throw and must not attempt to show a panel on the
        // detached screen.
        action.onPressed();
        await tester.pump();

        expect(find.byKey(const Key('stats-panel-expanded')), findsNothing);
      },
    );

    testWidgets('minimized stats panel can be re-expanded by tapping it', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      expect(supervisor.endBroadcast(), isTrue);
      await tester.pumpAndSettle();

      // Starts expanded.
      expect(find.byKey(const Key('stats-panel-expanded')), findsOneWidget);

      // Tap close icon → minimize.
      await tester.tap(find.byKey(const Key('stats-close-button')));
      await tester.pump();
      expect(find.byKey(const Key('stats-panel-minimized')), findsOneWidget);
      expect(find.byKey(const Key('stats-panel-expanded')), findsNothing);

      // Tap expand icon → expand again.
      await tester.tap(find.byKey(const Key('stats-panel-expand-button')));
      await tester.pump();
      expect(find.byKey(const Key('stats-panel-expanded')), findsOneWidget);
    });

    testWidgets('status bar elapsed label freezes after broadcast ends', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
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

      final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
      final Text before = tester.widget(elapsedFinder);
      final String? beforeText = before.data;
      expect(beforeText, isNotNull);

      // End the broadcast. The elapsed label should stop advancing even
      // as wall-clock time moves forward.
      expect(supervisor.endBroadcast(), isTrue);
      await tester.pump();
      final Text frozen = tester.widget(elapsedFinder);
      final String? frozenText = frozen.data;
      expect(frozenText, isNotNull);

      await tester.pump(const Duration(seconds: 3));
      final Text stillFrozen = tester.widget(elapsedFinder);
      expect(stillFrozen.data, frozenText);
    });

    testWidgets(
      'reconnect after stop clears stats panel and resumes elapsed ticking',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final DateTime beginAt = DateTime.now().subtract(
          const Duration(minutes: 5),
        );
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'c1', type: AppMessageType.chat, content: 'hello'),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            beginAt: beginAt,
          ),
        );

        // User stops the broadcast → stats panel should appear.
        expect(supervisor.stopByUser(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('stats-panel-expanded')), findsOneWidget);

        // User reconnects. The panel must disappear so it does not leak
        // stale stats into the new session.
        expect(supervisor.startConnection(), isTrue);
        expect(supervisor.onSessionWsConnected(), isTrue);
        expect(supervisor.onNdgrEndpointResolved(), isTrue);
        await tester.pump();
        expect(find.byKey(const Key('stats-panel-expanded')), findsNothing);
        expect(find.byKey(const Key('stats-panel-minimized')), findsNothing);

        // The elapsed label must still render and tick. It is present so
        // long as beginAt is provided; after reconnect endedAt is cleared
        // so the label no longer reads the frozen value.
        final Finder elapsedFinder = find.byKey(const Key('status-elapsed'));
        expect(elapsedFinder, findsOneWidget);
      },
    );

    group('NG protection notification', () {
      testWidgets(
        'does not show snackbar or badge when setting is OFF (default)',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: false,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-x',
              content: 'this is spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();

          expect(find.byType(SnackBar), findsNothing);
          expect(find.byKey(const Key('ng-protection-badge')), findsNothing);
        },
      );

      testWidgets('shows snackbar and badge on NG word match when ON', (
        WidgetTester tester,
      ) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_NgProtectionHostState> hostKey =
            GlobalKey<_NgProtectionHostState>();

        await tester.pumpWidget(
          _NgProtectionHost(
            key: hostKey,
            supervisor: supervisor,
            ngWords: const <String>['spam'],
            notificationEnabled: true,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'ng-1',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-x',
            content: 'hey spam here',
            type: AppMessageType.chat,
          ),
        );
        // First pump applies setState + schedules post-frame snackbar.
        await tester.pump();
        // Second pump flushes the post-frame callback.
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('「spam」'), findsOneWidget);
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
      });

      testWidgets('shows snackbar and badge on NG user match when ON', (
        WidgetTester tester,
      ) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_NgProtectionHostState> hostKey =
            GlobalKey<_NgProtectionHostState>();

        await tester.pumpWidget(
          _NgProtectionHost(
            key: hostKey,
            supervisor: supervisor,
            ngUserIds: const <String>{'blocked-user'},
            notificationEnabled: true,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'ng-user-1',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'blocked-user',
            content: 'any text',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('ユーザー'), findsOneWidget);
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
      });

      testWidgets(
        'second NG hit within 10 seconds keeps badge increasing but snackbar is not re-fired',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'first spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);

          // Dismiss the current snackbar so that any subsequent showSnackBar
          // call would be clearly observable.
          ScaffoldMessenger.of(
            tester.element(find.byType(CommentScreen)),
          ).hideCurrentSnackBar();
          await tester.pump(const Duration(seconds: 1));

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-2',
              timestamp: DateTime(2026, 3, 22, 12, 0, 1),
              userId: 'user-b',
              content: 'second spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          // Badge should reflect 2 hits, but snackbar should not re-appear
          // because we are still within the 10-second throttle window.
          expect(find.byType(SnackBar), findsNothing);
          expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
        },
      );

      testWidgets(
        'snackbar re-fires for a hit more than 10 seconds after the last',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          // Drive the NG-protection throttle window from a mutable "virtual
          // now" so the test can step past the 10-second window without
          // sleeping on the wall clock. The injected Clock reads this value
          // at each [_processNgProtectionNotifications] call.
          DateTime virtualNow = DateTime.utc(2026, 3, 22, 12, 0, 0);
          final Clock testClock = Clock(() => virtualNow);

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
              clock: testClock,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'first spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);

          // Advance the virtual clock past the 10-second throttle window.
          virtualNow = virtualNow.add(const Duration(seconds: 11));

          // Dismiss the current snackbar so a re-fire is clearly observable.
          ScaffoldMessenger.of(
            tester.element(find.byType(CommentScreen)),
          ).hideCurrentSnackBar();
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-2',
              timestamp: DateTime(2026, 3, 22, 12, 0, 11),
              userId: 'user-b',
              content: 'later spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          // Beyond the throttle window, the snackbar must fire again.
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
        },
      );

      testWidgets(
        'snackbar does not re-fire when the clock advances exactly to the '
        'throttle boundary minus one tick (<10s stays throttled)',
        (WidgetTester tester) async {
          // Regression guard for the boundary condition: elapsed >=
          // _protectionSnackBarWindow must be a closed boundary. Advancing
          // the clock to one microsecond before the window end must keep
          // the throttle engaged.
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          DateTime virtualNow = DateTime.utc(2026, 3, 22, 12, 0, 0);
          final Clock testClock = Clock(() => virtualNow);

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
              clock: testClock,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'first spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);

          ScaffoldMessenger.of(
            tester.element(find.byType(CommentScreen)),
          ).hideCurrentSnackBar();
          await tester.pump();

          // Advance to exactly one microsecond short of the 10-second
          // window: throttle must still be engaged, no re-fire.
          virtualNow = virtualNow.add(
            const Duration(seconds: 10) - const Duration(microseconds: 1),
          );

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-2',
              timestamp: DateTime(2026, 3, 22, 12, 0, 9),
              userId: 'user-b',
              content: 'near-boundary spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsNothing);
          expect(find.text('2'), findsOneWidget);
        },
      );

      testWidgets(
        'snackbar re-fires exactly at the 10-second boundary (>=10s)',
        (WidgetTester tester) async {
          // Complementary boundary test: at exactly 10 seconds elapsed the
          // throttle window has elapsed (elapsed >= window) and the
          // snackbar must re-fire.
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          DateTime virtualNow = DateTime.utc(2026, 3, 22, 12, 0, 0);
          final Clock testClock = Clock(() => virtualNow);

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
              clock: testClock,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'first spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);

          ScaffoldMessenger.of(
            tester.element(find.byType(CommentScreen)),
          ).hideCurrentSnackBar();
          await tester.pump();

          virtualNow = virtualNow.add(const Duration(seconds: 10));

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-2',
              timestamp: DateTime(2026, 3, 22, 12, 0, 10),
              userId: 'user-b',
              content: 'boundary spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
        },
      );

      testWidgets(
        'wall-clock rewind (NTP sync etc.) re-fires the snackbar rather than '
        'locking the throttle indefinitely',
        (WidgetTester tester) async {
          // Regression guard: the throttle must treat a negative elapsed
          // value as "fire now and reset" so that a backwards wall-clock
          // jump does not silence notifications forever.
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          DateTime virtualNow = DateTime.utc(2026, 3, 22, 12, 0, 0);
          final Clock testClock = Clock(() => virtualNow);

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
              clock: testClock,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'first spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);

          ScaffoldMessenger.of(
            tester.element(find.byType(CommentScreen)),
          ).hideCurrentSnackBar();
          await tester.pump();

          // Jump the clock backwards by 5 minutes to simulate an NTP or
          // manual wall-clock adjustment. Elapsed becomes negative.
          virtualNow = virtualNow.subtract(const Duration(minutes: 5));

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-2',
              timestamp: DateTime(2026, 3, 22, 11, 55, 0),
              userId: 'user-b',
              content: 'after rewind spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
        },
      );

      testWidgets(
        'sanitizes NG word containing emoji, newlines and zero-width chars without breaking surrogate pairs',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          // 21 face-with-tears-of-joy emoji (U+1F602, each is a surrogate
          // pair in UTF-16). UTF-16 length is 42 > 40, which would have
          // broken the previous substring-based truncate.
          final String emojiNgWord = '\u{1F602}' * 21;
          final String ngWordWithNoise = 'a\nb\tc\u200Bd\u202Ee$emojiNgWord';

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: <String>[ngWordWithNoise],
              notificationEnabled: true,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-emoji-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'hit: $ngWordWithNoise',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(SnackBar), findsOneWidget);

          // Extract the rendered snackbar text and verify:
          //  - no U+FFFD replacement character (would indicate a broken
          //    surrogate pair from substring slicing)
          //  - no newline/tab characters
          //  - no bidi override / zero-width characters
          final Iterable<Text> texts = tester.widgetList<Text>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ),
          );
          final String combined = texts.map((Text t) => t.data ?? '').join();
          expect(
            combined.contains('\uFFFD'),
            isFalse,
            reason: 'truncate split a surrogate pair',
          );
          expect(combined.contains('\n'), isFalse);
          expect(combined.contains('\t'), isFalse);
          expect(combined.contains('\u200B'), isFalse);
          expect(combined.contains('\u202E'), isFalse);
        },
      );

      testWidgets(
        'preserves ZWJ-composed emoji in the NG-user snackbar so family sequences are not split',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          // Family (man+woman+girl+boy) joined with ZWJ (U+200D). Must
          // render as a single grapheme; stripping ZWJ would split it
          // into four separate people in the snackbar.
          const String family =
              '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}'
              '\u200D\u{1F466}';
          // Variation selector (U+FE0F) on a base glyph (heart) verifies
          // VS15/16 is preserved alongside ZWJ.
          const String heart = '\u2764\uFE0F';
          final String ngUserId = 'user-$family$heart';

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngUserIds: <String>{ngUserId},
              notificationEnabled: true,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-zwj-user-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: ngUserId,
              content: 'any text',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(SnackBar), findsOneWidget);

          final Iterable<Text> texts = tester.widgetList<Text>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ),
          );
          final String combined = texts.map((Text t) => t.data ?? '').join();

          // ZWJ and VS16 must survive so the composed glyphs remain intact.
          expect(
            combined.contains('\u200D'),
            isTrue,
            reason: 'ZWJ (U+200D) must be preserved for family emoji',
          );
          expect(
            combined.contains('\uFE0F'),
            isTrue,
            reason: 'VS16 (U+FE0F) must be preserved for heart emoji',
          );
          expect(
            combined.contains(family),
            isTrue,
            reason: 'ZWJ-composed family must appear as a whole sequence',
          );
        },
      );

      testWidgets(
        'strips tag characters and additional bidi controls from the NG-user snackbar label',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          // U+061C (Arabic Letter Mark), U+180E (Mongolian Vowel Separator),
          // and U+E0041 (a Tag Character) are all invisible/spoofing chars
          // that must never leak into the snackbar label.
          const String alm = '\u061C';
          const String mvs = '\u180E';
          const String tagA = '\u{E0041}';
          final String spoofyUserId = 'alice${alm}admin${mvs}x$tagA';

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngUserIds: <String>{spoofyUserId},
              notificationEnabled: true,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'ng-spoof-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: spoofyUserId,
              content: 'any text',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(SnackBar), findsOneWidget);

          final Iterable<Text> texts = tester.widgetList<Text>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ),
          );
          final String combined = texts.map((Text t) => t.data ?? '').join();

          expect(
            combined.contains(alm),
            isFalse,
            reason: 'Arabic Letter Mark must be stripped from display',
          );
          expect(
            combined.contains(mvs),
            isFalse,
            reason: 'Mongolian Vowel Separator must be stripped from display',
          );
          expect(
            combined.contains(tagA),
            isFalse,
            reason: 'Tag characters must be stripped (Trojan Source defense)',
          );
        },
      );

      testWidgets(
        'does not retroactively announce historical NG hits when notification is toggled ON later',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          // Start with notification OFF and add an NG comment.
          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: false,
            ),
          );
          await tester.pump();

          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'past-ng',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'old spam',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();

          // No snackbar / badge while OFF.
          expect(find.byType(SnackBar), findsNothing);
          expect(find.byKey(const Key('ng-protection-badge')), findsNothing);

          // Toggle ON by rebuilding with notificationEnabled = true.
          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
            ),
          );
          await tester.pump();
          await tester.pump();

          // The historical NG comment must not trigger a retroactive
          // snackbar or badge increment.
          expect(find.byType(SnackBar), findsNothing);
          expect(find.byKey(const Key('ng-protection-badge')), findsNothing);
        },
      );

      testWidgets(
        'processes full tail when the cursor message was evicted by ring-buffer rotation',
        (WidgetTester tester) async {
          final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
          final GlobalKey<_NgProtectionHostState> hostKey =
              GlobalKey<_NgProtectionHostState>();

          await tester.pumpWidget(
            _NgProtectionHost(
              key: hostKey,
              supervisor: supervisor,
              ngWords: const <String>['spam'],
              notificationEnabled: true,
            ),
          );
          await tester.pump();

          // First, establish a cursor by pushing a benign message.
          hostKey.currentState!.addMessage(
            AppMessage(
              id: 'keep-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 0),
              userId: 'user-a',
              content: 'hello',
              type: AppMessageType.chat,
            ),
          );
          await tester.pump();
          await tester.pump();

          // Now replace the message list entirely with a fresh set that
          // does NOT contain the previous cursor ID ('keep-1'), simulating
          // ring-buffer rotation. The first of the new messages contains
          // an NG word.
          hostKey.currentState!.replaceAll(<AppMessage>[
            AppMessage(
              id: 'rotated-1',
              timestamp: DateTime(2026, 3, 22, 12, 0, 5),
              userId: 'user-b',
              content: 'rotated spam here',
              type: AppMessageType.chat,
            ),
            AppMessage(
              id: 'rotated-2',
              timestamp: DateTime(2026, 3, 22, 12, 0, 6),
              userId: 'user-c',
              content: 'benign',
              type: AppMessageType.chat,
            ),
          ]);
          await tester.pump();
          await tester.pump();

          // Because the cursor was evicted, the fallback path must process
          // the full tail and announce the NG hit (otherwise it would be
          // silently swallowed).
          expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
          expect(find.text('1'), findsOneWidget);
        },
      );
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

    testWidgets('shows gift/nicoad messages by default (toggles ON)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'gift-vis', type: AppMessageType.gift, content: 'ギフト'),
        _message(
          id: 'nicoad-vis',
          type: AppMessageType.nicoad,
          content: 'ニコニ広告',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: messages),
      );

      expect(find.byKey(const Key('comment-row-gift-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-nicoad-vis')), findsOneWidget);
    });

    testWidgets('hides gift messages when showGiftComment is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
        _message(id: 'gift-hidden', type: AppMessageType.gift, content: 'ギフト'),
        _message(
          id: 'nicoad-vis',
          type: AppMessageType.nicoad,
          content: 'ニコニ広告',
        ),
      ];

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: messages,
          showGiftComment: false,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-nicoad-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-gift-hidden')), findsNothing);
    });

    testWidgets('hides nicoad messages when showNicoadComment is false', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
      final List<AppMessage> messages = <AppMessage>[
        _message(id: 'chat-vis', type: AppMessageType.chat, content: '通常'),
        _message(id: 'gift-vis', type: AppMessageType.gift, content: 'ギフト'),
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
          showNicoadComment: false,
        ),
      );

      expect(find.byKey(const Key('comment-row-chat-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-gift-vis')), findsOneWidget);
      expect(find.byKey(const Key('comment-row-nicoad-hidden')), findsNothing);
    });

    // Locks the asymmetric NG-filter design that ships with this PR:
    //   - nicoad の TTS 経路は NG ワードでスキップする（攻撃ベクタ防御）
    //   - nicoad の表示経路は従来どおり NG をバイパスし、必ず一覧に出す
    //     （重要な収益イベントを silent に消さない）
    //   - gift も同様に表示経路は NG をバイパスする（本文がシステム固定文の前提）
    // chat 側との振る舞いの差を将来うっかり対称化されないよう regression
    // テストとして固定しておく。chat の場合は同じ NG 文字列で hidden になる
    // ことも対比として確認する。
    testWidgets(
      'gift / nicoad rows are still visible even when body contains an NG word '
      '(display bypasses NG filter on purpose)',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'gift-ng',
            type: AppMessageType.gift,
            content: 'NG containing gift body',
          ),
          _message(
            id: 'nicoad-ng',
            type: AppMessageType.nicoad,
            content: 'this contains NG ad copy',
          ),
          _message(
            id: 'chat-ng',
            type: AppMessageType.chat,
            content: 'this contains NG chat',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            ngWords: const <String>['NG'],
          ),
        );

        // gift / nicoad は表示される（NG バイパス）
        expect(find.byKey(const Key('comment-row-gift-ng')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-nicoad-ng')), findsOneWidget);
        // chat は NG ワードで非表示になる（既存挙動の対比）
        expect(find.byKey(const Key('comment-row-chat-ng')), findsNothing);
      },
    );

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

    // ------------------------------------------------------------------
    // _buildMetaSpans helper tests (Issue #444).
    //
    // Pins the timestamp + user-ID span construction that all three comment
    // layouts (pinned two-line, main single-line URL-aware, main two-line)
    // share. The goal is to detect visual regressions that dart analyze
    // cannot catch: missing user-id span, wrong color, wrong font weight,
    // or wrong italic/grey treatment when the spoiler-hidden state is on.
    // ------------------------------------------------------------------
    group('_buildMetaSpans', () {
      test('emits timestamp + separator + displayName when shown', () {
        final List<InlineSpan> spans = buildMetaSpansForTesting(
          timestamp: '12:34:56',
          showUserName: true,
          displayName: 'alice (u123)',
          timestampFontSize: 11,
          idFontSize: 12,
          timestampColor: const Color(0xFF808080),
          idColor: const Color(0xFF808080),
          hidden: false,
          idFontWeight: FontWeight.w500,
        );
        expect(spans.length, 3);

        final TextSpan ts = spans[0] as TextSpan;
        expect(ts.text, '12:34:56');
        expect(ts.style?.fontSize, 11);
        expect(ts.style?.color, const Color(0xFF808080));
        expect(ts.style?.fontStyle, isNull);

        final TextSpan sep = spans[1] as TextSpan;
        expect(sep.text, '  ');
        // Separator font size is pinned to the larger of timestamp/id sizes
        // so an inherited DefaultTextStyle cannot inflate the meta line
        // height beyond the adjacent spans.
        expect(sep.style?.fontSize, 12);

        final TextSpan id = spans[2] as TextSpan;
        expect(id.text, 'alice (u123)');
        expect(id.style?.fontSize, 12);
        expect(id.style?.fontWeight, FontWeight.w500);
        expect(id.style?.color, const Color(0xFF808080));
      });

      test('omits displayName span when showUserName is false', () {
        final List<InlineSpan> spans = buildMetaSpansForTesting(
          timestamp: '12:34:56',
          showUserName: false,
          displayName: 'alice',
          timestampFontSize: 11,
          idFontSize: 12,
          timestampColor: const Color(0xFF808080),
          idColor: const Color(0xFF808080),
          hidden: false,
        );
        expect(spans.length, 1);
        expect((spans.single as TextSpan).text, '12:34:56');
      });

      test('omits displayName span when displayName is null', () {
        final List<InlineSpan> spans = buildMetaSpansForTesting(
          timestamp: '12:34:56',
          showUserName: true,
          displayName: null,
          timestampFontSize: 11,
          idFontSize: 12,
          timestampColor: const Color(0xFF808080),
          idColor: const Color(0xFF808080),
          hidden: false,
        );
        expect(spans.length, 1);
        expect((spans.single as TextSpan).text, '12:34:56');
      });

      test('effectiveUserColor overrides idColor on the displayName span', () {
        final List<InlineSpan> spans = buildMetaSpansForTesting(
          timestamp: '00:00:00',
          showUserName: true,
          displayName: 'bob',
          timestampFontSize: 11,
          idFontSize: 12,
          timestampColor: const Color(0xFF808080),
          idColor: const Color(0xFF808080),
          effectiveUserColor: const Color(0xFFBF360C),
          hidden: false,
          idFontWeight: FontWeight.w500,
        );
        final TextSpan id = spans[2] as TextSpan;
        expect(id.style?.color, const Color(0xFFBF360C));
      });

      test(
        'hidden state forces grey + italic and drops the id font weight',
        () {
          final List<InlineSpan> spans = buildMetaSpansForTesting(
            timestamp: '12:34:56',
            showUserName: true,
            displayName: 'alice',
            timestampFontSize: 14,
            idFontSize: 14,
            timestampColor: const Color(0xFF808080),
            idColor: const Color(0xFF808080),
            effectiveUserColor: const Color(0xFFBF360C),
            hidden: true,
            idFontWeight: FontWeight.w500,
          );
          final TextSpan ts = spans[0] as TextSpan;
          expect(ts.style?.color, Colors.grey);
          expect(ts.style?.fontStyle, FontStyle.italic);

          final TextSpan id = spans[2] as TextSpan;
          expect(id.style?.color, Colors.grey);
          expect(id.style?.fontStyle, FontStyle.italic);
          // w500 must not leak through when hidden, otherwise the spoiler
          // placeholder looks louder than the rest of the row.
          expect(id.style?.fontWeight, isNull);
        },
      );

      test(
        'pinned-style call (idFontWeight: null) does not bold the displayName',
        () {
          final List<InlineSpan> spans = buildMetaSpansForTesting(
            timestamp: '12:34:56',
            showUserName: true,
            displayName: 'alice',
            timestampFontSize: 10,
            idFontSize: 10,
            timestampColor: const Color(0xFF808080),
            idColor: const Color(0xFF808080),
            hidden: false,
            idFontWeight: null,
          );
          final TextSpan id = spans[2] as TextSpan;
          expect(id.style?.fontWeight, isNull);
          // Pinned layout passes equal timestamp/id sizes; the separator
          // must match so the pinned meta line height stays at metaFontSize
          // (pre-refactor behavior).
          final TextSpan sep = spans[1] as TextSpan;
          expect(sep.style?.fontSize, 10);
        },
      );

      test('hidden with timestamp-only (no user name) still greys out', () {
        final List<InlineSpan> spans = buildMetaSpansForTesting(
          timestamp: '12:34:56',
          showUserName: false,
          displayName: 'alice',
          timestampFontSize: 11,
          idFontSize: 12,
          timestampColor: const Color(0xFF808080),
          idColor: const Color(0xFF808080),
          hidden: true,
        );
        expect(spans.length, 1);
        final TextSpan ts = spans.single as TextSpan;
        expect(ts.text, '12:34:56');
        expect(ts.style?.color, Colors.grey);
        expect(ts.style?.fontStyle, FontStyle.italic);
      });
    });

    // ------------------------------------------------------------------
    // Operator long-body / overflow boundary tests (Issue #477).
    //
    // Operator (運営) comments are broadcaster announcements that may carry
    // multi-paragraph or rule-change notices. The renderer currently uses
    // `Text.rich` with no `maxLines` / `overflow` cap, so long content wraps
    // freely. These tests pin that behavior so:
    //   * a future change that silently caps `maxLines` does not drop body
    //     content without an explicit decision,
    //   * narrow-screen wrapping (360dp class devices) keeps the body inside
    //     the viewport,
    //   * embedded newlines do not collapse into a single line.
    // Two-line and one-line layouts are both covered.
    // ------------------------------------------------------------------

    testWidgets(
      'operator long body (1000+ chars) renders without overflow exceptions',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        // 1100 visible characters (above the 1000-char threshold called out
        // in the issue) — uses ASCII so the byte length is unambiguous.
        final String longBody = 'A' * 1100;
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-long',
            type: AppMessageType.operator,
            content: longBody,
            userId: null,
            userName: '運営',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        // Row exists.
        expect(
          find.byKey(const Key('comment-row-operator-long')),
          findsOneWidget,
        );
        // No layout / overflow exception was thrown during pump.
        expect(tester.takeException(), isNull);

        // Body text is still present in the rendered RichText (i.e. the
        // renderer did not silently truncate to a few characters).
        final RichText rich = findRichTextContaining(tester, longBody);
        expect(
          rich.text.toPlainText().contains(longBody),
          isTrue,
          reason:
              'operator long body must render in full (current implementation '
              'does not cap maxLines). If a maxLines cap is intentionally '
              'introduced, update this test together with a spec note.',
        );
      },
    );

    testWidgets(
      'operator body with embedded newlines renders all lines (one-line mode)',
      (WidgetTester tester) async {
        // 10 line breaks (issue acceptance criterion: "改行 10 個含む").
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<String> segments = List<String>.generate(
          11,
          (int i) => '段落${i + 1}',
        );
        final String multiLineBody = segments.join('\n');
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-newlines',
            type: AppMessageType.operator,
            content: multiLineBody,
            userId: null,
            userName: '運営',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        expect(tester.takeException(), isNull);
        final RichText rich = findRichTextContaining(tester, '段落1');
        final String plain = rich.text.toPlainText();
        // Every segment must survive into the rendered tree -- a regression
        // that collapses '\n' into spaces, or one that drops trailing
        // segments via maxLines, would fail here.
        for (final String segment in segments) {
          expect(
            plain.contains(segment),
            isTrue,
            reason: 'operator body lost newline-separated segment "$segment"',
          );
        }
      },
    );

    testWidgets(
      'operator long body in two-line mode keeps meta and body both rendered',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        // Distinct strings for label vs body so substring checks cannot
        // false-positive across the two text spans.
        const String label = '2行運営';
        final String longBody =
            '${'長文告知' * 250}_END'; // ~1000+ chars + sentinel
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-long-2l',
            type: AppMessageType.operator,
            content: longBody,
            userId: null,
            userName: label,
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: messages,
            commentTwoLineEnabled: true,
          ),
        );

        expect(tester.takeException(), isNull);
        // Meta line carries the label.
        final RichText metaRich = findRichTextContaining(tester, label);
        expect(metaRich.text.toPlainText().contains(label), isTrue);
        // Body line carries the long content end-marker (proves the renderer
        // did not cap before reaching the end of the body).
        final RichText bodyRich = findRichTextContaining(tester, '_END');
        expect(
          bodyRich.text.toPlainText().endsWith('_END'),
          isTrue,
          reason:
              'two-line mode must keep the full operator body; the trailing '
              '"_END" sentinel is missing, suggesting a silent truncation.',
        );
      },
    );

    testWidgets(
      'operator long body wraps inside a 360dp narrow viewport without overflow',
      (WidgetTester tester) async {
        // Force a 360x800 logical-pixel viewport (matches the smaller-end
        // Android device class called out in the issue). Restored in
        // addTearDown so adjacent tests are not affected.
        const Size narrow = Size(360, 800);
        tester.view.physicalSize = narrow;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final String longBody = '長文告知のテキストが折り返されることを確認するための本文。' * 10;
        final List<AppMessage> messages = <AppMessage>[
          _message(
            id: 'operator-narrow',
            type: AppMessageType.operator,
            content: longBody,
            userId: null,
            userName: '運営',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        expect(
          find.byKey(const Key('comment-row-operator-narrow')),
          findsOneWidget,
        );
        // Wrapping must succeed without producing a RenderFlex / overflow
        // exception. takeException() returns only the first error captured
        // during this pump cycle, so a cascade of follow-up exceptions is
        // not reported individually — the first one is enough as a
        // regression signal here.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'operator long body must wrap cleanly on a 360dp-wide viewport; '
              'an overflow exception here means the row layout is no longer '
              'flexible (e.g. a fixed-width Row child was introduced).',
        );
        // The rendered row must not exceed the viewport width.
        final RenderBox rowBox = tester.renderObject(
          find.byKey(const Key('comment-row-operator-narrow')),
        );
        expect(
          rowBox.size.width,
          lessThanOrEqualTo(narrow.width),
          reason:
              'operator row width (${rowBox.size.width}) exceeded the 360dp '
              'narrow viewport — long content is escaping horizontally.',
        );
      },
    );
  });

  group('CommentScreen keyword search (Issue #114)', () {
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

    List<AppMessage> buildMessages() {
      return <AppMessage>[
        _message(id: 'c1', type: AppMessageType.chat, content: 'Hello world'),
        _message(id: 'c2', type: AppMessageType.chat, content: 'こんにちは世界'),
        _message(id: 'c3', type: AppMessageType.chat, content: 'goodbye world'),
      ];
    }

    testWidgets('tapping search icon expands the search bar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      expect(find.byKey(const Key('comment-search-field')), findsNothing);
      // The search action is reached through the overflow menu, so the
      // overflow button must be present and the search menu item must be
      // present only once the menu is opened.
      expect(find.byKey(const Key('appbar-overflow-menu')), findsOneWidget);

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment-search-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-search-field')), findsOneWidget);
      expect(find.byKey(const Key('appbar-title-text')), findsNothing);
      expect(find.byKey(const Key('search-close-button')), findsOneWidget);
      // While search mode is active the overflow menu button must be hidden
      // so the AppBar cannot launch nested modal flows (search inside search,
      // settings dialog while typing a query, etc.).
      expect(find.byKey(const Key('appbar-overflow-menu')), findsNothing);
    });

    testWidgets(
      'dismissing the overflow menu without selection leaves screen stable',
      (WidgetTester tester) async {
        // Regression guard for the IconButton + showMenu() implementation of
        // the AppBar overflow menu: when the user taps outside the menu to
        // dismiss it, `showMenu` resolves with `null` and the handler must
        // no-op cleanly (no crash, no navigation, no search mode).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: buildMessages()),
        );

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('comment-search-button')), findsOneWidget);

        // Tap outside the menu (the barrier) to dismiss without selecting.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Menu is gone, screen is still on the normal (non-search) AppBar.
        expect(find.byKey(const Key('comment-search-button')), findsNothing);
        expect(find.byKey(const Key('appbar-overflow-menu')), findsOneWidget);
        expect(find.byKey(const Key('comment-search-field')), findsNothing);
      },
    );

    testWidgets('entering a keyword filters comments to matches only', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'hello',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsNothing);
      expect(find.textContaining('こんにちは世界'), findsNothing);
    });

    testWidgets('NFKC-style normalization: halfwidth kana finds fullwidth kana '
        '(Issue #472)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: <AppMessage>[
            _message(id: 'k1', type: AppMessageType.chat, content: 'アイウエオ'),
            _message(
              id: 'k2',
              type: AppMessageType.chat,
              content: 'hello world',
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      // Halfwidth katakana query must find fullwidth katakana body.
      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'ｱｲｳ',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(find.textContaining('アイウエオ'), findsOneWidget);
      expect(find.textContaining('hello world'), findsNothing);
    });

    testWidgets('NFKC-style normalization: fullwidth alphanumerics fold to '
        'halfwidth (Issue #472)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: <AppMessage>[
            _message(
              id: 'a1',
              type: AppMessageType.chat,
              content: 'code ABC123',
            ),
            _message(
              id: 'a2',
              type: AppMessageType.chat,
              content: 'hello world',
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      // Fullwidth query ＡＢＣ must match halfwidth "ABC".
      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'ＡＢＣ',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(find.textContaining('code ABC123'), findsOneWidget);
      expect(find.textContaining('hello world'), findsNothing);
    });

    testWidgets('NFKC-style normalization: hiragana query finds katakana body '
        '(Issue #472 仕様判断 A)', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      // Use a distinctive katakana body that is unlikely to collide
      // with any surrounding AppBar / placeholder text the screen
      // renders (e.g. "コメント").
      await tester.pumpWidget(
        _buildScreen(
          supervisor: supervisor,
          messages: <AppMessage>[
            _message(id: 'h1', type: AppMessageType.chat, content: 'タカハシさん'),
            _message(
              id: 'h2',
              type: AppMessageType.chat,
              content: 'hello world',
            ),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'たかはし',
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 200));

      expect(find.textContaining('タカハシさん'), findsOneWidget);
      expect(find.textContaining('hello world'), findsNothing);
    });

    testWidgets(
      'search still works correctly after close and re-open (cache reset '
      'does not break subsequent search) (Issue #472 follow-up)',
      (WidgetTester tester) async {
        // Regression guard for the `_normalizedContentCache.clear()` in
        // `_closeSearch`. After dismissing search, re-opening it and
        // typing the same query must still filter correctly — the cache
        // must be repopulated lazily, not left stale or missing entries.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(
            supervisor: supervisor,
            messages: <AppMessage>[
              _message(id: 'c1', type: AppMessageType.chat, content: 'アイウ'),
              _message(id: 'c2', type: AppMessageType.chat, content: 'hello'),
            ],
          ),
        );

        // First open: type query, verify match
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('comment-search-field')),
          'ｱｲｳ',
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        expect(find.textContaining('アイウ'), findsOneWidget);
        expect(find.textContaining('hello'), findsNothing);

        // Close search via close button.
        await tester.tap(find.byKey(const Key('search-close-button')));
        await tester.pumpAndSettle();

        // Both messages visible again (search closed).
        expect(find.textContaining('アイウ'), findsOneWidget);
        expect(find.textContaining('hello'), findsOneWidget);

        // Re-open search, same query, verify it still filters correctly
        // (i.e. the cache was cleared on close and is being repopulated).
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('comment-search-field')),
          'ｱｲｳ',
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        expect(find.textContaining('アイウ'), findsOneWidget);
        expect(find.textContaining('hello'), findsNothing);
      },
    );

    testWidgets('matching is case-insensitive', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'WORLD',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsOneWidget);
      expect(find.textContaining('こんにちは世界'), findsNothing);
    });

    testWidgets('shows "見つかりません" when no comment matches', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'nonexistent-keyword',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-search-empty')), findsOneWidget);
      // The empty state now includes the user's query so they can confirm
      // what was searched for.
      expect(find.text('"nonexistent-keyword" は見つかりません'), findsOneWidget);
      expect(find.byKey(const Key('comment-list')), findsNothing);
    });

    testWidgets('long search queries are truncated in the empty state', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      // 30-char query; the first 20 chars should be shown with an ellipsis.
      const String longQuery = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        longQuery,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comment-search-empty')), findsOneWidget);
      expect(find.text('"${'a' * 20}..." は見つかりません'), findsOneWidget);
    });

    testWidgets(
      'emoji-heavy query is truncated on grapheme boundaries (no U+FFFD)',
      (WidgetTester tester) async {
        // Regression test for PR3 review #2 MUST-FIX item 1: truncating by
        // UTF-16 code units slices surrogate pairs and renders U+FFFD (`�`).
        // Switching to `characters.take()` must preserve whole emoji.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: buildMessages()),
        );

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();

        // 21 party-popper emoji (each a surrogate pair in UTF-16) — the
        // truncation threshold is 20 grapheme clusters.
        const String emojiQuery =
            '\u{1F389}\u{1F389}\u{1F389}\u{1F389}\u{1F389}'
            '\u{1F389}\u{1F389}\u{1F389}\u{1F389}\u{1F389}'
            '\u{1F389}\u{1F389}\u{1F389}\u{1F389}\u{1F389}'
            '\u{1F389}\u{1F389}\u{1F389}\u{1F389}\u{1F389}'
            '\u{1F389}';
        const String emoji = '\u{1F389}';
        final String expectedDisplay = emoji * 20;

        await tester.enterText(
          find.byKey(const Key('comment-search-field')),
          emojiQuery,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('comment-search-empty')), findsOneWidget);
        expect(find.text('"$expectedDisplay..." は見つかりません'), findsOneWidget);
        // The replacement character must NOT appear — that would indicate a
        // surrogate pair was cut in half by substring-by-code-unit.
        expect(find.textContaining('\uFFFD'), findsNothing);
      },
    );

    testWidgets('debounce delays query normalization until the timer fires', (
      WidgetTester tester,
    ) async {
      // Regression coverage for the 150ms debounce on _normalizedSearchQuery.
      // Prior tests relied on pumpAndSettle() which implicitly waited past
      // the debounce; this test verifies the timing explicitly so a future
      // debounce tweak (e.g. raising it to 500ms) would fail loudly.
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'hello',
      );
      // Before the 150ms debounce elapses, filtering has not yet run:
      // every comment is still visible.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsOneWidget);
      expect(find.textContaining('こんにちは世界'), findsOneWidget);

      // After the debounce fires (total >= 150ms), the non-matching rows
      // disappear.
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsNothing);
      expect(find.textContaining('こんにちは世界'), findsNothing);
    });

    testWidgets('whitespace-only query shows all comments (no empty state)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        '   ',
      );
      await tester.pumpAndSettle();

      // Empty-after-trim queries should behave like "no filter", not like
      // "no matches".
      expect(find.byKey(const Key('comment-search-empty')), findsNothing);
      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsOneWidget);
      expect(find.textContaining('こんにちは世界'), findsOneWidget);
    });

    testWidgets(
      'new messages arriving during search are filtered by the active query',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_CommentScreenHostState> hostKey =
            GlobalKey<_CommentScreenHostState>();

        await tester.pumpWidget(
          _CommentScreenHost(
            key: hostKey,
            supervisor: supervisor,
            initialLv: 'lv345678901',
            initialMessages: buildMessages(),
          ),
        );

        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('comment-search-field')),
          'hello',
        );
        await tester.pumpAndSettle();

        // Baseline: only "Hello world" is visible.
        expect(find.textContaining('Hello world'), findsOneWidget);
        expect(find.textContaining('goodbye world'), findsNothing);

        // A new comment arrives that matches the query.
        hostKey.currentState!.addMessage(
          _message(
            id: 'c4',
            type: AppMessageType.chat,
            content: 'another hello line',
          ),
        );
        // A new comment arrives that does NOT match.
        hostKey.currentState!.addMessage(
          _message(
            id: 'c5',
            type: AppMessageType.chat,
            content: 'unrelated text',
          ),
        );
        await tester.pumpAndSettle();

        // Matching new comment appears; non-matching new comment stays hidden.
        expect(find.textContaining('another hello line'), findsOneWidget);
        expect(find.textContaining('unrelated text'), findsNothing);
        // Original non-match still hidden.
        expect(find.textContaining('goodbye world'), findsNothing);
      },
    );

    testWidgets(
      'pinned comments remain visible even when they do not match the search query',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final List<AppMessage> messages = <AppMessage>[
          _message(id: 'msg-pin', type: AppMessageType.chat, content: 'pin me'),
          _message(
            id: 'msg-other',
            type: AppMessageType.chat,
            content: 'hello there',
          ),
        ];

        await tester.pumpWidget(
          _buildScreen(supervisor: supervisor, messages: messages),
        );

        // Pin the first comment before entering search mode.
        await tester.longPress(find.byKey(const Key('comment-row-msg-pin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('action-pin-msg-pin')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('pinned-comments-section')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pinned-row-msg-pin')), findsOneWidget);

        // Search for a term that does NOT match the pinned comment.
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('comment-search-field')),
          'hello',
        );
        await tester.pumpAndSettle();

        // Pinned section stays visible regardless of the query; the pinned
        // row is exempt from the search filter by design.
        expect(
          find.byKey(const Key('pinned-comments-section')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('pinned-row-msg-pin')), findsOneWidget);

        // The pinned comment's main-list row is hidden by the active search
        // filter (its content "pin me" does not match "hello"). Pinned
        // rendering MUST come from the pinned section only, not duplicated
        // in the main list.
        expect(find.byKey(const Key('comment-row-msg-pin')), findsNothing);
        // Sanity: the comment that actually matches the query still renders
        // in the main list.
        expect(find.byKey(const Key('comment-row-msg-other')), findsOneWidget);
      },
    );

    testWidgets('clearing the query returns to full match view', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'hello',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('goodbye world'), findsNothing);

      // Clear button appears only when the query is non-empty.
      expect(find.byKey(const Key('search-clear-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('search-clear-button')));
      await tester.pumpAndSettle();

      // Still in search mode, but all comments visible again.
      expect(find.byKey(const Key('comment-search-field')), findsOneWidget);
      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsOneWidget);
      expect(find.textContaining('こんにちは世界'), findsOneWidget);
    });

    testWidgets('closing search restores the normal AppBar', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = _buildStreamingSupervisor();

      await tester.pumpWidget(
        _buildScreen(supervisor: supervisor, messages: buildMessages()),
      );

      await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-search-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('comment-search-field')),
        'hello',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-close-button')));
      await tester.pumpAndSettle();

      // Title is back, search bar is gone, all comments visible.
      expect(find.byKey(const Key('comment-search-field')), findsNothing);
      expect(find.byKey(const Key('appbar-title-text')), findsOneWidget);
      // The overflow menu (which hosts the search entry) is rendered again
      // when the AppBar returns to its normal state.
      expect(find.byKey(const Key('appbar-overflow-menu')), findsOneWidget);
      expect(find.textContaining('Hello world'), findsOneWidget);
      expect(find.textContaining('goodbye world'), findsOneWidget);
      expect(find.textContaining('こんにちは世界'), findsOneWidget);
    });
  });

  // Integration tests covering the interaction of the five comment-screen
  // features that landed together (type-visibility toggles, gift/nicoad
  // emphasis, NG protection notification, keyword search, new protobuf
  // message types). Individual features are already covered in depth by
  // their own groups; these tests focus on *cross-feature* behavior that
  // was not guarded at merge time.
  //
  // See Issue #492 (M2).
  group('Five-feature integration', () {
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

    testWidgets(
      'all types render when every visibility flag is ON and NG protection is ON',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        // Mixed stream: chat / operator / system / emotion / notification /
        // gift / nicoad all present. The 'spam' NG word matches chat only so
        // we can verify that the protection path fires for an allowed type
        // while leaving everything else visible.
        final List<AppMessage> initialMessages = <AppMessage>[
          _message(
            id: 'm-chat',
            type: AppMessageType.chat,
            content: 'chat-body',
          ),
          _message(
            id: 'm-operator',
            type: AppMessageType.operator,
            content: 'operator-body',
          ),
          _message(
            id: 'm-system',
            type: AppMessageType.system,
            content: 'system-body',
          ),
          _message(
            id: 'm-emotion',
            type: AppMessageType.emotion,
            content: 'emotion-body',
          ),
          _message(
            id: 'm-notification',
            type: AppMessageType.notification,
            content: 'notification-body',
          ),
          _message(
            id: 'm-gift',
            type: AppMessageType.gift,
            content: 'gift-body',
          ),
          _message(
            id: 'm-nicoad',
            type: AppMessageType.nicoad,
            content: 'nicoad-body',
          ),
        ];

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: initialMessages,
            ngWords: const <String>['spam'],
            notificationEnabled: true,
          ),
        );
        await tester.pumpAndSettle();

        // All seven rows must be visible — every type renders when the
        // corresponding show-flag is ON (default for this host).
        expect(find.byKey(const Key('comment-row-m-chat')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-m-operator')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-m-system')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-m-emotion')), findsOneWidget);
        expect(
          find.byKey(const Key('comment-row-m-notification')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('comment-row-m-gift')), findsOneWidget);
        expect(find.byKey(const Key('comment-row-m-nicoad')), findsOneWidget);

        // Feed a chat NG hit and verify the protection path still fires.
        hostKey.currentState!.addMessage(
          _message(
            id: 'm-spam',
            type: AppMessageType.chat,
            content: 'bad spam',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'operator NG hit is suppressed from protection when showOperatorComment is OFF',
      (WidgetTester tester) async {
        // Regression guard for M1 (#489): if the user has explicitly hidden
        // a type, NG protection must not announce "protection" events for
        // messages of that type. Announcing protection for a message the
        // user cannot see is a semantic contradiction.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['重要'],
            notificationEnabled: true,
            showOperatorComment: false,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          _message(
            id: 'op-ng',
            type: AppMessageType.operator,
            content: '重要なお知らせ',
          ),
        );
        await tester.pump();
        await tester.pump();

        // Operator row is hidden by the visibility toggle (existing
        // behavior) AND the NG protection must not fire.
        expect(find.byKey(const Key('comment-row-op-ng')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);

        // Sanity check: a chat NG hit in the same session still fires, so
        // protection is otherwise wired up correctly.
        hostKey.currentState!.addMessage(
          _message(
            id: 'chat-ng',
            type: AppMessageType.chat,
            content: '重要な spam',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
      },
    );

    testWidgets(
      'search mode keeps badge updating but suppresses the snackbar',
      (WidgetTester tester) async {
        // Regression guard for S4 (#494): when the user is typing in the
        // search bar, the IME keyboard is visible and a floating SnackBar
        // competes with it for screen space. The badge must still reflect
        // the NG hit so no information is lost.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['spam'],
            notificationEnabled: true,
          ),
        );
        await tester.pumpAndSettle();

        // Enter search mode via the overflow menu → search button path.
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('comment-search-field')), findsOneWidget);

        // A fresh NG hit while in search mode must increment the protected
        // count (state) but must NOT schedule a snackbar (would collide
        // with the IME keyboard). The badge widget itself is not rendered
        // in the AppBar actions while search is active — the AppBar only
        // shows the search clear button in that state — so we verify the
        // stored count indirectly by closing search and then inspecting
        // the now-visible badge.
        hostKey.currentState!.addMessage(
          _message(
            id: 'ng-search-1',
            type: AppMessageType.chat,
            content: 'hi spam',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: 'snackbar must be suppressed while searching',
        );

        // Leaving search mode must expose the accumulated badge value and
        // restore the normal snackbar path for subsequent NG hits.
        await tester.tap(find.byKey(const Key('search-close-button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('ng-protection-badge')),
          findsOneWidget,
          reason:
              'badge must reflect the hit that arrived while searching '
              '(no information loss)',
        );
        expect(find.text('1'), findsOneWidget);

        hostKey.currentState!.addMessage(
          _message(
            id: 'ng-search-2',
            type: AppMessageType.chat,
            content: 'more spam',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'OFF→ON toggle after ring-buffer rotation does not replay historical NG hits',
      (WidgetTester tester) async {
        // Regression guard for N1 (#493): cursor advance continues while
        // OFF, so if the ring buffer rotates the tracked ID out, the
        // fallback (`start = 0`) would have replayed every historical NG
        // hit on the first ON pass. Toggling OFF→ON must re-seed the
        // cursor to the current tail.
        //
        // Implementation dependency note: this assertion relies on the
        // fact that the OFF path in _processNgProtectionNotifications
        // does NOT increment _protectedCount (it only advances the
        // cursor). If a future change starts accumulating the count while
        // OFF (e.g. "count but suppress snackbar"), the badge expectation
        // below (findsNothing) would need to be updated accordingly.
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        // Start OFF with several historical NG hits already present.
        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: <AppMessage>[
              _message(
                id: 'old-ng-1',
                type: AppMessageType.chat,
                content: 'first spam',
              ),
              _message(
                id: 'old-ng-2',
                type: AppMessageType.chat,
                content: 'second spam',
              ),
            ],
            ngWords: const <String>['spam'],
            notificationEnabled: false,
          ),
        );
        await tester.pumpAndSettle();

        // Simulate ring-buffer rotation: replace the messages entirely so
        // the OFF-path cursor ID ('old-ng-2') is no longer present.
        hostKey.currentState!.replaceAll(<AppMessage>[
          _message(
            id: 'rot-1',
            type: AppMessageType.chat,
            content: 'rotated spam here',
          ),
          _message(id: 'rot-2', type: AppMessageType.chat, content: 'neutral'),
        ]);
        await tester.pumpAndSettle();

        // Badge is still absent (OFF).
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);

        // Toggle ON — with the fix, didUpdateWidget re-seeds the cursor to
        // the current tail so the pre-existing 'rotated spam here' does not
        // replay. Without the fix, badge would jump to 1 (or higher).
        hostKey.currentState!.setNotificationEnabled(true);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);

        // But a fresh NG hit arriving *after* the toggle must still fire
        // the protection path — otherwise we would have over-corrected.
        hostKey.currentState!.addMessage(
          _message(
            id: 'fresh-ng',
            type: AppMessageType.chat,
            content: 'fresh spam',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
        expect(find.text('1'), findsOneWidget);
      },
    );

    testWidgets(
      'system NG hit is suppressed from protection when showSystemMessage is OFF',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['重要'],
            notificationEnabled: true,
            showSystemMessage: false,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          _message(
            id: 'sys-ng',
            type: AppMessageType.system,
            content: '重要なお知らせ',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('comment-row-sys-ng')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);

        // Sanity: a chat NG hit in the same session still fires.
        hostKey.currentState!.addMessage(
          _message(
            id: 'chat-ng-sys',
            type: AppMessageType.chat,
            content: '重要なコメント',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'emotion NG hit is suppressed from protection when showEmotion is OFF',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['嬉しい'],
            notificationEnabled: true,
            showEmotion: false,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          _message(
            id: 'emo-ng',
            type: AppMessageType.emotion,
            content: '嬉しい気持ち',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('comment-row-emo-ng')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);

        // Sanity: a chat NG hit in the same session still fires.
        hostKey.currentState!.addMessage(
          _message(
            id: 'chat-ng-emo',
            type: AppMessageType.chat,
            content: '嬉しいコメント',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
      },
    );

    testWidgets(
      'throttle window does not advance during search — first post-search NG hit fires immediately',
      (WidgetTester tester) async {
        // Verifies that _isSearching return in _processNgProtectionNotifications
        // does not update _lastProtectionNotificationAt. When search ends,
        // the throttle window is still at its pre-search value, so the next
        // NG hit fires the snackbar immediately (window already elapsed).
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        // Virtual clock so we can step past the 10-second throttle window
        // without sleeping on the wall clock (#499 Clock injection).
        DateTime virtualNow = DateTime.utc(2026, 3, 22, 12, 0, 0);
        final Clock testClock = Clock(() => virtualNow);

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['spam'],
            notificationEnabled: true,
            clock: testClock,
          ),
        );
        await tester.pumpAndSettle();

        // Fire the first NG hit to start the throttle window.
        hostKey.currentState!.addMessage(
          _message(id: 'pre-1', type: AppMessageType.chat, content: 'pre spam'),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(SnackBar), findsOneWidget);

        // Advance the virtual clock past the throttle window so a fresh
        // NG hit *would* re-fire the snackbar under normal conditions.
        virtualNow = virtualNow.add(const Duration(seconds: 11));
        ScaffoldMessenger.of(
          tester.element(find.byType(CommentScreen)),
        ).hideCurrentSnackBar();
        await tester.pumpAndSettle();

        // Enter search mode.
        await tester.tap(find.byKey(const Key('appbar-overflow-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('comment-search-button')));
        await tester.pumpAndSettle();

        // NG hit during search — suppressed (no snackbar, but badge updates).
        hostKey.currentState!.addMessage(
          _message(
            id: 'search-ng',
            type: AppMessageType.chat,
            content: 'search spam',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byType(SnackBar),
          findsNothing,
          reason: 'snackbar suppressed during search',
        );

        // Exit search mode.
        await tester.tap(find.byKey(const Key('search-close-button')));
        await tester.pumpAndSettle();

        // The first NG hit after search should fire immediately because
        // the throttle window was not advanced during search.
        hostKey.currentState!.addMessage(
          _message(
            id: 'post-search-ng',
            type: AppMessageType.chat,
            content: 'post spam',
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason:
              'throttle did not advance during search, so the '
              'first post-search hit fires immediately',
        );
      },
    );

    testWidgets(
      'AppBar renders speech + sort + badge + overflow menu at 360dp without errors',
      (WidgetTester tester) async {
        // Layout smoke-test: at a typical narrow phone width (360dp), the
        // four trailing AppBar actions plus the leading title must render
        // without layout exceptions. Search / save-log / settings are now
        // inside the overflow menu (PR #487), so the direct actions are
        // the four below.
        tester.view.physicalSize = const Size(360 * 3, 640 * 3);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_IntegrationHostState> hostKey =
            GlobalKey<_IntegrationHostState>();

        await tester.pumpWidget(
          _IntegrationHost(
            key: hostKey,
            supervisor: supervisor,
            initialMessages: const <AppMessage>[],
            ngWords: const <String>['spam'],
            notificationEnabled: true,
          ),
        );
        await tester.pumpAndSettle();

        // Trigger an NG hit so the badge is actually rendered.
        hostKey.currentState!.addMessage(
          _message(
            id: 'layout-ng',
            type: AppMessageType.chat,
            content: 'just spam',
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('sort-toggle-button')), findsOneWidget);
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
        expect(find.byKey(const Key('appbar-overflow-menu')), findsOneWidget);
      },
    );
  });

  // Issue #628: presetCategories injection seam on ContentFilterConfig.
  // These tests exercise the priority order
  //   (1) presetCategories > (2) presetNgWords > (3) asset
  // and verify that NgDisplayPreferences is honored by the matcher when
  // the structured categories are injected directly (no asset load).
  group('CommentScreen presetCategories seam (#628)', () {
    const NgPresetCategory violenceCategory = NgPresetCategory(
      id: 'violence_test',
      description: 'test violence preset',
      policy: NgPolicy.blockSpeechOnly,
      displaySubcategory: NgDisplaySubcategory.violence,
      words: <String>['殺す'],
    );

    testWidgets(
      'NG protection skips badge/snackbar when allowViolence is true',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_PresetCategoriesHostState> hostKey =
            GlobalKey<_PresetCategoriesHostState>();

        await tester.pumpWidget(
          _PresetCategoriesHost(
            key: hostKey,
            supervisor: supervisor,
            presetCategories: const <NgPresetCategory>[violenceCategory],
            ngDisplayPreferences: const NgDisplayPreferences(
              allowViolence: true,
            ),
            notificationEnabled: true,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'preset-violence-allowed',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-a',
            content: 'これは殺すという言葉を含む',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        await tester.pump();

        // Display is allowed → comment renders, no NG-hit announcement.
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);
      },
    );

    testWidgets(
      'NG protection fires badge+snackbar when allowViolence is false',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_PresetCategoriesHostState> hostKey =
            GlobalKey<_PresetCategoriesHostState>();

        await tester.pumpWidget(
          _PresetCategoriesHost(
            key: hostKey,
            supervisor: supervisor,
            presetCategories: const <NgPresetCategory>[violenceCategory],
            ngDisplayPreferences: NgDisplayPreferences.defaults,
            notificationEnabled: true,
          ),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'preset-violence-blocked',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-a',
            content: 'これは殺すという言葉を含む',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        await tester.pump();

        // Default preferences hide the comment and announce the NG hit.
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byKey(const Key('ng-protection-badge')), findsOneWidget);
      },
    );

    testWidgets(
      'action sheet shows read-skipped banner when matched preset is on screen',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_PresetCategoriesHostState> hostKey =
            GlobalKey<_PresetCategoriesHostState>();

        await tester.pumpWidget(
          _PresetCategoriesHost(
            key: hostKey,
            supervisor: supervisor,
            presetCategories: const <NgPresetCategory>[violenceCategory],
            // allow display so the row stays visible and is long-press-able.
            ngDisplayPreferences: const NgDisplayPreferences(
              allowViolence: true,
            ),
            notificationEnabled: false,
            initialMessages: <AppMessage>[
              AppMessage(
                id: 'preset-banner-match',
                timestamp: DateTime(2026, 3, 22, 12, 0, 0),
                userId: 'user-a',
                content: '殺すぞ',
                type: AppMessageType.chat,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(
          find.byKey(const Key('comment-row-preset-banner-match')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('comment-actions-sheet')), findsOneWidget);
        expect(
          find.byKey(const Key('action-read-skipped-banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'didUpdateWidget honors a fresh presetCategories injection on rebuild',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_PresetCategoriesHostState> hostKey =
            GlobalKey<_PresetCategoriesHostState>();

        // Start with no preset injection so the matcher has no preset
        // categories. allowViolence stays false so a later match would
        // normally fire a badge/snackbar.
        await tester.pumpWidget(
          _PresetCategoriesHost(
            key: hostKey,
            supervisor: supervisor,
            presetCategories: const <NgPresetCategory>[],
            ngDisplayPreferences: NgDisplayPreferences.defaults,
            notificationEnabled: true,
          ),
        );
        await tester.pump();

        // Now inject the structured violence category via a rebuild and
        // flip allowViolence to true. The didUpdateWidget seam swap
        // must take effect: a subsequent matching message must NOT
        // raise the protection badge/snackbar because the per-subcategory
        // display toggle says it is allowed.
        hostKey.currentState!.updateConfig(
          presetCategories: const <NgPresetCategory>[violenceCategory],
          ngDisplayPreferences: const NgDisplayPreferences(allowViolence: true),
        );
        await tester.pump();

        hostKey.currentState!.addMessage(
          AppMessage(
            id: 'preset-violence-after-update',
            timestamp: DateTime(2026, 3, 22, 12, 0, 0),
            userId: 'user-a',
            content: 'これは殺すという言葉を含む',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(SnackBar), findsNothing);
        expect(find.byKey(const Key('ng-protection-badge')), findsNothing);
      },
    );

    testWidgets(
      'action sheet hides read-skipped banner when comment does not match preset',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = _buildStreamingSupervisor();
        final GlobalKey<_PresetCategoriesHostState> hostKey =
            GlobalKey<_PresetCategoriesHostState>();

        await tester.pumpWidget(
          _PresetCategoriesHost(
            key: hostKey,
            supervisor: supervisor,
            presetCategories: const <NgPresetCategory>[violenceCategory],
            ngDisplayPreferences: const NgDisplayPreferences(
              allowViolence: true,
            ),
            notificationEnabled: false,
            initialMessages: <AppMessage>[
              AppMessage(
                id: 'preset-banner-nomatch',
                timestamp: DateTime(2026, 3, 22, 12, 0, 0),
                userId: 'user-a',
                content: 'こんにちは',
                type: AppMessageType.chat,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(
          find.byKey(const Key('comment-row-preset-banner-nomatch')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('comment-actions-sheet')), findsOneWidget);
        expect(
          find.byKey(const Key('action-read-skipped-banner')),
          findsNothing,
        );
      },
    );
  });
}

/// Test host for the `presetCategories` injection seam (Issue #628).
///
/// Mirrors [_NgProtectionHost] but accepts the structured preset
/// categories and an [NgDisplayPreferences] so the seam priority and the
/// matcher's display-toggle interaction can be exercised together.
class _PresetCategoriesHost extends StatefulWidget {
  const _PresetCategoriesHost({
    super.key,
    required this.supervisor,
    required this.presetCategories,
    this.ngDisplayPreferences = NgDisplayPreferences.defaults,
    this.notificationEnabled = false,
    this.initialMessages = const <AppMessage>[],
  });

  final ConnectionSupervisor supervisor;
  final List<NgPresetCategory> presetCategories;
  final NgDisplayPreferences ngDisplayPreferences;
  final bool notificationEnabled;
  final List<AppMessage> initialMessages;

  @override
  State<_PresetCategoriesHost> createState() => _PresetCategoriesHostState();
}

class _PresetCategoriesHostState extends State<_PresetCategoriesHost> {
  late List<AppMessage> _messages;
  late List<NgPresetCategory> _presetCategories;
  late NgDisplayPreferences _ngDisplayPreferences;

  @override
  void initState() {
    super.initState();
    _messages = List<AppMessage>.from(widget.initialMessages);
    _presetCategories = widget.presetCategories;
    _ngDisplayPreferences = widget.ngDisplayPreferences;
  }

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  /// Updates the injected `presetCategories` and/or display preferences
  /// to exercise the [CommentScreen.didUpdateWidget] seam-swap path.
  void updateConfig({
    List<NgPresetCategory>? presetCategories,
    NgDisplayPreferences? ngDisplayPreferences,
  }) {
    setState(() {
      if (presetCategories != null) {
        _presetCategories = presetCategories;
      }
      if (ngDisplayPreferences != null) {
        _ngDisplayPreferences = ngDisplayPreferences;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        programInfo: const CommentProgramInfo(lv: 'lv-preset-seam'),
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (_, _) async {},
        ),
        themeMode: AppThemeMode.light,
        contentFilter: ContentFilterConfig(
          presetCategories: _presetCategories,
          ngDisplayPreferences: _ngDisplayPreferences,
          ngProtectionNotificationEnabled: widget.notificationEnabled,
        ),
      ),
    );
  }
}

/// Reactive host that exposes every feature flag required by the
/// five-feature integration tests. Kept separate from [_NgProtectionHost]
/// so the narrower host used by the existing NG-protection group does not
/// grow another dozen optional parameters.
class _IntegrationHost extends StatefulWidget {
  const _IntegrationHost({
    super.key,
    required this.supervisor,
    required this.initialMessages,
    this.ngWords = const <String>[],
    this.notificationEnabled = false,
    this.showOperatorComment = true,
    this.showSystemMessage = true,
    this.showEmotion = true,
    this.clock,
  });

  final ConnectionSupervisor supervisor;
  final List<AppMessage> initialMessages;
  final List<String> ngWords;
  final bool notificationEnabled;
  final bool showOperatorComment;
  final bool showSystemMessage;
  final bool showEmotion;
  final Clock? clock;

  @override
  State<_IntegrationHost> createState() => _IntegrationHostState();
}

class _IntegrationHostState extends State<_IntegrationHost> {
  late List<AppMessage> _messages;
  late bool _notificationEnabled;

  @override
  void initState() {
    super.initState();
    _messages = List<AppMessage>.from(widget.initialMessages);
    _notificationEnabled = widget.notificationEnabled;
  }

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  void replaceAll(List<AppMessage> messages) {
    setState(() {
      _messages = List<AppMessage>.from(messages);
    });
  }

  void setNotificationEnabled(bool value) {
    setState(() {
      _notificationEnabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        programInfo: const CommentProgramInfo(lv: 'lv-integration'),
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (_, _) async {},
        ),
        themeMode: AppThemeMode.light,
        contentFilter: ContentFilterConfig(
          ngWords: widget.ngWords,
          ngProtectionNotificationEnabled: _notificationEnabled,
        ),
        messageTypeVisibility: MessageTypeVisibilityConfig(
          showOperatorComment: widget.showOperatorComment,
          showSystemMessage: widget.showSystemMessage,
          showEmotion: widget.showEmotion,
        ),
        clock: widget.clock,
      ),
    );
  }
}

class _NgProtectionHost extends StatefulWidget {
  const _NgProtectionHost({
    super.key,
    required this.supervisor,
    required this.notificationEnabled,
    this.ngWords = const <String>[],
    this.ngUserIds = const <String>{},
    this.clock,
  });

  final ConnectionSupervisor supervisor;
  final bool notificationEnabled;
  final List<String> ngWords;
  final Set<String> ngUserIds;
  final Clock? clock;

  @override
  State<_NgProtectionHost> createState() => _NgProtectionHostState();
}

class _NgProtectionHostState extends State<_NgProtectionHost> {
  List<AppMessage> _messages = const <AppMessage>[];

  void addMessage(AppMessage message) {
    setState(() {
      _messages = List<AppMessage>.from(_messages)..add(message);
    });
  }

  void replaceAll(List<AppMessage> messages) {
    setState(() {
      _messages = List<AppMessage>.from(messages);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        programInfo: const CommentProgramInfo(lv: 'lv-ng-protection'),
        connectionSupervisor: widget.supervisor,
        messages: _messages,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (_, _) async {},
        ),
        themeMode: AppThemeMode.light,
        contentFilter: ContentFilterConfig(
          ngWords: widget.ngWords,
          ngUserIds: widget.ngUserIds,
          ngProtectionNotificationEnabled: widget.notificationEnabled,
        ),
        clock: widget.clock,
      ),
    );
  }
}

/// Test host that mirrors the production data shape (Issue #670):
/// `widget.messages` is an [UnmodifiableListView] over a single mutable
/// backing list, exactly like [TimelineStore.messages]. Adding a message
/// mutates the backing in place and rebuilds, so `oldWidget.messages` and
/// `widget.messages` end up resolving to the same content at the moment
/// `didUpdateWidget` runs — the data shape that previously broke
/// nickname / NG-protection / log / userName-resolve gating.
class _SharedListNicknameHost extends StatefulWidget {
  const _SharedListNicknameHost({
    super.key,
    required this.supervisor,
    this.initialMessages = const <AppMessage>[],
  });

  final ConnectionSupervisor supervisor;
  final List<AppMessage> initialMessages;

  @override
  State<_SharedListNicknameHost> createState() =>
      _SharedListNicknameHostState();
}

class _SharedListNicknameHostState extends State<_SharedListNicknameHost> {
  late final List<AppMessage> _backing = <AppMessage>[
    ...widget.initialMessages,
  ];
  late final UnmodifiableListView<AppMessage> _view =
      UnmodifiableListView<AppMessage>(_backing);
  String? lastNicknameUserId;
  String? lastNickname;
  String? lastRemovedUserId;
  int nicknameCallCount = 0;
  int removedCallCount = 0;

  void addMessage(AppMessage message) {
    setState(() {
      _backing.add(message);
    });
  }

  void evictHead() {
    setState(() {
      if (_backing.isNotEmpty) {
        _backing.removeAt(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CommentScreen(
        programInfo: const CommentProgramInfo(lv: 'lv123'),
        connectionSupervisor: widget.supervisor,
        messages: _view,
        callbacks: CommentCallbacks(
          onStopAllConnections: () async {},
          onReconnectSameLv: () async {},
          onDifferentLvConnected: (_, _) async {},
          onNicknameChanged: (String userId, String nickname) {
            lastNicknameUserId = userId;
            lastNickname = nickname;
            nicknameCallCount += 1;
          },
          onNicknameRemoved: (String userId) {
            lastRemovedUserId = userId;
            lastNickname = null;
            removedCallCount += 1;
          },
        ),
        autoNicknameRegistration: true,
        themeMode: AppThemeMode.light,
      ),
    );
  }
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
        contentFilter: ContentFilterConfig(
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
  bool emphasizeGiftNicoadComment = true,
  bool commentTwoLineEnabled = false,
  DateTime? beginAt,
  CommentLogWriter? commentLogWriter,
  bool autoSaveCommentLog = false,
  String autoSaveCommentLogPath = '',
  bool showOperatorComment = true,
  bool showSystemMessage = true,
  bool showEmotion = true,
  bool showGiftComment = true,
  bool showNicoadComment = true,
  AppThemeMode themeMode = AppThemeMode.light,
  bool ngProtectionNotificationEnabled = false,
  CommentSortOrder commentSortOrder = CommentSortOrder.ascending,
  void Function(CommentSortOrder)? onSortOrderChanged,
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
      ),
      connectionSupervisor: supervisor,
      messages: messages,
      callbacks: CommentCallbacks(
        onStopAllConnections: onStopAllConnections ?? () async {},
        onReconnectSameLv: onReconnectSameLv ?? () async {},
        onDifferentLvConnected: (_, _) async {},
        onOpenSettings: onOpenSettings,
        onSortOrderChanged: onSortOrderChanged,
      ),
      debugMode: debugMode,
      userNameResolution: userNameResolution,
      commentTwoLineEnabled: commentTwoLineEnabled,
      commentSortOrder: commentSortOrder,
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
      contentFilter: ContentFilterConfig(
        ngUserIds: ngUserIds,
        ngWords: ngWords,
        presetNgWords: presetNgWords,
        userColorMap: userColorMap,
        userNicknameMap: userNicknameMap,
        starPrefixHidingEnabled: starPrefixHidingEnabled,
        emphasizeGiftNicoadComment: emphasizeGiftNicoadComment,
        ngProtectionNotificationEnabled: ngProtectionNotificationEnabled,
      ),
      messageTypeVisibility: MessageTypeVisibilityConfig(
        showOperatorComment: showOperatorComment,
        showSystemMessage: showSystemMessage,
        showEmotion: showEmotion,
        showGiftComment: showGiftComment,
        showNicoadComment: showNicoadComment,
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
