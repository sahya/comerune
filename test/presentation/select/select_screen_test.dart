import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/application/timeline/timeline_store.dart';
import 'package:comerune/data/follow/follow_program.dart';
import 'package:comerune/data/follow/follow_program_repository.dart';
import 'package:comerune/data/follow/my_program_repository.dart';
import 'package:comerune/data/user/user_attribute_store.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/select/select_screen.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/in_memory_user_attribute_store.dart';
import '../../helpers/in_memory_user_session_store.dart';

Finder inputField() => find.byKey(const Key('select_screen_input'));
Finder connectButton() => find.byKey(const Key('select_screen_connect_button'));

void main() {
  Future<void> pumpSelectScreen(
    WidgetTester tester,
    ConnectionSupervisor supervisor,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SelectScreen(connectionSupervisor: supervisor)),
    );
    await tester.pump();
  }

  testWidgets('connect button is disabled when input is empty', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);

    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('connect button is disabled when input is whitespace only', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), '   ');
    await tester.pump();

    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('connect button starts connection and navigates with lv input', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(find.byType(CommentScreen), findsOneWidget);
    expect(find.text('lv345678901'), findsOneWidget);
  });

  testWidgets('connect button extracts lv from URL and navigates', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(
      inputField(),
      'https://live.nicovideo.jp/watch/lv345678901',
    );
    await tester.pump();

    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(find.byType(CommentScreen), findsOneWidget);
    expect(find.text('lv345678901'), findsOneWidget);
  });

  testWidgets('shows snackbar when lv extraction fails', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'invalid');
    await tester.pump();

    await tester.tap(connectButton());
    await tester.pump();

    expect(find.text('放送IDが見つかりません'), findsOneWidget);
    expect(supervisor.status, ConnectionStatus.idle);
    expect(supervisor.lastError, isNull);
    expect(find.byType(CommentScreen), findsNothing);
  });

  testWidgets('pressing Enter starts connection', (WidgetTester tester) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(find.byType(CommentScreen), findsOneWidget);
  });

  testWidgets('pressing Enter does nothing when input is empty', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.tap(inputField());
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(supervisor.status, ConnectionStatus.idle);
    expect(find.byType(CommentScreen), findsNothing);
    expect(find.text('放送IDが見つかりません'), findsNothing);
  });

  testWidgets('button and input are disabled while connecting', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    expect(supervisor.startConnection(), isTrue);
    await tester.pump();

    final TextField input = tester.widget<TextField>(inputField());
    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );

    expect(input.enabled, isFalse);
    expect(button.onPressed, isNull);
  });

  testWidgets('button is enabled in STOPPED state when input is not empty', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.stopByUser(), isTrue);

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('button can reconnect from FAILED state', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.fail(ConnectionErrorCode.sessionWsConnectFailed), isTrue);

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(find.byType(CommentScreen), findsOneWidget);
  });

  testWidgets('button can reconnect from ENDED state', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.endBroadcast(), isTrue);

    await pumpSelectScreen(tester, supervisor);
    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();

    final ElevatedButton button = tester.widget<ElevatedButton>(
      connectButton(),
    );
    expect(button.onPressed, isNotNull);

    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(find.byType(CommentScreen), findsOneWidget);
  });

  testWidgets('passes timeline messages to comment screen', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore();
    timelineStore.add(
      AppMessage(
        id: 'msg-1',
        timestamp: DateTime(2026, 3, 28, 10, 0, 0),
        userId: 'user-1',
        content: 'hello',
        type: AppMessageType.chat,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          timelineStore: timelineStore,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(find.byType(CommentScreen), findsOneWidget);
    expect(find.byKey(const Key('comment-row-msg-1')), findsOneWidget);
  });

  testWidgets(
      'adds broadcast ended notification to timeline when status becomes ended',
      (WidgetTester tester) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore();

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          timelineStore: timelineStore,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(find.byType(CommentScreen), findsOneWidget);

    // Transition to streaming and then end broadcast.
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.endBroadcast(), isTrue);
    await tester.pumpAndSettle();

    final List<AppMessage> messages = timelineStore.messages.toList();
    final AppMessage notification = messages.firstWhere(
      (AppMessage m) => m.type == AppMessageType.notification,
    );
    expect(notification.content, '放送が終了しました');
    expect(notification.id, startsWith('system:broadcast_ended:'));

    // Verify the notification is visible in the comment screen.
    expect(find.textContaining('放送が終了しました'), findsOneWidget);
  });

  testWidgets(
      'does not add duplicate notification when endBroadcast is called twice',
      (WidgetTester tester) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore();

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          timelineStore: timelineStore,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.endBroadcast(), isTrue);
    await tester.pumpAndSettle();

    // Restart and end again to verify no duplicate notification.
    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.endBroadcast(), isTrue);
    await tester.pumpAndSettle();

    final List<AppMessage> notifications = timelineStore.messages
        .where((AppMessage m) => m.type == AppMessageType.notification)
        .toList();
    // Each ended transition should produce exactly one notification.
    expect(notifications, hasLength(2));
  });

  testWidgets('shows settings button when settingsStore is provided', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: InMemorySharedPreferences(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          settingsStore: settingsStore,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('select_screen_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('hides settings button when settingsStore is null', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);

    expect(
      find.byKey(const Key('select_screen_settings_button')),
      findsNothing,
    );
  });

  testWidgets('shows login-required banner when not logged in', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: InMemorySharedPreferences(),
    );
    final InMemoryUserSessionStore userSessionStore =
        InMemoryUserSessionStore();

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          settingsStore: settingsStore,
          userSessionStore: userSessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('login-status-banner-required')),
      findsOneWidget,
    );
    expect(find.text('ログインが必要です。タップして設定を開く'), findsOneWidget);
  });

  testWidgets('shows logged-in banner when session exists', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: InMemorySharedPreferences(),
    );
    final InMemoryUserSessionStore userSessionStore =
        InMemoryUserSessionStore();
    await userSessionStore.save('user_session_abc123');

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          settingsStore: settingsStore,
          userSessionStore: userSessionStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('login-status-banner-ok')),
      findsOneWidget,
    );
    expect(find.text('ニコニコ ログイン済み'), findsOneWidget);
    expect(
      find.byKey(const Key('login-status-banner-required')),
      findsNothing,
    );
  });

  testWidgets(
      'hides login banner when settingsStore is provided but userSessionStore is null',
      (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final SettingsStore settingsStore = SharedPreferencesSettingsStore(
      prefs: InMemorySharedPreferences(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          settingsStore: settingsStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('login-status-banner-ok')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('login-status-banner-required')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('select_screen_settings_button')),
      findsOneWidget,
    );
  });

  testWidgets('hides login banner when settingsStore is null', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);

    expect(
      find.byKey(const Key('login-status-banner-ok')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('login-status-banner-required')),
      findsNothing,
    );
  });

  testWidgets(
      'reflects nickname and color changes in comment screen immediately',
      (WidgetTester tester) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore();
    final ValueNotifier<String?> supplierUserIdNotifier =
        ValueNotifier<String?>(null);
    final _FakeUserAttributeStore userAttributeStore =
        _FakeUserAttributeStore();

    timelineStore.add(
      AppMessage(
        id: 'msg-1',
        timestamp: DateTime(2026, 3, 29, 20, 0, 0),
        userId: 'user-1',
        content: 'hello',
        type: AppMessageType.chat,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          timelineStore: timelineStore,
          supplierUserIdNotifier: supplierUserIdNotifier,
          userAttributeStore: userAttributeStore,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    supplierUserIdNotifier.value = 'broadcaster-1';
    await tester.pumpAndSettle();

    CommentScreen commentScreen = tester.widget<CommentScreen>(
      find.byType(CommentScreen),
    );
    commentScreen.onNicknameChanged?.call('user-1', 'コテハン名');
    await tester.pump();

    expect(find.textContaining('コテハン名 (user-1)'), findsOneWidget);

    commentScreen = tester.widget<CommentScreen>(find.byType(CommentScreen));
    commentScreen.onUserColorChanged?.call('user-1', 0xFFE53935);
    await tester.pump();

    final Text textWidget = tester.widget(
      find.descendant(
        of: find.byKey(const Key('comment-row-msg-1')),
        matching: find.byType(Text),
      ),
    );
    expect(textWidget.style?.color, colorFromARGB32(0xFFE53935));
  });

  testWidgets('resets user color and nickname maps when connected lv changes',
      (WidgetTester tester) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore();
    final ValueNotifier<String?> supplierUserIdNotifier =
        ValueNotifier<String?>(null);
    final _FakeUserAttributeStore userAttributeStore = _FakeUserAttributeStore(
      colorsByBroadcaster: <String, Map<String, int>>{
        'broadcaster-1': <String, int>{'user-1': 0xFFE53935},
      },
      nicknamesByBroadcaster: <String, Map<String, String>>{
        'broadcaster-1': <String, String>{'user-1': '初期コテハン'},
      },
    );

    timelineStore.add(
      AppMessage(
        id: 'msg-1',
        timestamp: DateTime(2026, 3, 29, 20, 0, 0),
        userId: 'user-1',
        content: 'hello',
        type: AppMessageType.chat,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SelectScreen(
          connectionSupervisor: supervisor,
          timelineStore: timelineStore,
          supplierUserIdNotifier: supplierUserIdNotifier,
          userAttributeStore: userAttributeStore,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(inputField(), 'lv345678901');
    await tester.pump();
    await tester.tap(connectButton());
    await tester.pumpAndSettle();

    supplierUserIdNotifier.value = 'broadcaster-1';
    await tester.pumpAndSettle();

    expect(find.textContaining('初期コテハン (user-1)'), findsOneWidget);

    final Text coloredText = tester.widget(
      find.descendant(
        of: find.byKey(const Key('comment-row-msg-1')),
        matching: find.byType(Text),
      ),
    );
    expect(coloredText.style?.color, colorFromARGB32(0xFFE53935));

    final CommentScreen commentScreen = tester.widget<CommentScreen>(
      find.byType(CommentScreen),
    );
    await commentScreen.onDifferentLvConnected('lv345678901', 'lv999999999');
    await tester.pump();

    final CommentScreen updated = tester.widget<CommentScreen>(
      find.byType(CommentScreen),
    );
    expect(updated.userColorMap, isEmpty);
    expect(updated.userNicknameMap, isEmpty);

    expect(find.byKey(const Key('comment-row-msg-1')), findsNothing);
    expect(find.textContaining('初期コテハン (user-1)'), findsNothing);
  });

  group('follow program list', () {
    Future<void> pumpWithFollowPrograms(
      WidgetTester tester, {
      required List<FollowProgram> programs,
    }) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeFollowProgramRepository repository =
          _FakeFollowProgramRepository(programs);

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userSessionStore: userSessionStore,
            followProgramRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows program title and provider info in tile', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv123456789',
            title: 'テスト放送タイトル',
            providerName: 'テスト放送者',
            communityName: 'テストコミュニティ',
          ),
        ],
      );

      expect(find.text('テスト放送タイトル'), findsOneWidget);
      expect(
        find.text('テスト放送者 / テストコミュニティ - lv123456789'),
        findsOneWidget,
      );
    });

    testWidgets('shows provider info without community when absent', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv987654321',
            title: 'コミュニティなし放送',
            providerName: '放送者A',
          ),
        ],
      );

      expect(find.text('放送者A - lv987654321'), findsOneWidget);
    });

    testWidgets('shows program count in header', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv111',
            title: '放送1',
            providerName: '放送者1',
          ),
          FollowProgram(
            programId: 'lv222',
            title: '放送2',
            providerName: '放送者2',
          ),
        ],
      );

      expect(find.text('フォロー中の放送'), findsOneWidget);
      expect(find.text('2件'), findsOneWidget);
    });

    testWidgets('shows elapsed time with clock icon', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv333',
            title: '経過時間テスト',
            providerName: '放送者',
            beginAt: DateTime.now().subtract(const Duration(minutes: 45)),
          ),
        ],
      );

      expect(find.textContaining(RegExp(r'^0:45:\d{2}$')), findsOneWidget);
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('shows fallback icon when providerIconUrl is null', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv444',
            title: 'アイコンなし',
            providerName: '放送者',
          ),
        ],
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('tapping tile fills input and starts connection', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(
            programId: 'lv555666777',
            title: 'タップテスト放送',
            providerName: 'タップ放送者',
          ),
        ],
      );

      await tester.tap(find.text('タップテスト放送'));
      await tester.pumpAndSettle();

      expect(find.byType(CommentScreen), findsOneWidget);
    });

    testWidgets('hides list when programs are empty', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[],
      );

      // Flush retry timers (1s + 2s backoff for 3 attempts) so no
      // pending timer remains after the test.
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('フォロー中の放送'), findsNothing);
    });
  });

  group('user attribute real-time reflection', () {
    late ConnectionSupervisor supervisor;
    late TimelineStore timelineStore;
    late InMemoryUserAttributeStore userAttributeStore;
    late ValueNotifier<String?> supplierUserIdNotifier;

    setUp(() {
      supervisor = ConnectionSupervisor();
      timelineStore = TimelineStore();
      userAttributeStore = InMemoryUserAttributeStore();
      supplierUserIdNotifier = ValueNotifier<String?>(null);
    });

    tearDown(() {
      supplierUserIdNotifier.dispose();
    });

    Future<void> pumpAndNavigate(WidgetTester tester) async {
      timelineStore.add(
        AppMessage(
          id: 'msg-1',
          timestamp: DateTime(2026, 3, 28, 10, 0, 0),
          userId: 'user-1',
          content: 'テストコメント',
          type: AppMessageType.chat,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            timelineStore: timelineStore,
            userAttributeStore: userAttributeStore,
            supplierUserIdNotifier: supplierUserIdNotifier,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(inputField(), 'lv345678901');
      await tester.pump();
      await tester.tap(connectButton());
      await tester.pumpAndSettle();

      expect(find.byType(CommentScreen), findsOneWidget);
    }

    testWidgets(
        'color loaded via supplierUserIdNotifier is reflected in comment row',
        (WidgetTester tester) async {
      // Pre-seed color data for broadcaster
      await userAttributeStore.setColor(
        broadcasterId: 'broadcaster-1',
        userId: 'user-1',
        colorValue: 0xFFE53935,
      );

      await pumpAndNavigate(tester);

      // Initially no custom color (broadcaster not resolved yet)
      Text text = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      expect(text.style?.color, isNull);

      // Trigger attribute load by resolving supplier user ID
      supplierUserIdNotifier.value = 'broadcaster-1';
      await tester.pumpAndSettle();

      // Verify color is now reflected
      text = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      expect(text.style?.color, isNotNull);
    });

    testWidgets(
        'nickname loaded via supplierUserIdNotifier is reflected in comment row',
        (WidgetTester tester) async {
      // Pre-seed nickname data for broadcaster
      await userAttributeStore.setNickname(
        broadcasterId: 'broadcaster-1',
        userId: 'user-1',
        nickname: 'テストニックネーム',
      );

      await pumpAndNavigate(tester);

      // Initially no nickname
      Text text = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, isNot(contains('テストニックネーム')));

      // Trigger attribute load
      supplierUserIdNotifier.value = 'broadcaster-1';
      await tester.pumpAndSettle();

      // Verify nickname is now reflected
      text = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, contains('テストニックネーム'));
    });

    testWidgets(
        'color change via user detail sheet is reflected in comment row',
        (WidgetTester tester) async {
      await pumpAndNavigate(tester);

      // Set broadcaster ID so callbacks work
      supplierUserIdNotifier.value = 'broadcaster-1';
      await tester.pumpAndSettle();

      // Long press → comment actions sheet
      await tester.longPress(find.byKey(const Key('comment-row-msg-1')));
      await tester.pumpAndSettle();

      // Tap "ユーザー詳細"
      await tester.tap(find.byKey(const Key('action-user-detail')));
      await tester.pumpAndSettle();

      // Tap red color (0xFFE53935 = 4293212469)
      await tester.tap(find.byKey(const Key('user-color-4293212469')));
      await tester.pumpAndSettle();

      // Verify color is reflected in comment row
      final Text coloredText = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      expect(coloredText.style?.color, isNotNull);
    });
  });

  group('my broadcast section', () {
    Future<void> pumpWithMyProgram(
      WidgetTester tester, {
      FollowProgram? myProgram,
      List<FollowProgram> followPrograms = const <FollowProgram>[],
    }) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository =
          _FakeMyProgramRepository(myProgram);
      final _FakeFollowProgramRepository followRepository =
          _FakeFollowProgramRepository(followPrograms);

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userSessionStore: userSessionStore,
            followProgramRepository: followRepository,
            myProgramRepository: myRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows own broadcast section when user is broadcasting',
        (WidgetTester tester) async {
      await pumpWithMyProgram(
        tester,
        myProgram: FollowProgram(
          programId: 'lv100',
          title: '自分のテスト放送',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
      );

      // Flush follow-program retry timers.
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('あなたの放送'), findsOneWidget);
      expect(find.text('自分のテスト放送'), findsOneWidget);
    });

    testWidgets('hides own broadcast section when not broadcasting',
        (WidgetTester tester) async {
      await pumpWithMyProgram(tester);

      // Flush retry timers.
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('あなたの放送'), findsNothing);
    });

    testWidgets('own broadcast section appears above follow list',
        (WidgetTester tester) async {
      await pumpWithMyProgram(
        tester,
        myProgram: FollowProgram(
          programId: 'lv100',
          title: '自分の放送',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
        followPrograms: <FollowProgram>[
          FollowProgram(
            programId: 'lv200',
            title: 'フォロー放送',
            providerName: 'フォロー放送者',
          ),
        ],
      );

      expect(find.text('あなたの放送'), findsOneWidget);
      expect(find.text('フォロー中の放送'), findsOneWidget);

      final double mySection = tester.getTopLeft(find.text('あなたの放送')).dy;
      final double followSection = tester.getTopLeft(find.text('フォロー中の放送')).dy;
      expect(mySection, lessThan(followSection));
    });

    testWidgets('tapping own broadcast tile starts connection',
        (WidgetTester tester) async {
      await pumpWithMyProgram(
        tester,
        myProgram: FollowProgram(
          programId: 'lv100200300',
          title: '自分の放送タップテスト',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
      );

      // Flush follow-program retry timers.
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.text('自分の放送タップテスト'));
      await tester.pumpAndSettle();

      expect(find.byType(CommentScreen), findsOneWidget);
    });

    testWidgets('shows videocam icon in header', (WidgetTester tester) async {
      await pumpWithMyProgram(
        tester,
        myProgram: FollowProgram(
          programId: 'lv100',
          title: '放送',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
      );

      // Flush retry timers.
      await tester.pump(const Duration(seconds: 4));

      // Header icon (16px) and fallback tile icon (22px) both use videocam.
      expect(find.byIcon(Icons.videocam), findsAtLeastNWidgets(1));
    });

    testWidgets('retries fetching own program on initial null response',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository =
          _FakeMyProgramRepository(FollowProgram(
        programId: 'lv999',
        title: 'リトライ後の放送',
        providerName: '自分',
        isOwnBroadcast: true,
      ));
      // Return null on the first call, then the real program.
      myRepository.nullResponseCount = 1;

      final _FakeFollowProgramRepository followRepository =
          _FakeFollowProgramRepository(const <FollowProgram>[]);

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userSessionStore: userSessionStore,
            followProgramRepository: followRepository,
            myProgramRepository: myRepository,
          ),
        ),
      );

      // Flush retry delays (exponential backoff: 1s, 2s).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(myRepository.fetchCallCount, greaterThanOrEqualTo(2));
      expect(find.text('あなたの放送'), findsOneWidget);
      expect(find.text('リトライ後の放送'), findsOneWidget);
    });

    testWidgets(
        'own program still displays when follow program fetch throws',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository =
          _FakeMyProgramRepository(FollowProgram(
        programId: 'lv100',
        title: '自分の放送',
        providerName: '自分',
        isOwnBroadcast: true,
      ));

      final _FakeFollowProgramRepository followRepository =
          _FakeFollowProgramRepository(const <FollowProgram>[]);
      followRepository.shouldThrow = true;

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userSessionStore: userSessionStore,
            followProgramRepository: followRepository,
            myProgramRepository: myRepository,
          ),
        ),
      );

      // Flush retry timers.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Own broadcast section should still appear despite follow fetch error.
      expect(find.text('あなたの放送'), findsOneWidget);
      expect(find.text('自分の放送'), findsOneWidget);
    });

    testWidgets(
        'follow programs still display when own program fetch throws',
        (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository =
          _FakeMyProgramRepository(null);
      myRepository.shouldThrow = true;

      final _FakeFollowProgramRepository followRepository =
          _FakeFollowProgramRepository(<FollowProgram>[
        FollowProgram(
          programId: 'lv200',
          title: 'フォロー放送',
          providerName: 'フォロー放送者',
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userSessionStore: userSessionStore,
            followProgramRepository: followRepository,
            myProgramRepository: myRepository,
          ),
        ),
      );

      // Flush retry timers.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Own broadcast section should not appear.
      expect(find.text('あなたの放送'), findsNothing);
      // Follow programs should still display despite the error.
      expect(find.text('フォロー放送'), findsOneWidget);
    });
  });
}

class _FakeMyProgramRepository extends MyProgramRepository {
  _FakeMyProgramRepository(this._program);

  final FollowProgram? _program;

  int fetchCallCount = 0;

  /// When non-null, [fetchOwnProgram] returns `null` for the first
  /// [nullResponseCount] calls, then returns [_program].
  int? nullResponseCount;

  /// When true, [fetchOwnProgram] throws an exception instead of returning.
  bool shouldThrow = false;

  @override
  Future<FollowProgram?> fetchOwnProgram({
    required String userSession,
  }) async {
    fetchCallCount++;
    if (shouldThrow) {
      throw Exception('Simulated API error');
    }
    if (nullResponseCount != null && fetchCallCount <= nullResponseCount!) {
      return null;
    }
    return _program;
  }
}

class _FakeFollowProgramRepository extends FollowProgramRepository {
  _FakeFollowProgramRepository(this._programs);

  final List<FollowProgram> _programs;

  /// When true, [fetchOnAirPrograms] throws an exception instead of returning.
  bool shouldThrow = false;

  @override
  Future<List<FollowProgram>> fetchOnAirPrograms({
    required String userSession,
  }) async {
    if (shouldThrow) {
      throw Exception('Simulated follow API error');
    }
    return _programs;
  }
}

class _FakeUserAttributeStore implements UserAttributeStore {
  _FakeUserAttributeStore({
    Map<String, Map<String, int>> colorsByBroadcaster =
        const <String, Map<String, int>>{},
    Map<String, Map<String, String>> nicknamesByBroadcaster =
        const <String, Map<String, String>>{},
  })  : _colorsByBroadcaster = colorsByBroadcaster.map(
          (String broadcasterId, Map<String, int> colors) =>
              MapEntry<String, Map<String, int>>(
            broadcasterId,
            Map<String, int>.from(colors),
          ),
        ),
        _nicknamesByBroadcaster = nicknamesByBroadcaster.map(
          (String broadcasterId, Map<String, String> nicknames) =>
              MapEntry<String, Map<String, String>>(
            broadcasterId,
            Map<String, String>.from(nicknames),
          ),
        );

  final Map<String, Map<String, int>> _colorsByBroadcaster;
  final Map<String, Map<String, String>> _nicknamesByBroadcaster;

  @override
  Future<Map<String, int>> loadColors(String broadcasterId) async {
    return Map<String, int>.from(
      _colorsByBroadcaster[broadcasterId] ?? const <String, int>{},
    );
  }

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) async {
    return Map<String, String>.from(
      _nicknamesByBroadcaster[broadcasterId] ?? const <String, String>{},
    );
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    final Map<String, int> colors =
        _colorsByBroadcaster.putIfAbsent(broadcasterId, () => <String, int>{});
    colors[userId] = colorValue;
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    _colorsByBroadcaster[broadcasterId]?.remove(userId);
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {
    final Map<String, String> nicknames = _nicknamesByBroadcaster.putIfAbsent(
      broadcasterId,
      () => <String, String>{},
    );
    nicknames[userId] = nickname;
  }

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) async {
    _nicknamesByBroadcaster[broadcasterId]?.remove(userId);
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    return 0;
  }
}
