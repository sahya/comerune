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
}
