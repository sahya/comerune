import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/comment_display_settings_screen.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('CommentDisplaySettingsScreen', () {
    testWidgets('toggles showUserName and persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default is true
      AppSettings loaded = await settingsStore.load();
      expect(loaded.showUserName, isTrue);

      await _toggleSwitchByKey(tester, const Key('show-user-name-switch'));

      loaded = await settingsStore.load();
      expect(loaded.showUserName, isFalse);
    });

    testWidgets('disables resolveUserName switch when showUserName is off', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Turn off showUserName
      await _toggleSwitchByKey(tester, const Key('show-user-name-switch'));

      // resolveUserName switch should now be disabled
      final SwitchListTile resolveTile = tester.widget(
        find.byKey(const Key('resolve-user-name-switch'), skipOffstage: false),
      );
      expect(resolveTile.onChanged, isNull);
    });

    testWidgets('auto-save comment log toggle persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default is false
      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isFalse);

      await _toggleSwitchByKey(
          tester, const Key('auto-save-comment-log-switch'));

      loaded = await settingsStore.load();
      expect(loaded.autoSaveCommentLog, isTrue);
    });

    testWidgets('disables statistics child toggles when parent toggle is off', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Parent is off by default; child toggles should be disabled.
      await _scrollToKey(tester, const Key('statistics-viewer-comment-switch'));
      SwitchListTile viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNull);

      await _scrollToKey(tester, const Key('statistics-active-user-switch'));
      SwitchListTile activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNull);

      // Turn on parent.
      await _toggleSwitchByKey(tester, const Key('statistics-enabled-switch'));

      // Child toggles should now be enabled.
      await _scrollToKey(tester, const Key('statistics-viewer-comment-switch'));
      viewerTile = tester.widget(
        find.byKey(
          const Key('statistics-viewer-comment-switch'),
          skipOffstage: false,
        ),
      );
      expect(viewerTile.onChanged, isNotNull);

      await _scrollToKey(tester, const Key('statistics-active-user-switch'));
      activeTile = tester.widget(
        find.byKey(
          const Key('statistics-active-user-switch'),
          skipOffstage: false,
        ),
      );
      expect(activeTile.onChanged, isNotNull);
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: CommentDisplaySettingsScreen(
      settingsStore: settingsStore,
    ),
  );
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  final Finder target = find.byKey(key);
  final Finder scrollable = find
      .descendant(
        of: find.byKey(const Key('comment-display-settings-list')),
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

Future<void> _toggleSwitchByKey(WidgetTester tester, Key key) async {
  await _scrollToKey(tester, key);
  final SwitchListTile tile =
      tester.widget(find.byKey(key, skipOffstage: false));
  tile.onChanged!.call(!tile.value);
  await tester.pumpAndSettle();
}
