import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/application/settings/settings_store.dart';
import '../../../lib/domain/models/app_settings.dart';
import '../../../lib/presentation/screens/settings_screen.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('switches engine-specific section by radio selection', (
      WidgetTester tester,
    ) async {
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bouyomi-section')), findsOneWidget);
      expect(find.byKey(const Key('voicevox-section')), findsNothing);

      await tester.tap(find.byKey(const Key('engine-voicevox-radio')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('voicevox-section')), findsOneWidget);
      expect(find.byKey(const Key('bouyomi-section')), findsNothing);
    });

    testWidgets('shows validation error and does not save invalid queue limit',
        (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('queue-limit-field')), 'abc');
      await tester.tap(find.byKey(const Key('max-delay-field')));
      await tester.pumpAndSettle();

      expect(find.text('数値を入力してください'), findsOneWidget);
      AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await tester.enterText(find.byKey(const Key('queue-limit-field')), '0');
      await tester.tap(find.byKey(const Key('max-delay-field')));
      await tester.pumpAndSettle();

      expect(find.text('1〜100 の範囲で入力してください'), findsOneWidget);
      loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await tester.enterText(find.byKey(const Key('queue-limit-field')), '35');
      await tester.tap(find.byKey(const Key('max-delay-field')));
      await tester.pumpAndSettle();

      loaded = await settingsStore.load();
      expect(loaded.queueLimit, 35);
      expect(find.text('1〜100 の範囲で入力してください'), findsNothing);
    });

    testWidgets('persists values and reloads on reopened screen', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('debug-mode-switch')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('ng-words-field')), '^8+\$');
      await tester.tap(find.byKey(const Key('auto-read-switch')));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final Finder debugSwitchFinder = find.descendant(
        of: find.byKey(const Key('debug-mode-switch')),
        matching: find.byType(Switch),
      );
      final Switch debugSwitch = tester.widget(debugSwitchFinder);
      expect(debugSwitch.value, isTrue);

      final TextFormField ngWordsField =
          tester.widget(find.byKey(const Key('ng-words-field')));
      expect(ngWordsField.controller?.text, '^8+\$');
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: SettingsScreen(settingsStore: settingsStore),
  );
}
