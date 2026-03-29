import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/tts_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

const Key _listKey = Key('tts-settings-list');

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

      await scrollToKeyInList(tester, _listKey, const Key('bouyomi-section'));
      expect(
        find.byKey(const Key('bouyomi-section'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('voicevox-section'), skipOffstage: false),
        findsNothing,
      );

      await scrollToKeyInList(
          tester, _listKey, const Key('engine-voicevox-radio'));
      await tester.tap(
        find.byKey(const Key('engine-voicevox-radio'), skipOffstage: false),
      );
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('voicevox-section'));
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

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), 'abc');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      expect(find.text('数値を入力してください', skipOffstage: false), findsOneWidget);
      AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), '0');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false), findsOneWidget);
      loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), '35');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

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

      await enterTextByKey(
          tester, _listKey, const Key('max-delay-field'), 'abc');
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      AppSettings loaded = await settingsStore.load();
      expect(loaded.maxDelaySeconds, AppSettings.defaults.maxDelaySeconds);

      await enterTextByKey(
          tester, _listKey, const Key('max-delay-field'), '0');
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

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

      await enterTextByKey(
        tester,
        _listKey,
        const Key('bouyomi-host-field'),
        '192.168.0.10',
      );
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      await enterTextByKey(
          tester, _listKey, const Key('ng-words-field'), '^w+\$');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.bouyomiHost, '192.168.0.10');
      expect(loaded.ngWords, '^w+\$');
    });

    testWidgets('persists values and reloads on reopened screen', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await toggleSwitchByKey(tester, _listKey, const Key('auto-read-switch'));
      await enterTextByKey(
          tester, _listKey, const Key('ng-words-field'), '^8+\$');
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      // Re-open the screen to verify values are reloaded from store
      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('ng-words-field'));
      final TextFormField ngWordsField = tester
          .widget(find.byKey(const Key('ng-words-field'), skipOffstage: false));
      expect(ngWordsField.controller?.text, '^8+\$');
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

      await toggleSwitchByKey(tester, _listKey, const Key('auto-read-switch'));

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

      await toggleSwitchByKey(
          tester, _listKey, const Key('slash-prefix-skip-switch'));

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

      await toggleSwitchByKey(
          tester, _listKey, const Key('star-prefix-hiding-switch'));

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
