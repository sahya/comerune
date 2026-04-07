import 'dart:convert';
import 'dart:developer';

import '../../domain/models/ng_word_rule.dart';
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
  static const int currentMigrationVersion = 2;

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
      // Persist progress after each successful migration so that a failure
      // in a later migration does not re-run already completed ones.
      await _prefs.setInt(_key, version);
    }

    log(
      'All migrations complete (now at v$currentMigrationVersion)',
      name: 'AppMigrationRunner',
    );

    return true;
  }

  /// **Important**: Migrations must NEVER clear cookies, user sessions, or
  /// authentication data. Users expect to remain logged in after an upgrade.
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
      case 2:
        // Migration v2: Convert newline-separated NG words to structured
        // JSON format with per-word enable/disable toggle.
        await _migrateNgWordsToRules();
        break;
      default:
        log(
          'Unknown migration version: $version — skipping',
          name: 'AppMigrationRunner',
        );
    }
  }

  /// Convert legacy newline-separated NG words (`settings.filter.ngWords`)
  /// to the structured JSON format (`settings.filter.ngWordRules`).
  ///
  /// All migrated words are created with `enabled: true`.
  Future<void> _migrateNgWordsToRules() async {
    const String oldKey = 'settings.filter.ngWords';
    const String newKey = 'settings.filter.ngWordRules';

    // Skip if the new format already exists.
    final String? existing = _prefs.getString(newKey);
    if (existing != null) {
      return;
    }

    final String? raw = _prefs.getString(oldKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    final List<Map<String, dynamic>> rules = raw
        .split('\n')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .map(
          (String pattern) => NgWordRule(pattern: pattern).toMap(),
        )
        .toList();

    if (rules.isNotEmpty) {
      // Write new format first, then clear old key (crash-safe order).
      await _prefs.setString(newKey, jsonEncode(rules));
    }

    await _prefs.remove(oldKey);

    log(
      'Migrated ${rules.length} NG words to structured format',
      name: 'AppMigrationRunner',
    );
  }
}
