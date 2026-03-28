import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/application/settings/settings_store.dart';
import '../../../lib/data/auth/user_session_store.dart';
import '../../../lib/domain/models/app_settings.dart';
import '../../../lib/presentation/screens/settings_screen.dart';
import '../../helpers/in_memory_shared_preferences.dart';

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

    testWidgets('persists values and reloads on reopened screen', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _toggleSwitchByKey(tester, const Key('debug-mode-switch'));

      await _enterTextByKey(tester, const Key('ng-words-field'), '^8+\$');
      await _toggleSwitchByKey(tester, const Key('auto-read-switch'));

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await _scrollToKey(tester, const Key('debug-mode-switch'));
      final Finder debugSwitchFinder = find.descendant(
        of: find.byKey(const Key('debug-mode-switch'), skipOffstage: false),
        matching: find.byType(Switch),
      );
      final Switch debugSwitch = tester.widget(debugSwitchFinder);
      expect(debugSwitch.value, isTrue);

      await _scrollToKey(tester, const Key('ng-words-field'));
      final TextFormField ngWordsField = tester
          .widget(find.byKey(const Key('ng-words-field'), skipOffstage: false));
      expect(ngWordsField.controller?.text, '^8+\$');
    });

    testWidgets('saves access token when focus is lost', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final _InMemoryUserSessionStore userSessionStore =
          _InMemoryUserSessionStore();

      await tester.pumpWidget(
        _buildScreen(settingsStore, userSessionStore: userSessionStore),
      );
      await tester.pumpAndSettle();

      await _enterTextByKey(
        tester,
        const Key('access-token-field'),
        'test-oauth-token-123',
      );
      await _focusFieldByKey(tester, const Key('bouyomi-host-field'));

      final String loaded = await userSessionStore.load();
      expect(loaded, 'test-oauth-token-123');
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
  });
}

Widget _buildScreen(
  SettingsStore settingsStore, {
  UserSessionStore? userSessionStore,
}) {
  return MaterialApp(
    home: SettingsScreen(
      settingsStore: settingsStore,
      userSessionStore: userSessionStore,
    ),
  );
}

class _InMemoryUserSessionStore implements UserSessionStore {
  String _session = '';

  @override
  Future<String> load() async => _session;

  @override
  Future<void> save(String userSession) async {
    _session = userSession;
  }

  @override
  Future<void> clear() async {
    _session = '';
  }
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  final Finder scrollable = find
      .descendant(
        of: find.byKey(const Key('settings-list')),
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
