import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesSettingsStore export/import', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesSettingsStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesSettingsStore(prefs: prefs);
    });

    test('exportAsJson returns valid pretty-printed JSON', () async {
      final String exported = await store.exportAsJson();

      final Object? decoded = jsonDecode(exported);
      expect(decoded, isA<Map<String, dynamic>>());

      // Should be pretty-printed (contains newlines).
      expect(exported.contains('\n'), isTrue);

      final Map<String, dynamic> json = decoded! as Map<String, dynamic>;
      expect(json['_version'], AppSettings.settingsVersion);
    });

    test('exportAsJson reflects saved settings', () async {
      final AppSettings custom = AppSettings.defaults.copyWith(
        themeMode: AppThemeMode.dark,
        voicevoxSpeaker: 99,
        debugMode: true,
      );
      await store.save(custom);

      final String exported = await store.exportAsJson();
      final Map<String, dynamic> json =
          jsonDecode(exported) as Map<String, dynamic>;

      expect(json['themeMode'], 'dark');
      expect(json['voicevoxSpeaker'], 99);
      expect(json['debugMode'], isTrue);
    });

    test('importFromJson saves settings and returns them', () async {
      final Map<String, dynamic> json = <String, dynamic>{
        '_version': 1,
        'themeMode': 'dark',
        'voicevoxSpeaker': 42,
        'commentFontSize': 20,
      };
      final String jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(json);

      final AppSettings imported = await store.importFromJson(jsonString);

      expect(imported.themeMode, AppThemeMode.dark);
      expect(imported.voicevoxSpeaker, 42);
      expect(imported.commentFontSize, 20);

      // Verify it was actually persisted.
      final AppSettings loaded = await store.load();
      expect(loaded.themeMode, AppThemeMode.dark);
      expect(loaded.voicevoxSpeaker, 42);
      expect(loaded.commentFontSize, 20);
    });

    test('importFromJson with invalid JSON throws FormatException', () async {
      expect(
        () => store.importFromJson('not valid json'),
        throwsFormatException,
      );
    });

    test('importFromJson with JSON array throws FormatException', () async {
      expect(() => store.importFromJson('[1, 2, 3]'), throwsFormatException);
    });

    test('roundtrip: export then import preserves all settings', () async {
      final AppSettings original = AppSettings.defaults.copyWith(
        themeMode: AppThemeMode.protanopia,
        autoReadEnabled: true,
        ngWords: 'word1\nword2',
        voicevoxSpeed: 1.5,
        commentFontSize: 36,
      );
      await store.save(original);

      final String exported = await store.exportAsJson();

      // Create a new store to import into.
      final InMemorySharedPreferences newPrefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore newStore =
          SharedPreferencesSettingsStore(prefs: newPrefs);

      final AppSettings imported = await newStore.importFromJson(exported);

      expect(imported.themeMode, AppThemeMode.protanopia);
      expect(imported.autoReadEnabled, isTrue);
      expect(imported.ngWords, 'word1\nword2');
      expect(imported.voicevoxSpeed, 1.5);
      expect(imported.commentFontSize, 36);
    });

    test('roundtrip preserves gift/nicoad display + TTS toggles', () async {
      final AppSettings original = AppSettings.defaults.copyWith(
        showGiftComment: false,
        showNicoadComment: false,
        readGiftComment: true,
        readNicoadComment: true,
      );
      await store.save(original);

      final String exported = await store.exportAsJson();

      final InMemorySharedPreferences newPrefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore newStore =
          SharedPreferencesSettingsStore(prefs: newPrefs);

      final AppSettings imported = await newStore.importFromJson(exported);

      expect(imported.showGiftComment, isFalse);
      expect(imported.showNicoadComment, isFalse);
      expect(imported.readGiftComment, isTrue);
      expect(imported.readNicoadComment, isTrue);
    });
  });
}
