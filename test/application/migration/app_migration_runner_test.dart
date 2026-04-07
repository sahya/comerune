import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/migration/app_migration_runner.dart';

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
}
