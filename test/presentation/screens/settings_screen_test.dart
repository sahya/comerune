import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/auth/user_session_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/in_memory_user_session_store.dart';
import '../../helpers/settings_test_helpers.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('shows login button when not logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-button')), findsOneWidget);
      expect(find.byKey(const Key('logout-button')), findsNothing);
      expect(find.text('コメント取得にはログインが必要です'), findsOneWidget);
    });

    testWidgets('shows logout button when logged in', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final InMemoryUserSessionStore userSessionStore =
          InMemoryUserSessionStore();
      await userSessionStore.save('user_session_abc123');

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logout-button')), findsOneWidget);
      expect(find.byKey(const Key('login-button')), findsNothing);
      expect(find.text('ログイン済み'), findsOneWidget);
    });

    testWidgets('theme dropdown persists selected value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be light
      AppSettings loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.light);

      // Open the dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // Tap the dark option in the dropdown overlay
      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.themeMode, AppThemeMode.dark);
    });

    testWidgets('theme dropdown updates themeModeNotifier immediately', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final ValueNotifier<AppThemeMode> themeNotifier =
          ValueNotifier<AppThemeMode>(AppThemeMode.light);

      await tester.pumpWidget(
        _buildScreen(settingsStore, themeModeNotifier: themeNotifier),
      );
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.light);

      // Open dropdown and select dark
      await tester.tap(
        find.byKey(const Key('theme-mode-dropdown')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク').last);
      await tester.pumpAndSettle();

      expect(themeNotifier.value, AppThemeMode.dark);

      themeNotifier.dispose();
    });

    testWidgets('debug mode toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('debug-mode-switch')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      toggleSwitchByKeySync(tester, const Key('debug-mode-switch'));
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.debugMode, isTrue);
    });

    testWidgets('shows navigation tiles for sub-screens', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Scroll down so all navigation tiles are visible.
      await tester.scrollUntilVisible(
        find.byKey(const Key('user-management-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tts-settings-tile')), findsOneWidget);
      expect(
        find.byKey(const Key('comment-display-settings-tile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('user-management-settings-tile')),
        findsOneWidget,
      );
    });

    testWidgets('tts tile shows auto-read status', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('tts-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default autoRead is OFF
      expect(find.text('自動読み上げ: OFF'), findsOneWidget);
    });

    testWidgets('comment display tile shows font size', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('comment-display-settings-tile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default font size is 14px
      expect(find.text('フォントサイズ: 14px'), findsOneWidget);
    });
  });
}

Widget _buildScreen(
  SettingsStore settingsStore, {
  UserSessionStore? userSessionStore,
  ValueNotifier<AppThemeMode>? themeModeNotifier,
}) {
  return MaterialApp(
    home: SettingsScreen(
      settingsStore: settingsStore,
      userSessionStore: userSessionStore,
      themeModeNotifier: themeModeNotifier,
    ),
  );
}
