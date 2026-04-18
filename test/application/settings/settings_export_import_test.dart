import 'dart:convert';
import 'dart:io';

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

    test('exportAsJson emits favoriteUserIds as a JSON array, '
        'and legacy string format is still importable', () async {
      final AppSettings original = AppSettings.defaults.copyWith(
        favoriteUserIds: 'user-a\nuser-b',
      );
      await store.save(original);

      final String exported = await store.exportAsJson();
      final Map<String, dynamic> json =
          jsonDecode(exported) as Map<String, dynamic>;
      expect(json['favoriteUserIds'], <String>['user-a', 'user-b']);

      // Roundtrip: export (array) → import → matches original value.
      final InMemorySharedPreferences newPrefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore newStore =
          SharedPreferencesSettingsStore(prefs: newPrefs);
      final AppSettings imported = await newStore.importFromJson(exported);
      expect(imported.favoriteUserIdSet, <String>{'user-a', 'user-b'});

      // Legacy string format is still accepted by import.
      final InMemorySharedPreferences legacyPrefs = InMemorySharedPreferences();
      final SharedPreferencesSettingsStore legacyStore =
          SharedPreferencesSettingsStore(prefs: legacyPrefs);
      final Map<String, dynamic> legacyJson = <String, dynamic>{
        '_version': 1,
        'favoriteUserIds': 'legacy-1\nlegacy-2',
      };
      final AppSettings legacyImported = await legacyStore.importFromJson(
        const JsonEncoder.withIndent('  ').convert(legacyJson),
      );
      expect(legacyImported.favoriteUserIdSet, <String>{
        'legacy-1',
        'legacy-2',
      });
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

  group('SharedPreferencesSettingsStore.writeExportToTempFile', () {
    late InMemorySharedPreferences prefs;
    late Directory tempDir;
    late SharedPreferencesSettingsStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      tempDir = Directory.systemTemp.createTempSync('comerune_settings_test_');
      store = SharedPreferencesSettingsStore(
        prefs: prefs,
        tempDirectory: tempDir,
      );
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes JSON to a `.json` file and matches exportAsJson', () async {
      final AppSettings custom = AppSettings.defaults.copyWith(
        themeMode: AppThemeMode.dark,
        voicevoxSpeaker: 42,
      );
      await store.save(custom);

      final String path = await store.writeExportToTempFile();

      expect(path.endsWith('.json'), isTrue);
      final File file = File(path);
      expect(file.existsSync(), isTrue);

      final String fileContent = await file.readAsString();
      final String exportedJson = await store.exportAsJson();
      expect(fileContent, exportedJson);

      final Map<String, dynamic> decoded =
          jsonDecode(fileContent) as Map<String, dynamic>;
      expect(decoded['themeMode'], 'dark');
      expect(decoded['voicevoxSpeaker'], 42);
    });

    test('creates the temp directory when it does not yet exist', () async {
      final Directory nested = Directory('${tempDir.path}/nested_subdir');
      final SharedPreferencesSettingsStore nestedStore =
          SharedPreferencesSettingsStore(prefs: prefs, tempDirectory: nested);

      expect(nested.existsSync(), isFalse);

      final String path = await nestedStore.writeExportToTempFile();

      expect(File(path).existsSync(), isTrue);
      expect(nested.existsSync(), isTrue);
    });

    test('overwrites the previous file on repeated export', () async {
      final String firstPath = await store.writeExportToTempFile();

      final AppSettings changed = AppSettings.defaults.copyWith(
        debugMode: true,
      );
      await store.save(changed);

      final String secondPath = await store.writeExportToTempFile();

      // Same logical destination (no timestamp suffix) — overwrite semantics.
      expect(firstPath, secondPath);
      final Map<String, dynamic> decoded =
          jsonDecode(await File(secondPath).readAsString())
              as Map<String, dynamic>;
      expect(decoded['debugMode'], isTrue);
    });

    test('uses SettingsExport.fileName as the canonical file name', () async {
      final String path = await store.writeExportToTempFile();
      expect(path.endsWith('/${SettingsExport.fileName}'), isTrue);
    });
  });
}
