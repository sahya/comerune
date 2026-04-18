import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
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

    test(
      'uses a timestamped file name so repeated exports do not collide',
      () async {
        await withClock(Clock.fixed(DateTime(2026, 4, 18, 0, 1, 23)), () async {
          final String path = await store.writeExportToTempFile();
          final String name = path.split(Platform.pathSeparator).last;

          expect(name, 'comerune-settings_20260418_000123.json');
          expect(
            SettingsExport.timestampedFileNamePattern.hasMatch(name),
            isTrue,
            reason: 'generated file name must match timestampedFileNamePattern',
          );
        });
      },
    );

    test(
      'removes previous timestamped exports in the temp directory on next export',
      () async {
        // 複数の stale タイムスタンプ付きファイルを並べて、cleanup が
        // 全てを削除することを確認する。
        final List<File> strays = <File>[
          File(
            '${tempDir.path}${Platform.pathSeparator}'
            'comerune-settings_20250101_120000.json',
          ),
          File(
            '${tempDir.path}${Platform.pathSeparator}'
            'comerune-settings_20251231_235959.json',
          ),
          File(
            '${tempDir.path}${Platform.pathSeparator}'
            'comerune-settings_20260101_000000.json',
          ),
        ];
        for (final File f in strays) {
          await f.writeAsString('{"stale": true}');
          expect(f.existsSync(), isTrue);
        }

        // 無関係な他ファイルは消されないことも確認する。
        final File unrelated = File(
          '${tempDir.path}${Platform.pathSeparator}other-file.json',
        );
        await unrelated.writeAsString('{"keep": true}');

        // 新しいタイムスタンプで書き出す。
        await withClock(Clock.fixed(DateTime(2026, 4, 18, 0, 1, 23)), () async {
          await store.writeExportToTempFile();
        });

        final List<String> names = tempDir
            .listSync()
            .whereType<File>()
            .map((File f) => f.uri.pathSegments.last)
            .toList();

        expect(
          names.where(SettingsExport.timestampedFileNamePattern.hasMatch),
          <String>['comerune-settings_20260418_000123.json'],
        );
        for (final File f in strays) {
          expect(
            f.existsSync(),
            isFalse,
            reason: '${f.path} should be removed',
          );
        }
        expect(unrelated.existsSync(), isTrue);
      },
    );

    test(
      'writes a new timestamped file even when a previous one exists',
      () async {
        await withClock(Clock.fixed(DateTime(2026, 4, 18, 0, 1, 23)), () async {
          await store.writeExportToTempFile();
        });

        final AppSettings changed = AppSettings.defaults.copyWith(
          debugMode: true,
        );
        await store.save(changed);

        String? secondPath;
        await withClock(Clock.fixed(DateTime(2026, 4, 18, 0, 2, 45)), () async {
          secondPath = await store.writeExportToTempFile();
        });

        expect(
          secondPath!.endsWith('comerune-settings_20260418_000245.json'),
          isTrue,
        );
        final Map<String, dynamic> decoded =
            jsonDecode(await File(secondPath!).readAsString())
                as Map<String, dynamic>;
        expect(decoded['debugMode'], isTrue);
      },
    );
  });

  group('SettingsExport.timestampedFileName', () {
    test('pads every component with leading zeros', () {
      expect(
        SettingsExport.timestampedFileName(DateTime(2026, 1, 2, 3, 4, 5)),
        'comerune-settings_20260102_030405.json',
      );
    });

    test('matches timestampedFileNamePattern', () {
      final String name = SettingsExport.timestampedFileName(
        DateTime(2026, 12, 31, 23, 59, 59),
      );
      expect(SettingsExport.timestampedFileNamePattern.hasMatch(name), isTrue);
    });
  });
}
