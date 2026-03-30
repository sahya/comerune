import 'dart:developer';

import '../settings/settings_store.dart';

/// Runs one-time migration tasks when the app's migration version changes.
///
/// Each migration is identified by a sequential integer version. On startup
/// the runner compares the stored version against [currentMigrationVersion]
/// and executes any outstanding migrations in order.
///
/// This is intentionally decoupled from the APK `versionCode` so that
/// migrations can be added or skipped independently of release cadence.
class AppMigrationRunner {
  AppMigrationRunner({required SharedPreferencesLike prefs}) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _key = 'app.migrationVersion';

  /// Bump this constant and add a corresponding case in [_runMigration]
  /// whenever a new migration is needed.
  static const int currentMigrationVersion = 1;

  /// Run all pending migrations. Safe to call on every app startup.
  ///
  /// Returns `true` if at least one migration was executed.
  Future<bool> run() async {
    final int storedVersion = _prefs.getInt(_key) ?? 0;

    if (storedVersion >= currentMigrationVersion) {
      return false;
    }

    log(
      'Running migrations from v$storedVersion to v$currentMigrationVersion',
      name: 'AppMigrationRunner',
    );

    for (int version = storedVersion + 1;
        version <= currentMigrationVersion;
        version++) {
      await _runMigration(version);
    }

    await _prefs.setInt(_key, currentMigrationVersion);

    log(
      'All migrations complete (now at v$currentMigrationVersion)',
      name: 'AppMigrationRunner',
    );

    return true;
  }

  Future<void> _runMigration(int version) async {
    log('Running migration v$version', name: 'AppMigrationRunner');
    switch (version) {
      case 1:
        // Migration v1: No-op marker.
        // The VOICEVOX asset re-download is handled on the native (Kotlin)
        // side by incorporating the app versionCode into the asset version
        // check. This migration simply records that the migration framework
        // has been initialized.
        break;
      default:
        log(
          'Unknown migration version: $version — skipping',
          name: 'AppMigrationRunner',
        );
    }
  }
}
