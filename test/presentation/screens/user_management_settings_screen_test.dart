import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/presentation/screens/user_management_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('UserManagementSettingsScreen', () {
    testWidgets('shows favorite user list tile', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('favorite-user-list-tile')), findsOneWidget);
    });

    // Issue #727 PR2 (UX flatten): the per-broadcaster NG management entry
    // moved to a top-level Settings tile (`broadcaster-ng-filter-tile`), so
    // this screen no longer renders an NG-related tile. The corresponding
    // assertions live in `settings_screen_test.dart` now.

    testWidgets(
      'dispose does not throw when broadcasterIdNotifier is provided',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final ValueNotifier<String?> notifier = ValueNotifier<String?>(
          'broadcaster-1',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: UserManagementSettingsScreen(
              settingsStore: settingsStore,
              broadcasterIdNotifier: notifier,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(const MaterialApp(home: Scaffold()));
        await tester.pumpAndSettle();

        notifier.value = 'broadcaster-2';
        await tester.pump();

        notifier.dispose();
      },
    );

    testWidgets('dispose does not throw when broadcasterIdNotifier is null', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(
        MaterialApp(
          home: UserManagementSettingsScreen(settingsStore: settingsStore),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: UserManagementSettingsScreen(settingsStore: settingsStore),
  );
}
