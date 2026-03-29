import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/user/user_attribute_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/user_management_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

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

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(
            settingsStore: settingsStore,
            userAttributeStore: _FakeUserAttributeStore(),
            broadcasterId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ListTile nicknameTile = tester.widget(
        find.byKey(const Key('nickname-list-tile')),
      );
      expect(nicknameTile.enabled, isFalse);
      expect(find.text('放送に接続すると利用できます'), findsOneWidget);
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

      _toggleSwitchByKey(
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

void _toggleSwitchByKey(WidgetTester tester, Key key) {
  final SwitchListTile tile = tester.widget(find.byKey(key, skipOffstage: false));
  tile.onChanged!.call(!tile.value);
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
