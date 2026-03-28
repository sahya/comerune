import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/application/timeline/timeline_store.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/presentation/select/select_screen.dart';
import 'package:comerune/presentation/screens/comment_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
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
}
