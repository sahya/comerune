import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/tts_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('TtsSettingsScreen', () {
    testWidgets('switches engine-specific section by radio selection', (
      WidgetTester tester,
    ) async {
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _scrollToKey(tester, const Key('bouyomi-section'));
      expect(
        find.byKey(const Key('bouyomi-section'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('voicevox-section'), skipOffstage: false),
        findsNothing,
      );

      await _scrollToKey(tester, const Key('engine-voicevox-radio'));
      await tester.tap(
        find.byKey(const Key('engine-voicevox-radio'), skipOffstage: false),
      );
      await tester.pumpAndSettle();

      await _scrollToKey(tester, const Key('voicevox-section'));
      expect(
        find.byKey(const Key('voicevox-section'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('bouyomi-section'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets('shows validation error and does not save invalid queue limit',
        (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _enterTextByKey(tester, const Key('queue-limit-field'), 'abc');
      await _focusFieldByKey(tester, const Key('max-delay-field'));

      expect(find.text('数値を入力してください', skipOffstage: false), findsOneWidget);
      AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await _enterTextByKey(tester, const Key('queue-limit-field'), '0');
      await _focusFieldByKey(tester, const Key('max-delay-field'));

      expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false), findsOneWidget);
      loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await _enterTextByKey(tester, const Key('queue-limit-field'), '35');
      await _focusFieldByKey(tester, const Key('max-delay-field'));

      loaded = await settingsStore.load();
      expect(loaded.queueLimit, 35);
      expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false), findsNothing);
    });

    testWidgets('shows validation error and does not save invalid max delay', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _enterTextByKey(tester, const Key('max-delay-field'), 'abc');
      await _focusFieldByKey(tester, const Key('queue-limit-field'));

      AppSettings loaded = await settingsStore.load();
      expect(loaded.maxDelaySeconds, AppSettings.defaults.maxDelaySeconds);

      await _enterTextByKey(tester, const Key('max-delay-field'), '0');
      await _focusFieldByKey(tester, const Key('queue-limit-field'));

      loaded = await settingsStore.load();
      expect(loaded.maxDelaySeconds, AppSettings.defaults.maxDelaySeconds);
    });

    testWidgets('saves text fields when focus is lost', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _enterTextByKey(
        tester,
        const Key('bouyomi-host-field'),
        '192.168.0.10',
      );
      await _focusFieldByKey(tester, const Key('queue-limit-field'));

      await _enterTextByKey(tester, const Key('ng-words-field'), '^w+\$');
      await _focusFieldByKey(tester, const Key('max-delay-field'));

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.bouyomiHost, '192.168.0.10');
      expect(loaded.ngWords, '^w+\$');
    });

    testWidgets('auto-read toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoReadEnabled, isFalse);

      await _toggleSwitchByKey(tester, const Key('auto-read-switch'));

      loaded = await settingsStore.load();
      expect(loaded.autoReadEnabled, isTrue);
    });

    testWidgets('slash prefix skip toggle persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be ON
      AppSettings loaded = await settingsStore.load();
      expect(loaded.slashPrefixSkipEnabled, isTrue);

      await _toggleSwitchByKey(tester, const Key('slash-prefix-skip-switch'));

      loaded = await settingsStore.load();
      expect(loaded.slashPrefixSkipEnabled, isFalse);
    });

    testWidgets('star prefix hiding toggle persists value (default OFF)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be OFF
      AppSettings loaded = await settingsStore.load();
      expect(loaded.starPrefixHidingEnabled, isFalse);

      await _toggleSwitchByKey(tester, const Key('star-prefix-hiding-switch'));

      loaded = await settingsStore.load();
      expect(loaded.starPrefixHidingEnabled, isTrue);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: TtsSettingsScreen(
      settingsStore: settingsStore,
    ),
  );
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  final Finder scrollable = find
      .descendant(
        of: find.byKey(const Key('tts-settings-list')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    try {
      await tester.scrollUntilVisible(
        target,
        -120,
        scrollable: scrollable,
      );
    } on StateError {
      await tester.scrollUntilVisible(
        target,
        120,
        scrollable: scrollable,
      );
    }
  }
  await tester.pumpAndSettle();
}

Future<void> _focusFieldByKey(WidgetTester tester, Key key) async {
  await _scrollToKey(tester, key);
  await tester.tap(find.byKey(key), warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _enterTextByKey(WidgetTester tester, Key key, String text) async {
  await _focusFieldByKey(tester, key);
  await tester.enterText(find.byKey(key), text);
  await tester.pumpAndSettle();
}

Future<void> _toggleSwitchByKey(WidgetTester tester, Key key) async {
  await _scrollToKey(tester, key);
  final SwitchListTile tile =
      tester.widget(find.byKey(key, skipOffstage: false));
  // TODO(issue-12-followup): off-screen 要素のヒットテスト制約を解消したら、
  // 直接 callback 呼び出しではなく tester.tap ベースに統一する。
  tile.onChanged!.call(!tile.value);
  await tester.pumpAndSettle();
}
