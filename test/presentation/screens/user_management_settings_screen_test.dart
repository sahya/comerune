import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/user/user_attribute_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/user_management_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

void main() {
  group('UserManagementSettingsScreen', () {
    testWidgets('shows favorite user list tile', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('favorite-user-list-tile')),
        findsOneWidget,
      );
      expect(find.text('未登録'), findsOneWidget);
    });

    testWidgets('shows disabled nickname tile when broadcasterId is null', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ListTile nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isFalse);
      expect(find.text('放送に接続すると利用できます'), findsOneWidget);

      notifier.dispose();
    });

    testWidgets('shows enabled nickname tile when broadcasterId is non-null', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier =
          ValueNotifier<String?>('broadcaster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ListTile nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isTrue);
      expect(find.text('放送に接続すると利用できます'), findsNothing);

      notifier.dispose();
    });

    testWidgets(
        'nickname tile enables reactively when broadcasterId becomes non-null',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially disabled
      ListTile nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isFalse);

      // Simulate broadcaster ID resolved asynchronously
      notifier.value = 'broadcaster-1';
      await tester.pumpAndSettle();

      // Now enabled
      nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isTrue);
      expect(find.text('放送に接続すると利用できます'), findsNothing);

      notifier.dispose();
    });

    testWidgets(
        'nickname tile disables reactively when broadcasterId becomes null',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier =
          ValueNotifier<String?>('broadcaster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially enabled
      ListTile nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isTrue);

      // Simulate disconnect
      notifier.value = null;
      await tester.pumpAndSettle();

      // Now disabled
      nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isFalse);
      expect(find.text('放送に接続すると利用できます'), findsOneWidget);

      notifier.dispose();
    });

    testWidgets('nickname tile label is コテハン管理', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier = ValueNotifier<String?>(null);

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('コテハン管理'), findsOneWidget);
      // Ensure the old label is not present
      expect(find.text('コテハン一覧管理'), findsNothing);

      notifier.dispose();
    });

    testWidgets(
        'nickname tile is not shown when userAttributeStore is null',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            // userAttributeStore is null
            broadcasterIdNotifier: ValueNotifier<String?>('broadcaster-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nickname-list-tile')), findsNothing);
    });

    testWidgets(
        'dispose does not throw when broadcasterIdNotifier is provided',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<String?> notifier =
          ValueNotifier<String?>('broadcaster-1');

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterIdNotifier: notifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate away to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      // Changing the notifier after dispose should not throw
      notifier.value = 'broadcaster-2';
      await tester.pump();

      notifier.dispose();
    });

    testWidgets(
        'dispose does not throw when broadcasterIdNotifier is null',
        (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate away to trigger dispose – should not throw
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
    });

    testWidgets('auto-nickname registration toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default is true
      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoNicknameRegistration, isTrue);

      toggleSwitchByKeySync(
          tester, const Key('auto-nickname-registration-switch'));
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.autoNicknameRegistration, isFalse);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: UserManagementSettingsScreen(
      settingsStore: settingsStore,
    ),
  );
}

class _FakeUserAttributeStore implements UserAttributeStore {
  @override
  Future<Map<String, int>> loadColors(String broadcasterId) async =>
      <String, int>{};

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) async =>
      <String, String>{};

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {}

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {}

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {}

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) async {}

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async => 0;
}
