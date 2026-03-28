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
  });
}
