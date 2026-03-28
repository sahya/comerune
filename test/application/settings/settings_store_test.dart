import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesSettingsStore', () {
    test('showUserName defaults to true when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.showUserName, isTrue);
    });

    test('round-trips showUserName value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        showUserName: false,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.showUserName, isFalse);
    });

    test('commentFontSize defaults to 14 when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.commentFontSize, commentFontSizeDefault);
    });

    test('round-trips commentFontSize value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      for (final double size in <double>[10, 14, 24, 36, 48]) {
        final AppSettings original = AppSettings.defaults.copyWith(
          commentFontSize: size,
        );
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(loaded.commentFontSize, size, reason: '$size should round-trip');
      }
    });

    test('migrates legacy enum commentFontSize values', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: prefs);

      // Simulate a legacy stored value.
      await prefs.setString('settings.comment.fontSize', 'xl');

      final AppSettings loaded = await store.load();

      expect(loaded.commentFontSize, 18);
    });

    test('autoSaveCommentLog defaults to false when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.autoSaveCommentLog, isFalse);
    });

    test('round-trips autoSaveCommentLog value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings original = AppSettings.defaults.copyWith(
        autoSaveCommentLog: true,
      );
      await store.save(original);

      final AppSettings loaded = await store.load();

      expect(loaded.autoSaveCommentLog, isTrue);
    });

    test('themeMode defaults to light when not stored', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      final AppSettings loaded = await store.load();

      expect(loaded.themeMode, AppThemeMode.light);
    });

    test('round-trips themeMode value', () async {
      final SharedPreferencesSettingsStore store =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      for (final AppThemeMode mode in AppThemeMode.values) {
        final AppSettings original =
            AppSettings.defaults.copyWith(themeMode: mode);
        await store.save(original);

        final AppSettings loaded = await store.load();

        expect(loaded.themeMode, mode);
      }
    });
  });
}
