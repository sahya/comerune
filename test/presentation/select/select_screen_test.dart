import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/application/timeline/timeline_store.dart';
import 'package:comerune/data/follow/favorite_user_live_checker.dart';
import 'package:comerune/domain/models/follow_program.dart';
import 'package:comerune/data/follow/follow_program_repository.dart';
import 'package:comerune/data/follow/my_program_repository.dart';
import 'package:comerune/data/niconico/broadcaster_embed_resolver.dart';
import 'package:comerune/data/user/user_attribute_store.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/user_name_resolution.dart';
import 'package:comerune/presentation/select/select_screen.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';

import '../../helpers/fake_broadcaster_embed_resolver.dart';
import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/in_memory_user_attribute_store.dart';
import '../../helpers/in_memory_user_session_store.dart';

Finder inputField() => find.byKey(const Key('select_screen_input'));
Finder connectButton() => find.byKey(const Key('select_screen_connect_button'));

void main() {
  _registerIssue697MuteTests();

  test('buildBroadcastEndedNotificationId is unique for same milliseconds', () {
    final String id0 = buildBroadcastEndedNotificationId(
      epochMilliseconds: 1234567890,
      sequence: 0,
    );
    final String id1 = buildBroadcastEndedNotificationId(
      epochMilliseconds: 1234567890,
      sequence: 1,
    );

    expect(id0, isNot(id1));
    expect(id0, startsWith('system:broadcast_ended:1234567890:'));
    expect(id1, startsWith('system:broadcast_ended:1234567890:'));
  });

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

  testWidgets('auto-follows newly added live comments when TimelineStore grows '
      'past the initial fetch count', (WidgetTester tester) async {
    // Regression: auto-scroll used to work only by coincidence of trim
    // (list length held constant → no extent growth). After the
    // displayCapacity fix preserved past history, new arrivals grew the
    // list and the view stopped following the latest comment because
    // diffing `oldWidget.messages` vs `widget.messages` sees equal
    // snapshots (both are `UnmodifiableListView` over the same mutable
    // list). This test pins the independent state-tracked detection.
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final TimelineStore timelineStore = TimelineStore(capacity: 5100);

    // Seed enough messages to make the ListView actually scrollable.
    final DateTime base = DateTime(2026, 3, 28, 10, 0, 0);
    for (int i = 0; i < 80; i++) {
      timelineStore.add(
        AppMessage(
          id: 'seed-$i',
          timestamp: base.add(Duration(seconds: i)),
          userId: 'u',
          content: 'seed $i',
          type: AppMessageType.chat,
        ),
      );
    }

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

    // Capture the scroll extent at the initial view. The post-mount
    // `_scrollToEdge` runs in a postFrameCallback so `pumpAndSettle`
    // above guarantees the controller is already at the tail.
    final ScrollController controller = tester
        .widget<ListView>(find.byKey(const Key('comment-list')))
        .controller!;
    final double extentBefore = controller.position.maxScrollExtent;
    expect(
      controller.position.pixels,
      closeTo(extentBefore, 0.5),
      reason: 'view should start at the tail after initial mount',
    );

    // Inject new live comments that extend the list beyond the initial
    // viewport. This grows maxScrollExtent; the view must auto-scroll
    // to the new tail. Timestamps are placed strictly after every seed
    // so each new arrival actually becomes `messages.last`.
    final DateTime liveBase = base.add(const Duration(hours: 1));
    for (int i = 0; i < 20; i++) {
      timelineStore.add(
        AppMessage(
          id: 'live-$i',
          timestamp: liveBase.add(Duration(seconds: i)),
          userId: 'u',
          content: 'live $i',
          type: AppMessageType.chat,
        ),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final double extentAfter = controller.position.maxScrollExtent;
    expect(
      extentAfter,
      greaterThan(extentBefore),
      reason: 'new live comments should extend the scrollable area',
    );
    // If auto-scroll silently regressed (as happened when `_hasNewMessages`
    // diffed two `UnmodifiableListView` instances over the same mutable
    // list), `pixels` would stay at `extentBefore` and the user would be
    // stranded well behind the new tail. Allow a small slack window for
    // animation / rendering timing, but assert we've crossed well past
    // the initial tail toward the new one.
    final double crossedDistance = controller.position.pixels - extentBefore;
    final double availableGrowth = extentAfter - extentBefore;
    expect(
      crossedDistance,
      greaterThan(availableGrowth * 0.5),
      reason:
          'auto-scroll must follow the newly added latest comment; if the '
          'view lags behind the new maxScrollExtent, `_hasNewMessages` '
          'was likely relied upon and failed silently (pre-fix symptom). '
          'pixels=${controller.position.pixels}, '
          'extentBefore=$extentBefore, extentAfter=$extentAfter',
    );
  });

  testWidgets(
    'does NOT auto-scroll to tail while user is scrolled away from the tail',
    (WidgetTester tester) async {
      // Contract: when the user has manually scrolled up to read older
      // comments, `_autoScrollEnabled` flips to false and new arrivals
      // must NOT yank the viewport back to the tail. This pins the other
      // half of the auto-scroll contract alongside the forward-follow
      // test above.
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final TimelineStore timelineStore = TimelineStore(capacity: 5100);

      final DateTime base = DateTime(2026, 3, 28, 10, 0, 0);
      for (int i = 0; i < 80; i++) {
        timelineStore.add(
          AppMessage(
            id: 'seed-$i',
            timestamp: base.add(Duration(seconds: i)),
            userId: 'u',
            content: 'seed $i',
            type: AppMessageType.chat,
          ),
        );
      }

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

      final ScrollController controller = tester
          .widget<ListView>(find.byKey(const Key('comment-list')))
          .controller!;

      // Simulate a user dragging the list upward to read older comments.
      // A large upward swipe flips `_autoScrollEnabled` off via
      // `_handleScrollAscending`.
      await tester.drag(
        find.byKey(const Key('comment-list')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();

      final double pixelsAfterManualScroll = controller.position.pixels;
      final double extentBeforeLive = controller.position.maxScrollExtent;
      expect(
        pixelsAfterManualScroll,
        lessThan(extentBeforeLive - 50),
        reason:
            'the manual drag must move the view clearly away from the tail '
            'so `_autoScrollEnabled` flips to false',
      );

      // Inject new live comments while the user is scrolled up.
      final DateTime liveBase = base.add(const Duration(hours: 1));
      for (int i = 0; i < 20; i++) {
        timelineStore.add(
          AppMessage(
            id: 'live-$i',
            timestamp: liveBase.add(Duration(seconds: i)),
            userId: 'u',
            content: 'live $i',
            type: AppMessageType.chat,
          ),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // The view must stay roughly where the user left it, not snap back
      // to the tail. maxScrollExtent may have grown, but pixels should
      // remain near pixelsAfterManualScroll.
      final double pixelsAfterLive = controller.position.pixels;
      expect(
        pixelsAfterLive,
        closeTo(pixelsAfterManualScroll, 50),
        reason:
            'auto-scroll must stay disabled when the user is scrolled away '
            'from the tail; `pixels` must not be yanked to the new '
            'maxScrollExtent. pixelsAfterLive=$pixelsAfterLive, '
            'pixelsAfterManualScroll=$pixelsAfterManualScroll, '
            'newExtent=${controller.position.maxScrollExtent}',
      );
    },
  );

  testWidgets(
    'startConnection updates TimelineStore capacity to displayCapacity '
    'so fetched history is not evicted by incoming live comments',
    (WidgetTester tester) async {
      // Regression wiring test: guards against a future refactor that
      // re-wires `setCapacity` back to `historyCount` (the original bug).
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      // Start with an intentionally unrelated capacity so the assertion
      // proves the connect flow updated it.
      final TimelineStore timelineStore = TimelineStore(capacity: 1);

      const AppSettings settings = AppSettings.defaults;
      const PastCommentFetchCount fetchCount = PastCommentFetchCount.count500;
      final AppSettings settingsWith500 = settings.copyWith(
        pastCommentFetchCount: fetchCount,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            timelineStore: timelineStore,
            initialSettings: settingsWith500,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(inputField(), 'lv345678901');
      await tester.pump();
      await tester.tap(connectButton());
      await tester.pumpAndSettle();

      // `displayCapacity` must be used, not `historyCount`. This pins the
      // invariant: capacity > historyCount, so live influx never trims
      // the freshly fetched history.
      expect(timelineStore.capacity, fetchCount.displayCapacity);
      expect(
        timelineStore.capacity,
        greaterThan(fetchCount.historyCount),
        reason: 'regression: TimelineStore.capacity must exceed historyCount',
      );
    },
  );

  testWidgets(
    'keeps name resolution callbacks enabled when showUserName is false',
    (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setBool('settings.comment.showUserName', false);
      await prefs.setBool('settings.comment.resolveUserName', true);
      await prefs.setBool('settings.tts.readUserName', true);
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: prefs,
      );
      final List<String> requestedUserIds = <String>[];
      final UserNameResolution userNameResolution = UserNameResolution(
        resolve: (_) => '解決名',
        requestResolve: requestedUserIds.add,
        listenable: ChangeNotifier(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            settingsStore: settingsStore,
            userNameResolution: userNameResolution,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(inputField(), 'lv345678901');
      await tester.pump();
      await tester.tap(connectButton());
      await tester.pumpAndSettle();

      final CommentScreen commentScreen = tester.widget<CommentScreen>(
        find.byType(CommentScreen),
      );
      expect(commentScreen.showUserName, isFalse);
      expect(commentScreen.speechConfig.readUserName, isTrue);
      expect(commentScreen.userNameResolution?.resolve, isNotNull);
      expect(commentScreen.userNameResolution?.requestResolve, isNotNull);

      commentScreen.userNameResolution?.requestResolve('12345');
      expect(requestedUserIds, <String>['12345']);
    },
  );

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
      expect(notification.id, startsWith(kSystemBroadcastEndedMessageIdPrefix));

      // Verify the notification is visible in the comment screen.
      expect(find.textContaining('放送が終了しました'), findsOneWidget);
    },
  );

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
    },
  );

  testWidgets('does not add notification when user stops manually (stopped)', (
    WidgetTester tester,
  ) async {
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

    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.stopByUser(), isTrue);
    await tester.pumpAndSettle();

    final List<AppMessage> notifications = timelineStore.messages
        .where((AppMessage m) => m.type == AppMessageType.notification)
        .toList();
    expect(notifications, isEmpty);
  });

  testWidgets('does not add notification when connection fails', (
    WidgetTester tester,
  ) async {
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

    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.fail(ConnectionErrorCode.ndgrStreamFailed), isTrue);
    await tester.pumpAndSettle();

    final List<AppMessage> notifications = timelineStore.messages
        .where((AppMessage m) => m.type == AppMessageType.notification)
        .toList();
    expect(notifications, isEmpty);
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

    expect(find.byKey(const Key('login-status-banner-ok')), findsOneWidget);
    expect(find.text('ニコニコ ログイン済み'), findsOneWidget);
    expect(find.byKey(const Key('login-status-banner-required')), findsNothing);
  });

  testWidgets(
    'hides login banner when settingsStore is provided but userSessionStore is null',
    (WidgetTester tester) async {
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

      expect(find.byKey(const Key('login-status-banner-ok')), findsNothing);
      expect(
        find.byKey(const Key('login-status-banner-required')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('select_screen_settings_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('hides login banner when settingsStore is null', (
    WidgetTester tester,
  ) async {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    await pumpSelectScreen(tester, supervisor);

    expect(find.byKey(const Key('login-status-banner-ok')), findsNothing);
    expect(find.byKey(const Key('login-status-banner-required')), findsNothing);
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
      commentScreen.callbacks.onNicknameChanged?.call('user-1', 'コテハン名');
      await tester.pump();

      expect(find.textContaining('コテハン名 (user-1)'), findsOneWidget);

      commentScreen = tester.widget<CommentScreen>(find.byType(CommentScreen));
      commentScreen.callbacks.onUserColorChanged?.call('user-1', 0xFFE53935);
      await tester.pump();

      final Text textWidget = tester.widget(
        find.descendant(
          of: find.byKey(const Key('comment-row-msg-1')),
          matching: find.byType(Text),
        ),
      );
      // Text.rich is used; check the content span (last child) for color.
      final TextSpan root = textWidget.textSpan! as TextSpan;
      final TextSpan contentSpan = root.children!.last as TextSpan;
      expect(contentSpan.style?.color, colorFromARGB32(0xFFE53935));
    },
  );

  testWidgets('resets user color and nickname maps when connected lv changes', (
    WidgetTester tester,
  ) async {
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
    final TextSpan coloredRoot = coloredText.textSpan! as TextSpan;
    final TextSpan coloredContentSpan = coloredRoot.children!.last as TextSpan;
    expect(coloredContentSpan.style?.color, colorFromARGB32(0xFFE53935));

    final CommentScreen commentScreen = tester.widget<CommentScreen>(
      find.byType(CommentScreen),
    );
    await commentScreen.callbacks.onDifferentLvConnected(
      'lv345678901',
      'lv999999999',
    );
    await tester.pump();

    final CommentScreen updated = tester.widget<CommentScreen>(
      find.byType(CommentScreen),
    );
    expect(updated.contentFilter.userColorMap, isEmpty);
    expect(updated.contentFilter.userNicknameMap, isEmpty);

    expect(find.byKey(const Key('comment-row-msg-1')), findsNothing);
    expect(find.textContaining('初期コテハン (user-1)'), findsNothing);
  });

  testWidgets(
    'shows broadcasterName from notifier when supplierUserId is null',
    (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final TimelineStore timelineStore = TimelineStore();
      final ValueNotifier<String?> supplierUserIdNotifier =
          ValueNotifier<String?>(null);
      final ValueNotifier<String?> broadcasterNameNotifier =
          ValueNotifier<String?>(null);

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
            broadcasterNameNotifier: broadcasterNameNotifier,
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(inputField(), 'lv345678901');
      await tester.pump();
      await tester.tap(connectButton());
      await tester.pumpAndSettle();

      broadcasterNameNotifier.value = 'URL入力フォールバック名';
      await tester.pumpAndSettle();

      final CommentScreen commentScreen = tester.widget<CommentScreen>(
        find.byType(CommentScreen),
      );
      expect(commentScreen.programInfo.broadcasterName, 'URL入力フォールバック名');
      expect(commentScreen.programInfo.broadcasterUserId, isNull);
    },
  );

  group('follow program list', () {
    Future<void> pumpWithFollowPrograms(
      WidgetTester tester, {
      required List<FollowProgram> programs,
      ValueNotifier<DateTime?>? beginAtNotifier,
      ValueNotifier<DateTime?>? vposBaseAtNotifier,
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
            beginAtNotifier: beginAtNotifier,
            vposBaseAtNotifier: vposBaseAtNotifier,
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
      expect(find.text('テスト放送者 / テストコミュニティ - lv123456789'), findsOneWidget);
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

    testWidgets('shows program count in header', (WidgetTester tester) async {
      await pumpWithFollowPrograms(
        tester,
        programs: <FollowProgram>[
          FollowProgram(programId: 'lv111', title: '放送1', providerName: '放送者1'),
          FollowProgram(programId: 'lv222', title: '放送2', providerName: '放送者2'),
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

    testWidgets(
      'falls back to beginAtNotifier when follow beginAt is in the future',
      (WidgetTester tester) async {
        final DateTime notifierBeginAt = DateTime.now().subtract(
          const Duration(minutes: 10),
        );
        final ValueNotifier<DateTime?> beginAtNotifier =
            ValueNotifier<DateTime?>(notifierBeginAt);
        addTearDown(beginAtNotifier.dispose);

        await pumpWithFollowPrograms(
          tester,
          programs: <FollowProgram>[
            FollowProgram(
              programId: 'lv777888999',
              title: 'future beginAt fallback test',
              providerName: 'tester',
              beginAt: DateTime.now().add(const Duration(hours: 2)),
            ),
          ],
          beginAtNotifier: beginAtNotifier,
        );

        await tester.tap(find.text('future beginAt fallback test'));
        await tester.pumpAndSettle();

        final CommentScreen commentScreen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(commentScreen.programInfo.beginAt, notifierBeginAt);
      },
    );

    testWidgets(
      'forwards vposBaseAtNotifier value to CommentScreen.programInfo.vposBaseAt '
      '(Issue #465 plumbing)',
      (WidgetTester tester) async {
        // Locks the main.dart → SelectScreen → CommentProgramInfo plumbing
        // chain so a future refactor cannot silently drop vposBaseAt from
        // the CommentScreen entry point. Without this test, the per-unit
        // resolver + controller tests would still pass even if the UI
        // stopped forwarding the value.
        final DateTime notifierVposBaseAt = DateTime.utc(2026, 1, 1, 10);
        final ValueNotifier<DateTime?> vposBaseAtNotifier =
            ValueNotifier<DateTime?>(notifierVposBaseAt);
        addTearDown(vposBaseAtNotifier.dispose);

        await pumpWithFollowPrograms(
          tester,
          programs: <FollowProgram>[
            FollowProgram(
              programId: 'lv465000001',
              title: 'vposBaseAt plumbing test',
              providerName: 'tester',
            ),
          ],
          vposBaseAtNotifier: vposBaseAtNotifier,
        );

        await tester.tap(find.text('vposBaseAt plumbing test'));
        await tester.pumpAndSettle();

        final CommentScreen commentScreen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(commentScreen.programInfo.vposBaseAt, notifierVposBaseAt);
      },
    );

    testWidgets('hides list when programs are empty', (
      WidgetTester tester,
    ) async {
      await pumpWithFollowPrograms(tester, programs: <FollowProgram>[]);

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
        // Text.rich is used; check the content span (last child) for color.
        TextSpan root = text.textSpan! as TextSpan;
        TextSpan contentSpan = root.children!.last as TextSpan;
        expect(contentSpan.style?.color, isNull);

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
        root = text.textSpan! as TextSpan;
        contentSpan = root.children!.last as TextSpan;
        expect(contentSpan.style?.color, isNotNull);
      },
    );

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
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-msg-1')),
            matching: find.textContaining('テストニックネーム'),
          ),
          findsNothing,
        );

        // Trigger attribute load
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        // Verify nickname is now reflected
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-msg-1')),
            matching: find.textContaining('テストニックネーム'),
          ),
          findsOneWidget,
        );
      },
    );

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
        final TextSpan cRoot = coloredText.textSpan! as TextSpan;
        final TextSpan cContent = cRoot.children!.last as TextSpan;
        expect(cContent.style?.color, isNotNull);
      },
    );

    testWidgets(
      'in-memory nickname set before supplierUserId resolves persists after load',
      (WidgetTester tester) async {
        await pumpAndNavigate(tester);

        // Simulate auto-nickname registration arriving before broadcaster
        // ID is known (e.g. from historical messages).
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-1', '事前ニックネーム');
        await tester.pump();

        // Verify nickname appears in UI.
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-msg-1')),
            matching: find.textContaining('事前ニックネーム'),
          ),
          findsOneWidget,
        );

        // Now resolve broadcaster → triggers _loadUserAttributes with merge.
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        // Nickname must still be visible (merged, not overwritten).
        expect(
          find.descendant(
            of: find.byKey(const Key('comment-row-msg-1')),
            matching: find.textContaining('事前ニックネーム'),
          ),
          findsOneWidget,
        );

        // Verify it was flushed to persistent storage.
        final Map<String, String> stored = await userAttributeStore
            .loadNicknames('broadcaster-1');
        expect(stored['user-1'], '事前ニックネーム');
      },
    );

    testWidgets(
      'in-memory color set before supplierUserId resolves persists after load',
      (WidgetTester tester) async {
        await pumpAndNavigate(tester);

        // Simulate a color change before broadcaster ID is known.
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onUserColorChanged!('user-1', 0xFFE53935);
        await tester.pump();

        // Resolve broadcaster.
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        // Color must survive the merge.
        final CommentScreen after = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(after.contentFilter.userColorMap['user-1'], 0xFFE53935);

        // Verify it was flushed to persistent storage.
        final Map<String, int> stored = await userAttributeStore.loadColors(
          'broadcaster-1',
        );
        expect(stored['user-1'], 0xFFE53935);
      },
    );

    testWidgets(
      'disk data is merged with in-memory data when broadcaster resolves',
      (WidgetTester tester) async {
        // Pre-seed disk data for a different user.
        await userAttributeStore.setNickname(
          broadcasterId: 'broadcaster-1',
          userId: 'user-disk',
          nickname: 'ディスクユーザー',
        );
        await userAttributeStore.setColor(
          broadcasterId: 'broadcaster-1',
          userId: 'user-disk',
          colorValue: 0xFF1E88E5,
        );

        await pumpAndNavigate(tester);

        // Set in-memory data before broadcaster resolves.
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-1', 'メモリユーザー');
        await tester.pump();

        // Resolve broadcaster.
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        // Both disk and in-memory data must be present.
        final CommentScreen after = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(after.contentFilter.userNicknameMap['user-1'], 'メモリユーザー');
        expect(after.contentFilter.userNicknameMap['user-disk'], 'ディスクユーザー');
        expect(after.contentFilter.userColorMap['user-disk'], 0xFF1E88E5);
      },
    );

    testWidgets('flush skips entries that already match disk data', (
      WidgetTester tester,
    ) async {
      // Pre-seed disk with exact same data that will be in memory.
      await userAttributeStore.setColor(
        broadcasterId: 'broadcaster-1',
        userId: 'user-1',
        colorValue: 0xFFE53935,
      );

      await pumpAndNavigate(tester);

      // Set the same value in memory before broadcaster resolves.
      final CommentScreen screen = tester.widget<CommentScreen>(
        find.byType(CommentScreen),
      );
      screen.callbacks.onUserColorChanged!('user-1', 0xFFE53935);
      await tester.pump();

      // Resolve broadcaster.
      supplierUserIdNotifier.value = 'broadcaster-1';
      await tester.pumpAndSettle();

      // Color must be present (merged).
      final CommentScreen after = tester.widget<CommentScreen>(
        find.byType(CommentScreen),
      );
      expect(after.contentFilter.userColorMap['user-1'], 0xFFE53935);

      // Disk still has original value (no redundant write).
      final Map<String, int> stored = await userAttributeStore.loadColors(
        'broadcaster-1',
      );
      expect(stored['user-1'], 0xFFE53935);
    });

    testWidgets(
      'reconnect via onReconnectSameLv reloads attributes from disk',
      (WidgetTester tester) async {
        // Pre-seed disk data.
        await userAttributeStore.setColor(
          broadcasterId: 'broadcaster-1',
          userId: 'user-1',
          colorValue: 0xFFE53935,
        );
        await userAttributeStore.setNickname(
          broadcasterId: 'broadcaster-1',
          userId: 'user-1',
          nickname: 'ディスクコテハン',
        );

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
              onPrepareConnection: (String lv, AppSettings settings) async {
                supplierUserIdNotifier.value = null;
              },
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
        expect(
          tester
              .widget<CommentScreen>(find.byType(CommentScreen))
              .contentFilter
              .userColorMap['user-1'],
          0xFFE53935,
        );

        await userAttributeStore.setNickname(
          broadcasterId: 'broadcaster-1',
          userId: 'user-new',
          nickname: '新規ユーザー',
        );

        await tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onReconnectSameLv();
        await tester.pump();
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        final CommentScreen after = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(
          after.contentFilter.userNicknameMap['user-new'],
          '新規ユーザー',
          reason: 'New disk entry must be loaded after onReconnectSameLv',
        );
        expect(after.contentFilter.userColorMap['user-1'], 0xFFE53935);
        expect(after.contentFilter.userNicknameMap['user-1'], 'ディスクコテハン');
      },
    );

    testWidgets(
      'disk change is picked up after lv switch clears in-memory state',
      (WidgetTester tester) async {
        await pumpAndNavigate(tester);

        // Resolve broadcaster and load initial data.
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        // Set a nickname via callback (simulates user action).
        tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onNicknameChanged!('user-1', '古いニックネーム');
        await tester.pumpAndSettle();

        // Re-fetch widget after rebuild to verify.
        expect(
          tester
              .widget<CommentScreen>(find.byType(CommentScreen))
              .contentFilter
              .userNicknameMap['user-1'],
          '古いニックネーム',
        );

        // Simulate what _openSettings does after settings screen returns:
        // write a new value directly to the store, then force reload by
        // switching to a different broadcaster and back (resets
        // _currentBroadcasterId so _loadUserAttributes runs again).
        await userAttributeStore.setNickname(
          broadcasterId: 'broadcaster-1',
          userId: 'user-1',
          nickname: '設定画面で変更',
        );

        // Reset _currentBroadcasterId so _loadUserAttributes will run again.
        await tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onDifferentLvConnected('lv345678901', 'lv999999999');
        await tester.pump();

        // Clear then re-set supplierUserIdNotifier so ValueNotifier fires.
        supplierUserIdNotifier.value = null;
        await tester.pump();
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        final CommentScreen after = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        expect(after.contentFilter.userNicknameMap['user-1'], '設定画面で変更');
      },
    );

    testWidgets(
      'switching to a different lv clears in-memory attrs so broadcaster A '
      'data is not written to broadcaster B file',
      (WidgetTester tester) async {
        // Simulate broadcaster A connection + in-memory changes.
        await pumpAndNavigate(tester);
        supplierUserIdNotifier.value = 'broadcaster-A';
        await tester.pumpAndSettle();

        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-A', 'Aの古いコテハン');
        screen.callbacks.onUserColorChanged!('user-A', 0xFFE53935);
        await tester.pump();

        // Navigate back to the select screen and connect to a different lv
        // (broadcaster B). Without the fix, A's in-memory nickname would be
        // merged into B's file via `_flushPendingAttributes`.
        await tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onStopAllConnections();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(CommentScreen))).pop();
        await tester.pumpAndSettle();

        // Guard: verify we are back on SelectScreen.
        expect(find.byType(SelectScreen), findsOneWidget);
        expect(supervisor.canStartConnection, isTrue);

        supplierUserIdNotifier.value = null;
        await tester.pump();

        await tester.enterText(inputField(), 'lv999999999');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        supplierUserIdNotifier.value = 'broadcaster-B';
        await tester.pumpAndSettle();

        // Broadcaster B's file must not contain any of A's data.
        final Map<String, String> bStored = await userAttributeStore
            .loadNicknames('broadcaster-B');
        expect(
          bStored['user-A'],
          isNull,
          reason: 'broadcaster-A の in-memory データが broadcaster-B に漏洩してはいけない',
        );
        expect(bStored, isEmpty);

        final Map<String, int> bColors = await userAttributeStore.loadColors(
          'broadcaster-B',
        );
        expect(
          bColors,
          isEmpty,
          reason: 'broadcaster-A の色データが broadcaster-B に漏洩してはいけない',
        );
      },
    );

    testWidgets(
      'direct lv input does not create an orphan lv-keyed file while waiting '
      'for supplier resolution',
      (WidgetTester tester) async {
        await pumpAndNavigate(tester);
        // supplier has NOT resolved yet.

        // Auto-nickname registration fires while supplier is unresolved
        // (simulates @コテハン auto-registration from past comments during
        // the resolution window on a slow emulator).
        tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onNicknameChanged!('user-1', '自動登録ニックネーム');
        await tester.pump();

        // No lv-keyed file/entry must be created.
        final Map<String, String> lvStored = await userAttributeStore
            .loadNicknames('lv345678901');
        expect(lvStored, isEmpty, reason: 'lv キーでの永続化は行われてはならない');

        // Once supplier resolves, the accumulated in-memory changes should
        // be flushed to the real broadcaster's file.
        supplierUserIdNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        final Map<String, String> realStored = await userAttributeStore
            .loadNicknames('broadcaster-1');
        expect(realStored['user-1'], '自動登録ニックネーム');
      },
    );

    testWidgets(
      'embed resolver result binds supplierUserIdNotifier for LV-direct input',
      (WidgetTester tester) async {
        // Pre-seed disk attrs for the broadcaster the embed will resolve.
        await userAttributeStore.setNickname(
          broadcasterId: '7654321',
          userId: 'user-1',
          nickname: 'Embed解決ニックネーム',
        );

        final FakeBroadcasterEmbedResolver embedResolver =
            FakeBroadcasterEmbedResolver(
              results: <String, BroadcasterEmbedInfo>{
                'lv345678901': const BroadcasterEmbedInfo(
                  userId: '7654321',
                  name: '配信者A',
                ),
              },
            );

        timelineStore.add(
          AppMessage(
            id: 'msg-1',
            timestamp: DateTime(2026, 4, 25, 12, 0, 0),
            userId: 'user-1',
            content: 'embed test',
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
              broadcasterEmbedResolver: embedResolver,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        expect(embedResolver.resolvedLvs, <String>['lv345678901']);
        expect(supplierUserIdNotifier.value, '7654321');
        expect(
          tester
              .widget<CommentScreen>(find.byType(CommentScreen))
              .contentFilter
              .userNicknameMap['user-1'],
          'Embed解決ニックネーム',
        );
      },
    );

    testWidgets(
      'embed resolver is skipped when preferredBroadcasterId is provided',
      (WidgetTester tester) async {
        final FakeBroadcasterEmbedResolver embedResolver =
            FakeBroadcasterEmbedResolver();

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: supervisor,
              timelineStore: timelineStore,
              userAttributeStore: userAttributeStore,
              supplierUserIdNotifier: supplierUserIdNotifier,
              broadcasterEmbedResolver: embedResolver,
              followProgramRepository:
                  _FakeFollowProgramRepository(<FollowProgram>[
                    FollowProgram(
                      programId: 'lv345678901',
                      title: 'タップ放送',
                      providerName: '配信者X',
                      providerUserId: '11111',
                      status: ProgramStatus.onAir,
                    ),
                  ]),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        await tester.tap(find.text('タップ放送'));
        await tester.pumpAndSettle();

        // pre-binding via FollowProgram.providerUserId already covers this
        // case, so the embed resolver must not be called.
        expect(embedResolver.resolvedLvs, isEmpty);
        expect(supplierUserIdNotifier.value, '11111');
      },
    );

    testWidgets(
      'embed resolver returning null leaves notifier unchanged so the '
      'accumulate-and-flush path remains in effect',
      (WidgetTester tester) async {
        final FakeBroadcasterEmbedResolver embedResolver =
            FakeBroadcasterEmbedResolver();

        timelineStore.add(
          AppMessage(
            id: 'msg-1',
            timestamp: DateTime(2026, 4, 25, 12, 0, 0),
            userId: 'user-1',
            content: 'no embed',
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
              broadcasterEmbedResolver: embedResolver,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        expect(embedResolver.resolvedLvs, <String>['lv345678901']);
        expect(supplierUserIdNotifier.value, isNull);

        // Programinfo eventually resolves the broadcaster — the legacy
        // accumulate-and-flush path must still work.
        supplierUserIdNotifier.value = 'broadcaster-late';
        await tester.pumpAndSettle();
        expect(supplierUserIdNotifier.value, 'broadcaster-late');
      },
    );

    testWidgets(
      'embed result for an old lv is discarded after the user switches lv',
      (WidgetTester tester) async {
        // Pre-seed disk attrs for the broadcaster the (stale) embed would
        // resolve to so we can detect a mistaken bind.
        await userAttributeStore.setNickname(
          broadcasterId: '1111111',
          userId: 'user-1',
          nickname: 'Aの古い名前',
        );

        final Completer<void> embedGate = Completer<void>();
        final FakeBroadcasterEmbedResolver embedResolver =
            FakeBroadcasterEmbedResolver(
              results: <String, BroadcasterEmbedInfo>{
                'lv111': const BroadcasterEmbedInfo(userId: '1111111'),
              },
            )..setGate('lv111', embedGate.future);

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: supervisor,
              timelineStore: timelineStore,
              userAttributeStore: userAttributeStore,
              supplierUserIdNotifier: supplierUserIdNotifier,
              broadcasterEmbedResolver: embedResolver,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv111');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // Embed for lv111 is still pending (gate not yet released).
        expect(supplierUserIdNotifier.value, isNull);

        // Simulate the user stopping the current connection, navigating
        // back, and starting a different lv before lv111's embed completes.
        await tester
            .widget<CommentScreen>(find.byType(CommentScreen))
            .callbacks
            .onStopAllConnections();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.byType(CommentScreen))).pop();
        await tester.pumpAndSettle();
        await tester.enterText(inputField(), 'lv222');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // Now release the in-flight embed — it must NOT bind to lv111's
        // userId because _lastConnectedLv has moved on.
        embedGate.complete();
        await tester.pumpAndSettle();

        expect(
          supplierUserIdNotifier.value,
          isNot('1111111'),
          reason: '古い lv の embed 結果で別放送者の supplierUserId にバインドしてはならない',
        );
      },
    );

    testWidgets(
      'embed only seeds the name cache when supplierUserIdNotifier is '
      'already populated by another source',
      (WidgetTester tester) async {
        final List<({String userId, String name})> seeds =
            <({String userId, String name})>[];
        final UserNameResolution userNameResolution = UserNameResolution(
          resolve: (_) => null,
          requestResolve: (_) {},
          listenable: ValueNotifier<int>(0),
          seedCache: (String userId, String name) {
            seeds.add((userId: userId, name: name));
          },
        );

        final FakeBroadcasterEmbedResolver embedResolver =
            FakeBroadcasterEmbedResolver(
              results: <String, BroadcasterEmbedInfo>{
                'lv333': const BroadcasterEmbedInfo(
                  userId: '3333333',
                  name: 'Embed放送者',
                ),
              },
            );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: supervisor,
              timelineStore: timelineStore,
              userAttributeStore: userAttributeStore,
              supplierUserIdNotifier: supplierUserIdNotifier,
              userNameResolution: userNameResolution,
              broadcasterEmbedResolver: embedResolver,
              onPrepareConnection: (String lv, AppSettings settings) async {
                // Simulate programinfo resolving the supplier ID before
                // the embed result lands.
                supplierUserIdNotifier.value = '3333333';
              },
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv333');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // The embed must not override the already-resolved supplier ID,
        // but it should still seed the name cache so the comment header
        // can skip a nickname-API round-trip.
        expect(supplierUserIdNotifier.value, '3333333');
        expect(seeds, <({String userId, String name})>[
          (userId: '3333333', name: 'Embed放送者'),
        ]);
      },
    );

    testWidgets('flushes pending user attribute writes on app pause', (
      WidgetTester tester,
    ) async {
      final _FlushTrackingUserAttributeStore trackingStore =
          _FlushTrackingUserAttributeStore();
      final ConnectionSupervisor localSupervisor = ConnectionSupervisor();
      final TimelineStore localTimelineStore = TimelineStore();

      localTimelineStore.add(
        AppMessage(
          id: 'msg-pause',
          timestamp: DateTime(2026, 4, 22, 12, 0, 0),
          userId: 'user-1',
          content: 'pause test',
          type: AppMessageType.chat,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: localSupervisor,
            timelineStore: localTimelineStore,
            userAttributeStore: trackingStore,
          ),
        ),
      );
      await tester.pump();

      final TestWidgetsFlutterBinding binding =
          TestWidgetsFlutterBinding.ensureInitialized();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(trackingStore.flushPendingWritesCallCount, 1);

      addTearDown(() async {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });
    });

    testWidgets(
      'loadAttributes merge: in-memory entries with no disk counterpart are '
      'flushed to the store after broadcaster resolution',
      (WidgetTester tester) async {
        // Use _FakeUserAttributeStore so we can count setColor / setNickname
        // calls (the InMemoryUserAttributeStore fixture used in this group
        // does not track call traffic).
        final _FakeUserAttributeStore localStore = _FakeUserAttributeStore();
        final ConnectionSupervisor localSupervisor = ConnectionSupervisor();
        final TimelineStore localTimelineStore = TimelineStore();
        final ValueNotifier<String?> localSupplierNotifier =
            ValueNotifier<String?>(null);
        addTearDown(localSupplierNotifier.dispose);

        localTimelineStore.add(
          AppMessage(
            id: 'msg-merge',
            timestamp: DateTime(2026, 4, 25, 9, 0, 0),
            userId: 'user-1',
            content: 'merge test',
            type: AppMessageType.chat,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: localSupervisor,
              timelineStore: localTimelineStore,
              supplierUserIdNotifier: localSupplierNotifier,
              userAttributeStore: localStore,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // Accumulate in-memory changes BEFORE the broadcaster ID is known.
        // _currentBroadcasterId is still null, so these go straight into
        // _userAttrNotifier without hitting the store.
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-1', 'メモリ専用ニックネーム');
        screen.callbacks.onUserColorChanged!('user-1', 0xFFE53935);
        await tester.pump();

        // Sanity: nothing should have been written yet because
        // _currentBroadcasterId is null.
        expect(
          localStore.setColorCalls,
          isEmpty,
          reason: 'broadcaster 未確定中に store へ書き込んではいけない',
        );
        expect(localStore.setNicknameCalls, isEmpty);

        // Broadcaster resolves -> _loadUserAttributes runs -> merge happens
        // -> _flushPendingAttributes flushes the in-memory deltas to the
        // store via setColor / setNickname.
        localSupplierNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        expect(localStore.setNicknameCalls, hasLength(1));
        expect(
          localStore.setNicknameCalls.single.broadcasterId,
          'broadcaster-1',
        );
        expect(localStore.setNicknameCalls.single.userId, 'user-1');
        expect(localStore.setNicknameCalls.single.nickname, 'メモリ専用ニックネーム');

        expect(localStore.setColorCalls, hasLength(1));
        expect(localStore.setColorCalls.single.broadcasterId, 'broadcaster-1');
        expect(localStore.setColorCalls.single.userId, 'user-1');
        expect(localStore.setColorCalls.single.colorValue, 0xFFE53935);
      },
    );

    testWidgets(
      'loadAttributes merge: in-memory entries equal to disk are NOT re-flushed',
      (WidgetTester tester) async {
        // Pre-seed disk so disk == in-memory after the user "changes" the
        // value to the same thing. _flushPendingAttributes should detect
        // this and skip the redundant write.
        final _FakeUserAttributeStore localStore = _FakeUserAttributeStore(
          colorsByBroadcaster: <String, Map<String, int>>{
            'broadcaster-1': <String, int>{'user-1': 0xFFE53935},
          },
          nicknamesByBroadcaster: <String, Map<String, String>>{
            'broadcaster-1': <String, String>{'user-1': '同じコテハン'},
          },
        );
        final ConnectionSupervisor localSupervisor = ConnectionSupervisor();
        final TimelineStore localTimelineStore = TimelineStore();
        final ValueNotifier<String?> localSupplierNotifier =
            ValueNotifier<String?>(null);
        addTearDown(localSupplierNotifier.dispose);

        localTimelineStore.add(
          AppMessage(
            id: 'msg-merge-eq',
            timestamp: DateTime(2026, 4, 25, 9, 0, 0),
            userId: 'user-1',
            content: 'no-op merge',
            type: AppMessageType.chat,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: localSupervisor,
              timelineStore: localTimelineStore,
              supplierUserIdNotifier: localSupplierNotifier,
              userAttributeStore: localStore,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // In-memory changes that happen to match the disk values exactly.
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-1', '同じコテハン');
        screen.callbacks.onUserColorChanged!('user-1', 0xFFE53935);
        await tester.pump();

        // The first onNicknameChanged / onUserColorChanged calls happen
        // before broadcaster resolution, so _onUserColorChanged /
        // _onNicknameChanged must not call setColor / setNickname yet.
        expect(localStore.setColorCalls, isEmpty);
        expect(localStore.setNicknameCalls, isEmpty);

        // Resolve broadcaster: merge runs and _flushPendingAttributes
        // should detect that disk already has the same values, and skip
        // the writes.
        localSupplierNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        expect(
          localStore.setColorCalls,
          isEmpty,
          reason: 'disk と一致する in-memory 値は再書き込みされてはいけない',
        );
        expect(
          localStore.setNicknameCalls,
          isEmpty,
          reason: 'disk と一致する in-memory 値は再書き込みされてはいけない',
        );
      },
    );

    testWidgets(
      'loadAttributes merge: only nickname is flushed when color matches '
      'disk and nickname is in-memory only',
      (WidgetTester tester) async {
        // Disk already has the same color as the user "set" in-memory,
        // but the nickname is in-memory only (not on disk yet).
        // _flushPendingAttributes must skip the redundant color write
        // and only flush the nickname.
        final _FakeUserAttributeStore localStore = _FakeUserAttributeStore(
          colorsByBroadcaster: <String, Map<String, int>>{
            'broadcaster-1': <String, int>{'user-1': 0xFFE53935},
          },
          // No nickname on disk for user-1.
        );
        final ConnectionSupervisor localSupervisor = ConnectionSupervisor();
        final TimelineStore localTimelineStore = TimelineStore();
        final ValueNotifier<String?> localSupplierNotifier =
            ValueNotifier<String?>(null);
        addTearDown(localSupplierNotifier.dispose);

        localTimelineStore.add(
          AppMessage(
            id: 'msg-merge-partial-c',
            timestamp: DateTime(2026, 4, 25, 9, 0, 0),
            userId: 'user-1',
            content: 'partial merge: nickname only',
            type: AppMessageType.chat,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: localSupervisor,
              timelineStore: localTimelineStore,
              supplierUserIdNotifier: localSupplierNotifier,
              userAttributeStore: localStore,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        // Color matches disk; nickname is brand new in-memory only.
        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onUserColorChanged!('user-1', 0xFFE53935);
        screen.callbacks.onNicknameChanged!('user-1', '新しいコテハン');
        await tester.pump();

        expect(localStore.setColorCalls, isEmpty);
        expect(localStore.setNicknameCalls, isEmpty);

        localSupplierNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        expect(
          localStore.setColorCalls,
          isEmpty,
          reason: 'disk と一致する color は再書き込みされてはいけない',
        );
        expect(
          localStore.setNicknameCalls,
          hasLength(1),
          reason: 'in-memory のみの nickname は flush されなければならない',
        );
        expect(
          localStore.setNicknameCalls.single.broadcasterId,
          'broadcaster-1',
        );
        expect(localStore.setNicknameCalls.single.userId, 'user-1');
        expect(localStore.setNicknameCalls.single.nickname, '新しいコテハン');
      },
    );

    testWidgets(
      'loadAttributes merge: only color is flushed when nickname matches '
      'disk and color is in-memory only',
      (WidgetTester tester) async {
        // Symmetric counterpart: disk has the nickname, in-memory adds
        // a fresh color.  Only the color should hit the store.
        final _FakeUserAttributeStore localStore = _FakeUserAttributeStore(
          // No color on disk for user-1.
          nicknamesByBroadcaster: <String, Map<String, String>>{
            'broadcaster-1': <String, String>{'user-1': '同じコテハン'},
          },
        );
        final ConnectionSupervisor localSupervisor = ConnectionSupervisor();
        final TimelineStore localTimelineStore = TimelineStore();
        final ValueNotifier<String?> localSupplierNotifier =
            ValueNotifier<String?>(null);
        addTearDown(localSupplierNotifier.dispose);

        localTimelineStore.add(
          AppMessage(
            id: 'msg-merge-partial-n',
            timestamp: DateTime(2026, 4, 25, 9, 0, 0),
            userId: 'user-1',
            content: 'partial merge: color only',
            type: AppMessageType.chat,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: localSupervisor,
              timelineStore: localTimelineStore,
              supplierUserIdNotifier: localSupplierNotifier,
              userAttributeStore: localStore,
            ),
          ),
        );
        await tester.pump();

        await tester.enterText(inputField(), 'lv345678901');
        await tester.pump();
        await tester.tap(connectButton());
        await tester.pumpAndSettle();

        final CommentScreen screen = tester.widget<CommentScreen>(
          find.byType(CommentScreen),
        );
        screen.callbacks.onNicknameChanged!('user-1', '同じコテハン');
        screen.callbacks.onUserColorChanged!('user-1', 0xFF1E88E5);
        await tester.pump();

        expect(localStore.setColorCalls, isEmpty);
        expect(localStore.setNicknameCalls, isEmpty);

        localSupplierNotifier.value = 'broadcaster-1';
        await tester.pumpAndSettle();

        expect(
          localStore.setNicknameCalls,
          isEmpty,
          reason: 'disk と一致する nickname は再書き込みされてはいけない',
        );
        expect(
          localStore.setColorCalls,
          hasLength(1),
          reason: 'in-memory のみの color は flush されなければならない',
        );
        expect(localStore.setColorCalls.single.broadcasterId, 'broadcaster-1');
        expect(localStore.setColorCalls.single.userId, 'user-1');
        expect(localStore.setColorCalls.single.colorValue, 0xFF1E88E5);
      },
    );
  });

  group('favorite user section', () {
    testWidgets('tapping favorite user tile starts connection', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final _FakeFavoriteUserLiveChecker checker = _FakeFavoriteUserLiveChecker(
        resultMap: <String, FollowProgram>{
          '12345': FollowProgram(
            programId: 'lv777888999',
            title: 'テスト放送',
            providerName: 'テストユーザー',
            status: ProgramStatus.onAir,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            initialSettings: AppSettings.defaults.copyWith(
              favoriteUserIds: '12345',
            ),
            favoriteUserLiveChecker: checker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('お気に入りユーザーの放送'), findsOneWidget);
      expect(find.text('テスト放送'), findsOneWidget);

      await tester.tap(find.text('テスト放送'));
      await tester.pumpAndSettle();

      expect(find.byType(CommentScreen), findsOneWidget);
      expect(checker.lastRequestedUserIds, <String>{'12345'});
    });

    testWidgets('tapping favorite tile pre-binds supplierUserIdNotifier to '
        'FollowProgram.providerUserId (Issue #681 Phase 1)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final ValueNotifier<String?> supplierUserIdNotifier =
          ValueNotifier<String?>(null);
      addTearDown(supplierUserIdNotifier.dispose);

      final _FakeFavoriteUserLiveChecker checker = _FakeFavoriteUserLiveChecker(
        resultMap: <String, FollowProgram>{
          '97472220': FollowProgram(
            programId: 'lv350353828',
            title: 'ドラクエ6(DS)',
            providerName: '朝方ネル',
            providerUserId: '97472220',
            status: ProgramStatus.onAir,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            initialSettings: AppSettings.defaults.copyWith(
              favoriteUserIds: '97472220',
            ),
            favoriteUserLiveChecker: checker,
            supplierUserIdNotifier: supplierUserIdNotifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(supplierUserIdNotifier.value, isNull);

      await tester.tap(find.text('ドラクエ6(DS)'));
      await tester.pumpAndSettle();

      expect(supplierUserIdNotifier.value, '97472220');
    });

    testWidgets('tapping favorite tile with null providerUserId leaves '
        'supplierUserIdNotifier unchanged (lv fallback path)', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final ValueNotifier<String?> supplierUserIdNotifier =
          ValueNotifier<String?>(null);
      addTearDown(supplierUserIdNotifier.dispose);

      final _FakeFavoriteUserLiveChecker checker = _FakeFavoriteUserLiveChecker(
        resultMap: <String, FollowProgram>{
          'co0': FollowProgram(
            programId: 'lv350353828',
            title: 'コミュID経由の放送',
            providerName: '不明',
            // providerUserId intentionally omitted — simulates the
            // non-numeric map-key defensive path.
            status: ProgramStatus.onAir,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            initialSettings: AppSettings.defaults.copyWith(
              favoriteUserIds: 'co0',
            ),
            favoriteUserLiveChecker: checker,
            supplierUserIdNotifier: supplierUserIdNotifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(supplierUserIdNotifier.value, isNull);

      await tester.tap(find.text('コミュID経由の放送'));
      await tester.pumpAndSettle();

      // No pre-bind: the notifier stays null because providerUserId was
      // null. Subsequent programinfo resolution (not mocked here) is
      // the only path that can populate this notifier in the lv fallback
      // case.
      expect(supplierUserIdNotifier.value, isNull);
    });

    testWidgets('throttles favorite-user polling to background cadence while '
        'CommentScreen is on top', (WidgetTester tester) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final _FakeFavoriteUserLiveChecker checker = _FakeFavoriteUserLiveChecker(
        resultMap: <String, FollowProgram>{
          '12345': FollowProgram(
            programId: 'lv777888999',
            title: 'テスト放送',
            providerName: 'テストユーザー',
            status: ProgramStatus.onAir,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            initialSettings: AppSettings.defaults.copyWith(
              favoriteUserIds: '12345',
            ),
            favoriteUserLiveChecker: checker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial fetch from initState.
      expect(checker.checkCallCount, 1);

      // While the connection list is on top, the foreground 15-second
      // cadence is in effect: advancing 16 seconds should fire one tick.
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        checker.checkCallCount,
        2,
        reason: 'foreground cadence should fire within 16 seconds',
      );

      // Navigate to the comment screen by tapping the favorite tile.
      await tester.tap(find.text('テスト放送'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentScreen), findsOneWidget);

      final int countBeforeThrottle = checker.checkCallCount;

      // Advance well past the 15-second foreground interval but short
      // of the 120-second throttled interval. No additional fetches
      // should occur while the comment screen is the visible surface.
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(
        checker.checkCallCount,
        countBeforeThrottle,
        reason:
            'polling must be throttled while CommentScreen is on top — '
            'no foreground-cadence ticks should fire',
      );

      // Boundary check: advancing past the 120-second background
      // interval (60s already + 65s more = 125s total) MUST fire a
      // single throttled tick — guards against accidentally raising
      // the interval to a value that would never fire.
      await tester.pump(const Duration(seconds: 65));
      await tester.pumpAndSettle();
      expect(
        checker.checkCallCount,
        countBeforeThrottle + 1,
        reason:
            'one throttled-cadence tick should fire after the '
            '120-second interval elapses while CommentScreen is on top',
      );

      // Pop back to the connection list.
      Navigator.of(tester.element(find.byType(CommentScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(SelectScreen), findsOneWidget);

      // Returning to the connection list triggers an immediate refresh
      // so any state change during the throttled window is reflected
      // right away.
      expect(
        checker.checkCallCount,
        greaterThan(countBeforeThrottle),
        reason:
            'an immediate fetch must run after returning from '
            'CommentScreen',
      );
    });

    testWidgets(
      'app lifecycle resume while CommentScreen is on top does NOT trigger '
      'an immediate favorite refresh',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = ConnectionSupervisor();
        final _FakeFavoriteUserLiveChecker checker =
            _FakeFavoriteUserLiveChecker(
              resultMap: <String, FollowProgram>{
                '12345': FollowProgram(
                  programId: 'lv777888999',
                  title: 'テスト放送',
                  providerName: 'テストユーザー',
                  status: ProgramStatus.onAir,
                ),
              },
            );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: supervisor,
              initialSettings: AppSettings.defaults.copyWith(
                favoriteUserIds: '12345',
              ),
              favoriteUserLiveChecker: checker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('テスト放送'));
        await tester.pumpAndSettle();
        expect(find.byType(CommentScreen), findsOneWidget);

        final int countOnComment = checker.checkCallCount;

        // Simulate the app being backgrounded while the user is on the
        // comment screen, and then coming back to foreground. Without the
        // _isCommentScreenActive guard, the resume path would fire an
        // immediate fetch even though the favorite list isn't visible.
        // Flutter requires lifecycle transitions to follow the documented
        // graph: resumed → inactive → hidden → paused → hidden → inactive
        // → resumed. Stepping through each intermediate is necessary even
        // though our handler only reacts at the resumed transition.
        final TestWidgetsFlutterBinding binding =
            TestWidgetsFlutterBinding.ensureInitialized();
        for (final AppLifecycleState state in <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(
          checker.checkCallCount,
          countOnComment,
          reason:
              'foreground resume must NOT trigger an immediate fetch '
              'while CommentScreen is on top — the favorite list is '
              'hidden so the request would be wasted traffic',
        );

        // The throttled 120s cadence must still hold after the resume —
        // advancing 60s must not fire a tick.
        await tester.pump(const Duration(seconds: 60));
        await tester.pumpAndSettle();
        expect(
          checker.checkCallCount,
          countOnComment,
          reason:
              'background cadence (120s) must remain in effect after '
              'lifecycle resume while CommentScreen is on top',
        );

        addTearDown(() {
          binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        });
      },
    );

    testWidgets(
      'pull-to-refresh invalidates the favorite cache so the user sees '
      'fresh data rather than a value cached from a throttled tick',
      (WidgetTester tester) async {
        final ConnectionSupervisor supervisor = ConnectionSupervisor();
        final _FakeFavoriteUserLiveChecker checker =
            _FakeFavoriteUserLiveChecker(
              resultMap: <String, FollowProgram>{
                '12345': FollowProgram(
                  programId: 'lv777888999',
                  title: 'テスト放送',
                  providerName: 'テストユーザー',
                  status: ProgramStatus.onAir,
                ),
              },
            );

        await tester.pumpWidget(
          MaterialApp(
            home: SelectScreen(
              connectionSupervisor: supervisor,
              initialSettings: AppSettings.defaults.copyWith(
                favoriteUserIds: '12345',
              ),
              favoriteUserLiveChecker: checker,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(checker.invalidateCacheCallCount, 0);

        // Trigger pull-to-refresh by invoking the RefreshIndicator's
        // onRefresh callback directly — a real fling gesture would be
        // brittle in widget tests.
        final RefreshIndicator refreshIndicator = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator).first);
        await refreshIndicator.onRefresh();
        await tester.pumpAndSettle();

        expect(
          checker.invalidateCacheCallCount,
          1,
          reason:
              'pull-to-refresh must bypass the favorite TTL cache so '
              'the user sees the up-to-date result rather than a value '
              'cached from a recent throttled tick',
        );
      },
    );

    testWidgets('with zero favorites the polling timer is not scheduled', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final _FakeFavoriteUserLiveChecker checker = _FakeFavoriteUserLiveChecker(
        resultMap: const <String, FollowProgram>{},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SelectScreen(
            connectionSupervisor: supervisor,
            // Default settings: empty favoriteUserIds.
            favoriteUserLiveChecker: checker,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No favorites means no polling — checkBroadcastStatus must not
      // be invoked even after a long time passes. This is mainly a
      // CPU/timer hygiene optimisation; the network was already
      // gated by the favorites set being empty.
      expect(checker.checkCallCount, 0);

      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(
        checker.checkCallCount,
        0,
        reason: 'no favorites → no foreground-cadence ticks should fire',
      );

      await tester.pump(const Duration(seconds: 200));
      await tester.pumpAndSettle();
      expect(
        checker.checkCallCount,
        0,
        reason:
            'no favorites → no background-cadence ticks should fire '
            'either',
      );
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

      final _FakeMyProgramRepository myRepository = _FakeMyProgramRepository(
        myProgram,
      );
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

    testWidgets('shows own broadcast section when user is broadcasting', (
      WidgetTester tester,
    ) async {
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

    testWidgets('shows own broadcast thumbnail when providerIconUrl exists', (
      WidgetTester tester,
    ) async {
      await pumpWithMyProgram(
        tester,
        myProgram: FollowProgram(
          programId: 'lv101',
          title: 'サムネイル付き放送',
          providerName: '自分',
          providerIconUrl: 'https://example.com/my-broadcast-icon.jpg',
          isOwnBroadcast: true,
        ),
      );

      await tester.pump(const Duration(seconds: 4));

      final Finder iconFinder = find.byWidgetPredicate((Widget widget) {
        if (widget is! Image) {
          return false;
        }
        final ImageProvider imageProvider = widget.image;
        if (imageProvider is NetworkImage) {
          return imageProvider.url ==
              'https://example.com/my-broadcast-icon.jpg';
        }
        if (imageProvider is ResizeImage) {
          final ImageProvider<Object> base = imageProvider.imageProvider;
          return base is NetworkImage &&
              base.url == 'https://example.com/my-broadcast-icon.jpg';
        }
        return false;
      });

      expect(iconFinder, findsOneWidget);
    });

    testWidgets('hides own broadcast section when not broadcasting', (
      WidgetTester tester,
    ) async {
      await pumpWithMyProgram(tester);

      // Flush retry timers.
      await tester.pump(const Duration(seconds: 4));

      expect(find.text('あなたの放送'), findsNothing);
    });

    testWidgets('own broadcast section appears above follow list', (
      WidgetTester tester,
    ) async {
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

    testWidgets('tapping own broadcast tile starts connection', (
      WidgetTester tester,
    ) async {
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

    testWidgets('retries fetching own program on initial null response', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository = _FakeMyProgramRepository(
        FollowProgram(
          programId: 'lv999',
          title: 'リトライ後の放送',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
      );
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

    testWidgets('own program still displays when follow program fetch throws', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository = _FakeMyProgramRepository(
        FollowProgram(
          programId: 'lv100',
          title: '自分の放送',
          providerName: '自分',
          isOwnBroadcast: true,
        ),
      );

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

    testWidgets('follow programs still display when own program fetch throws', (
      WidgetTester tester,
    ) async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor();
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('test_session');

      final _FakeMyProgramRepository myRepository = _FakeMyProgramRepository(
        null,
      );
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
  Future<FollowProgram?> fetchOwnProgram({required String userSession}) async {
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

class _FakeFavoriteUserLiveChecker extends FavoriteUserLiveChecker {
  _FakeFavoriteUserLiveChecker({required this.resultMap});

  final Map<String, FollowProgram> resultMap;
  Set<String> lastRequestedUserIds = const <String>{};
  int checkCallCount = 0;
  int invalidateCacheCallCount = 0;

  @override
  Future<Map<String, FollowProgram>> checkBroadcastStatus(
    Set<String> userIds,
  ) async {
    checkCallCount += 1;
    lastRequestedUserIds = Set<String>.from(userIds);
    final Map<String, FollowProgram> filtered = <String, FollowProgram>{};
    for (final String userId in userIds) {
      final FollowProgram? program = resultMap[userId];
      if (program != null) {
        filtered[userId] = program;
      }
    }
    return filtered;
  }

  @override
  void invalidateCache() {
    invalidateCacheCallCount += 1;
    super.invalidateCache();
  }

  @override
  void dispose() {}
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

/// Fake [UserAttributeStore] used by widget tests.
///
/// **Semantic differences from the production stores
/// ([FileUserAttributeStore] / [SharedPreferencesUserAttributeStore]):**
///
/// - Production stores hold colors and nicknames in a single raw JSON
///   payload per broadcaster, so an "empty" broadcaster always yields empty
///   `colors` AND empty `nicknames` together. This fake stores them in two
///   separate maps, so it can represent a state where only one of them has
///   data for a broadcaster (a configuration that the production stores
///   cannot reach by normal operations).
/// - This fake does not model `_lastUsedAt` touch behaviour. Cleanup-by-age
///   verification belongs in the production-store unit tests under
///   `test/data/user/`.
///
/// Both differences are intentional and acceptable for widget tests that
/// only depend on the in-memory contract of [UserAttributeStore].
/// `setColor` / `setNickname` / `removeColor` / `removeNickname` call counts
/// are tracked so tests can assert on the exact write traffic produced by
/// the screen (e.g. the merge / flush path of `_loadUserAttributes`).
class _FakeUserAttributeStore implements UserAttributeStore {
  _FakeUserAttributeStore({
    Map<String, Map<String, int>> colorsByBroadcaster =
        const <String, Map<String, int>>{},
    Map<String, Map<String, String>> nicknamesByBroadcaster =
        const <String, Map<String, String>>{},
  }) : _colorsByBroadcaster = colorsByBroadcaster.map(
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

  /// Internal mutable buffers; tests must read via the public unmodifiable
  /// getters below so they cannot accidentally mutate recorded history.
  final List<({String broadcasterId, String userId, int colorValue})>
  _setColorCalls = <({String broadcasterId, String userId, int colorValue})>[];
  final List<({String broadcasterId, String userId, String nickname})>
  _setNicknameCalls =
      <({String broadcasterId, String userId, String nickname})>[];
  final List<({String broadcasterId, String userId})> _removeColorCalls =
      <({String broadcasterId, String userId})>[];
  final List<({String broadcasterId, String userId})> _removeNicknameCalls =
      <({String broadcasterId, String userId})>[];

  /// Read-only views over every mutating call, in invocation order.
  ///
  /// Exposed as unmodifiable lists so tests can inspect `length`, `single`,
  /// element fields, etc. without being able to add or remove entries.
  List<({String broadcasterId, String userId, int colorValue})>
  get setColorCalls =>
      List<
        ({String broadcasterId, String userId, int colorValue})
      >.unmodifiable(_setColorCalls);
  List<({String broadcasterId, String userId, String nickname})>
  get setNicknameCalls =>
      List<
        ({String broadcasterId, String userId, String nickname})
      >.unmodifiable(_setNicknameCalls);
  List<({String broadcasterId, String userId})> get removeColorCalls =>
      List<({String broadcasterId, String userId})>.unmodifiable(
        _removeColorCalls,
      );
  List<({String broadcasterId, String userId})> get removeNicknameCalls =>
      List<({String broadcasterId, String userId})>.unmodifiable(
        _removeNicknameCalls,
      );

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
  Future<UserAttributesSnapshot> loadAttributes(String broadcasterId) async {
    return (
      colors: Map<String, int>.from(
        _colorsByBroadcaster[broadcasterId] ?? const <String, int>{},
      ),
      nicknames: Map<String, String>.from(
        _nicknamesByBroadcaster[broadcasterId] ?? const <String, String>{},
      ),
    );
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    _setColorCalls.add((
      broadcasterId: broadcasterId,
      userId: userId,
      colorValue: colorValue,
    ));
    final Map<String, int> colors = _colorsByBroadcaster.putIfAbsent(
      broadcasterId,
      () => <String, int>{},
    );
    colors[userId] = colorValue;
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    _removeColorCalls.add((broadcasterId: broadcasterId, userId: userId));
    _colorsByBroadcaster[broadcasterId]?.remove(userId);
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {
    _setNicknameCalls.add((
      broadcasterId: broadcasterId,
      userId: userId,
      nickname: nickname,
    ));
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
    _removeNicknameCalls.add((broadcasterId: broadcasterId, userId: userId));
    _nicknamesByBroadcaster[broadcasterId]?.remove(userId);
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    return 0;
  }

  @override
  Future<void> flushPendingWrites() async {}
}

class _FlushTrackingUserAttributeStore extends _FakeUserAttributeStore {
  int flushPendingWritesCallCount = 0;

  @override
  Future<void> flushPendingWrites() async {
    flushPendingWritesCallCount++;
  }
}

void _registerIssue697MuteTests() {
  // ---------------------------------------------------------------------------
  // Issue #697: tapping the AppBar mute toggle while engineType=Android TTS
  // must actually mute speech. The previous implementation only adjusted the
  // VOICEVOX volume and left Android TTS playing at full volume even though
  // the icon flipped to volume_off.
  //
  // The mute decision logic now lives in `computeSpeechMuteToggle`, a pure
  // function we can drive directly from tests without standing up the full
  // SelectScreen + CommentScreen + MethodChannel stack (which previously
  // gated access to the toggle behind a non-tappable icon when the speech
  // engine was not initialised).
  // ---------------------------------------------------------------------------
  group('computeSpeechMuteToggle (Issue #697)', () {
    test(
      'mute path zeroes BOTH engine volumes and captures both pre-mute slots',
      () {
        final SpeechMuteToggleResult result = computeSpeechMuteToggle(
          current: AppSettings.defaults.copyWith(
            voicevoxVolume: 1.5,
            androidTtsVolume: 0.8,
          ),
          currentVoicevoxPreMute: null,
          currentAndroidTtsPreMute: null,
        );

        expect(
          result.updated.voicevoxVolume,
          0.0,
          reason:
              'Mute must zero VOICEVOX volume so the existing VOICEVOX-mute '
              'path stays intact.',
        );
        expect(
          result.updated.androidTtsVolume,
          0.0,
          reason:
              'Mute must zero Android TTS volume so the native TTS speak call '
              'receives KEY_PARAM_VOLUME=0 — this is the regression Issue #697 '
              'targets.',
        );
        expect(result.voicevoxPreMute, 1.5);
        expect(
          result.androidTtsPreMute,
          0.8,
          reason:
              'Both pre-mute slots are persisted so engine switching while '
              'muted does not lose either engine\'s saved volume.',
        );
      },
    );

    test(
      'mute path with already-zero current volumes falls back to 1.0 on the pre-mute slot',
      () {
        // Defensive parity with the legacy VOICEVOX behaviour: storing 0 in
        // the pre-mute slot would leave the user silent forever after unmute,
        // so 1.0 is used instead.
        final SpeechMuteToggleResult result = computeSpeechMuteToggle(
          current: AppSettings.defaults.copyWith(
            voicevoxVolume: 0.0,
            androidTtsVolume: 0.0,
          ),
          currentVoicevoxPreMute: null,
          currentAndroidTtsPreMute: null,
        );

        expect(result.updated.voicevoxVolume, 0.0);
        expect(result.updated.androidTtsVolume, 0.0);
        expect(result.voicevoxPreMute, 1.0);
        expect(result.androidTtsPreMute, 1.0);
      },
    );

    test(
      'unmute path restores both engine volumes from the pre-mute slots and clears them',
      () {
        final SpeechMuteToggleResult result = computeSpeechMuteToggle(
          current: AppSettings.defaults.copyWith(
            voicevoxVolume: 0.0,
            androidTtsVolume: 0.0,
          ),
          currentVoicevoxPreMute: 1.5,
          currentAndroidTtsPreMute: 0.8,
        );

        expect(result.updated.voicevoxVolume, 1.5);
        expect(result.updated.androidTtsVolume, 0.8);
        expect(result.voicevoxPreMute, isNull);
        expect(result.androidTtsPreMute, isNull);
      },
    );

    test(
      'unmute path falls back to 1.0 when slot is null AND current volume is 0 (post-merge round-2)',
      () {
        // Post-merge round-2 review: a partial SharedPreferences write
        // failure can persist the muted save (current.*Volume = 0.0)
        // while losing the pre-mute slot for one engine. Without the
        // `> 0` guard, unmute would restore that engine's volume to 0,
        // leaving the user silent forever even though they tapped
        // unmute. This test pins the recovery fallback to 1.0.
        final SpeechMuteToggleResult result = computeSpeechMuteToggle(
          current: AppSettings.defaults.copyWith(
            voicevoxVolume: 0.0,
            androidTtsVolume: 0.0,
          ),
          currentVoicevoxPreMute: 1.5,
          currentAndroidTtsPreMute: null,
        );

        expect(result.updated.voicevoxVolume, 1.5);
        expect(
          result.updated.androidTtsVolume,
          1.0,
          reason:
              'When the pre-mute slot is null AND the current volume is '
              '0 (e.g. after a partial-write + restart), unmute must '
              'fall back to 1.0 instead of leaving the user silent. '
              'Mirrors the mute path defence (Issue #697 post-merge '
              'round-2).',
        );
        expect(result.voicevoxPreMute, isNull);
        expect(result.androidTtsPreMute, isNull);
      },
    );

    test(
      'unmute path falls back to current volume when only one pre-mute slot is set (legacy upgrade)',
      () {
        // Forward-compat with users upgrading from a build that only stored
        // the VOICEVOX pre-mute slot: the missing Android TTS slot must not
        // overwrite a good current volume with 0.
        final SpeechMuteToggleResult result = computeSpeechMuteToggle(
          current: AppSettings.defaults.copyWith(
            voicevoxVolume: 0.0,
            androidTtsVolume: 0.4,
          ),
          currentVoicevoxPreMute: 1.2,
          currentAndroidTtsPreMute: null,
        );

        expect(result.updated.voicevoxVolume, 1.2);
        expect(
          result.updated.androidTtsVolume,
          0.4,
          reason:
              'Missing pre-mute slot must preserve the current value, not '
              'overwrite it with 0.',
        );
        expect(result.voicevoxPreMute, isNull);
        expect(result.androidTtsPreMute, isNull);
      },
    );

    test('unmute is triggered when EITHER pre-mute slot is set', () {
      // Either slot being non-null means "muted". The toggle therefore
      // takes the unmute path whenever at least one slot is populated.
      final SpeechMuteToggleResult onlyAndroid = computeSpeechMuteToggle(
        current: AppSettings.defaults.copyWith(
          voicevoxVolume: 0.0,
          androidTtsVolume: 0.0,
        ),
        currentVoicevoxPreMute: null,
        currentAndroidTtsPreMute: 0.8,
      );
      // Took the unmute path → both slots cleared.
      expect(onlyAndroid.voicevoxPreMute, isNull);
      expect(onlyAndroid.androidTtsPreMute, isNull);
      expect(onlyAndroid.updated.androidTtsVolume, 0.8);

      // Symmetric case: only the VOICEVOX slot set must also take the
      // unmute path (Issue #697 cycle-2 review #2).
      final SpeechMuteToggleResult onlyVoicevox = computeSpeechMuteToggle(
        current: AppSettings.defaults.copyWith(
          voicevoxVolume: 0.0,
          androidTtsVolume: 0.0,
        ),
        currentVoicevoxPreMute: 1.5,
        currentAndroidTtsPreMute: null,
      );
      expect(onlyVoicevox.voicevoxPreMute, isNull);
      expect(onlyVoicevox.androidTtsPreMute, isNull);
      expect(onlyVoicevox.updated.voicevoxVolume, 1.5);
    });
  });
}
