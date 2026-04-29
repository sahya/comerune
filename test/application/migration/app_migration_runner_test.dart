import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/migration/app_migration_runner.dart';
import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/app_settings.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('AppMigrationRunner', () {
    test('runs migrations on fresh install and stores version', () async {
      final prefs = InMemorySharedPreferences();
      final runner = AppMigrationRunner(prefs: prefs);

      final bool ran = await runner.run();

      expect(ran, isTrue);
      expect(
        prefs.getInt('app.migrationVersion'),
        AppMigrationRunner.currentMigrationVersion,
      );
    });

    test('does not run when already at current version', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setInt(
        'app.migrationVersion',
        AppMigrationRunner.currentMigrationVersion,
      );

      final runner = AppMigrationRunner(prefs: prefs);
      final bool ran = await runner.run();

      expect(ran, isFalse);
    });

    test('runs only pending migrations on upgrade', () async {
      final prefs = InMemorySharedPreferences();
      // Simulate a previous run that stopped at version 0.
      await prefs.setInt('app.migrationVersion', 0);

      final runner = AppMigrationRunner(prefs: prefs);
      final bool ran = await runner.run();

      expect(ran, isTrue);
      expect(
        prefs.getInt('app.migrationVersion'),
        AppMigrationRunner.currentMigrationVersion,
      );
    });

    test('is idempotent when called multiple times', () async {
      final prefs = InMemorySharedPreferences();
      final runner = AppMigrationRunner(prefs: prefs);

      await runner.run();
      final bool secondRun = await runner.run();

      expect(secondRun, isFalse);
      expect(
        prefs.getInt('app.migrationVersion'),
        AppMigrationRunner.currentMigrationVersion,
      );
    });
  });

  group('Migration v2: NG words to rules', () {
    test('converts newline-separated NG words to structured JSON', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setString('settings.filter.ngWords', 'word1\nword2\nword3');

      final runner = AppMigrationRunner(prefs: prefs);
      await runner.run();

      final String? raw = prefs.getString('settings.filter.ngWordRules');
      expect(raw, isNotNull);

      final List<dynamic> rules = jsonDecode(raw!) as List<dynamic>;
      expect(rules.length, 3);
      expect(rules[0]['pattern'], 'word1');
      expect(rules[0]['enabled'], isTrue);
      expect(rules[2]['pattern'], 'word3');

      // Old key should be removed.
      expect(prefs.getString('settings.filter.ngWords'), isNull);
    });

    test('skips migration when old key is empty', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setString('settings.filter.ngWords', '  \n  ');

      final runner = AppMigrationRunner(prefs: prefs);
      await runner.run();

      expect(prefs.getString('settings.filter.ngWordRules'), isNull);
    });

    test('skips migration when old key is null', () async {
      final prefs = InMemorySharedPreferences();
      // No ngWords key set at all.

      final runner = AppMigrationRunner(prefs: prefs);
      await runner.run();

      expect(prefs.getString('settings.filter.ngWordRules'), isNull);
    });

    test('skips migration when new key already exists', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setString('settings.filter.ngWords', 'old_word');
      await prefs.setString(
        'settings.filter.ngWordRules',
        '[{"pattern":"existing","enabled":true}]',
      );

      final runner = AppMigrationRunner(prefs: prefs);
      await runner.run();

      // New key should not be overwritten.
      final List<dynamic> rules =
          jsonDecode(prefs.getString('settings.filter.ngWordRules')!)
              as List<dynamic>;
      expect(rules.length, 1);
      expect(rules[0]['pattern'], 'existing');
    });

    test('trims blank lines and whitespace during migration', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setString(
        'settings.filter.ngWords',
        '  hello  \n\n  world  \n',
      );

      final runner = AppMigrationRunner(prefs: prefs);
      await runner.run();

      final List<dynamic> rules =
          jsonDecode(prefs.getString('settings.filter.ngWordRules')!)
              as List<dynamic>;
      expect(rules.length, 2);
      expect(rules[0]['pattern'], 'hello');
      expect(rules[1]['pattern'], 'world');
    });
  });

  group('Migration v3: single-w dictionary preset backfill', () {
    const String dictKey = 'settings.speech.dictionaryRules';
    const String standalonePattern = r'(?<![A-Za-z0-9])[wｗ](?![A-Za-z0-9])';
    const String endOfStringPattern = r'[wｗ]$';

    Map<String, dynamic> rule(
      String pattern,
      String replacement, {
      bool enabled = true,
    }) => <String, dynamic>{
      'pattern': pattern,
      'replacement': replacement,
      'enabled': enabled,
    };

    test('appends both presets when both are missing', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setInt('app.migrationVersion', 2);
      await prefs.setString(
        dictKey,
        jsonEncode(<Map<String, dynamic>>[
          rule(r'[wｗ]{3,}', 'わらわら'),
          rule('うぽつ', 'うぷおつ'),
        ]),
      );

      await AppMigrationRunner(prefs: prefs).run();

      final List<dynamic> rules =
          jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
      expect(rules.length, 4, reason: 'Two original + two appended presets');
      expect(rules[0]['pattern'], r'[wｗ]{3,}');
      expect(rules[1]['pattern'], 'うぽつ');
      expect(rules[2]['pattern'], endOfStringPattern);
      expect(rules[2]['replacement'], 'わら');
      expect(rules[2]['enabled'], isTrue);
      expect(rules[3]['pattern'], standalonePattern);
      expect(rules[3]['replacement'], 'わら');
      expect(rules[3]['enabled'], isTrue);
    });

    test('appends only the missing preset when one already exists', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setInt('app.migrationVersion', 2);
      await prefs.setString(
        dictKey,
        jsonEncode(<Map<String, dynamic>>[rule(endOfStringPattern, 'わら')]),
      );

      await AppMigrationRunner(prefs: prefs).run();

      final List<dynamic> rules =
          jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
      expect(rules.length, 2);
      expect(rules[0]['pattern'], endOfStringPattern);
      expect(rules[1]['pattern'], standalonePattern);
    });

    test(
      'does not modify dictionary when both presets are already present',
      () async {
        final prefs = InMemorySharedPreferences();
        await prefs.setInt('app.migrationVersion', 2);
        final String original = jsonEncode(<Map<String, dynamic>>[
          rule(endOfStringPattern, 'わら'),
          rule(standalonePattern, 'わら'),
          rule('うぽつ', 'うぷおつ'),
        ]);
        await prefs.setString(dictKey, original);

        await AppMigrationRunner(prefs: prefs).run();

        expect(prefs.getString(dictKey), original);
      },
    );

    test(
      'preserves user-customized replacement and disabled state by pattern',
      () async {
        final prefs = InMemorySharedPreferences();
        await prefs.setInt('app.migrationVersion', 2);
        await prefs.setString(
          dictKey,
          jsonEncode(<Map<String, dynamic>>[
            rule(endOfStringPattern, 'カスタム', enabled: false),
          ]),
        );

        await AppMigrationRunner(prefs: prefs).run();

        final List<dynamic> rules =
            jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
        expect(rules.length, 2);
        expect(rules[0]['pattern'], endOfStringPattern);
        expect(rules[0]['replacement'], 'カスタム');
        expect(rules[0]['enabled'], isFalse);
        expect(rules[1]['pattern'], standalonePattern);
      },
    );

    test('skips on fresh install (no dictionary key set)', () async {
      final prefs = InMemorySharedPreferences();

      await AppMigrationRunner(prefs: prefs).run();

      expect(prefs.getString(dictKey), isNull);
      expect(
        prefs.getInt('app.migrationVersion'),
        AppMigrationRunner.currentMigrationVersion,
      );
    });

    test('does not clobber user data when JSON is malformed', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setInt('app.migrationVersion', 2);
      const String corrupt = '{not-json';
      await prefs.setString(dictKey, corrupt);

      await AppMigrationRunner(prefs: prefs).run();

      expect(prefs.getString(dictKey), corrupt);
      expect(
        prefs.getInt('app.migrationVersion'),
        AppMigrationRunner.currentMigrationVersion,
      );
    });

    test(
      'appends both presets when stored dictionary is an empty array',
      () async {
        final prefs = InMemorySharedPreferences();
        await prefs.setInt('app.migrationVersion', 2);
        await prefs.setString(dictKey, '[]');

        await AppMigrationRunner(prefs: prefs).run();

        final List<dynamic> rules =
            jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
        expect(rules.length, 2);
        expect(rules[0]['pattern'], endOfStringPattern);
        expect(rules[1]['pattern'], standalonePattern);
      },
    );

    test(
      'does not clobber user data when JSON parses to a non-array',
      () async {
        final prefs = InMemorySharedPreferences();
        await prefs.setInt('app.migrationVersion', 2);
        const String nonArray = '{"oops":"object"}';
        await prefs.setString(dictKey, nonArray);

        await AppMigrationRunner(prefs: prefs).run();

        expect(prefs.getString(dictKey), nonArray);
      },
    );

    test('every targeted preset pattern exists in defaultNicoDictionaryRules '
        '(subset invariant)', () {
      // Drift detector: this migration relies on the patterns it backfills
      // also being present in the built-in defaults, so it can copy the
      // canonical replacement string. If a future edit drops one of these
      // patterns from defaultNicoDictionaryRules without updating the
      // migration, the backfill silently degrades to a no-op for that
      // pattern. Asserting at test time keeps the two lists in sync.
      //
      // Pure invariant check — does not exercise the migration so the
      // assertion remains diagnostic even if backfill behavior changes.
      for (final String pattern in const <String>[
        endOfStringPattern,
        standalonePattern,
      ]) {
        expect(
          defaultNicoDictionaryRules.any(
            (ReplaceRule r) => r.pattern == pattern,
          ),
          isTrue,
          reason:
              'Default rules must still contain "$pattern". If you removed '
              'it intentionally, also remove it from the migration target '
              'list (see _singleWPresetPatterns in AppMigrationRunner).',
        );
      }
    });

    test('only runs once across multiple startups', () async {
      final prefs = InMemorySharedPreferences();
      await prefs.setInt('app.migrationVersion', 2);
      await prefs.setString(
        dictKey,
        jsonEncode(<Map<String, dynamic>>[rule(r'[wｗ]{3,}', 'わらわら')]),
      );

      await AppMigrationRunner(prefs: prefs).run();

      // Simulate a user deleting the preset post-migration.
      final List<dynamic> afterFirst =
          jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
      afterFirst.removeWhere(
        (dynamic r) =>
            (r as Map<String, dynamic>)['pattern'] == endOfStringPattern,
      );
      await prefs.setString(dictKey, jsonEncode(afterFirst));

      // Second startup must not re-add the deleted preset.
      await AppMigrationRunner(prefs: prefs).run();

      final List<dynamic> afterSecond =
          jsonDecode(prefs.getString(dictKey)!) as List<dynamic>;
      expect(
        afterSecond.any(
          (dynamic r) =>
              (r as Map<String, dynamic>)['pattern'] == endOfStringPattern,
        ),
        isFalse,
      );
    });
  });
}
