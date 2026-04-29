import 'dart:convert';
import 'dart:developer';

import '../../comment_speech/src/models/replace_rule.dart';
import '../../domain/models/app_settings.dart';
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
  static const int currentMigrationVersion = 3;

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

    for (
      int version = storedVersion + 1;
      version <= currentMigrationVersion;
      version++
    ) {
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
      case 3:
        // Migration v3: Backfill the "single w/ｗ → わら" dictionary preset
        // for users whose saved dictionary predates that preset being added.
        await _backfillSingleWDictionaryPresets();
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
        .map((String pattern) => NgWordRule(pattern: pattern).toMap())
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

  /// Patterns that read a single `w` / `ｗ` as 「わら」.
  ///
  /// These rules were added to [defaultNicoDictionaryRules] after some users
  /// had already persisted their dictionary. Without this backfill, those
  /// users keep seeing only the older multi-`w` rules.
  ///
  /// The patterns are a subset of [defaultNicoDictionaryRules] and must stay
  /// in sync; the migration appends only the rules whose `pattern` is missing
  /// from the user's saved dictionary so previously-deleted built-ins are not
  /// re-added more than once.
  static const List<String> _singleWPresetPatterns = <String>[
    r'[wｗ]$',
    r'(?<![A-Za-z0-9])[wｗ](?![A-Za-z0-9])',
  ];

  /// Append any missing "single w/ｗ → わら" preset rules to the user's
  /// saved dictionary. No-op when the dictionary key is unset (fresh install
  /// — defaults will be loaded on first read) or when the stored JSON is
  /// malformed (avoid clobbering user data on parse failure).
  Future<void> _backfillSingleWDictionaryPresets() async {
    const String key = 'settings.speech.dictionaryRules';

    final String? raw = _prefs.getString(key);
    if (raw == null) {
      // Fresh install: defaults are returned by the store when the key is
      // null, so no migration is needed.
      return;
    }

    final List<ReplaceRule> rules;
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      rules = decoded
          .map((dynamic e) => ReplaceRule.fromMap(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e) {
      log(
        'Skipping single-w preset backfill: failed to parse dictionary JSON: $e',
        name: 'AppMigrationRunner',
      );
      return;
    }

    final Set<String> existingPatterns = rules
        .map((ReplaceRule r) => r.pattern)
        .toSet();

    final List<ReplaceRule> additions = <ReplaceRule>[];
    for (final String pattern in _singleWPresetPatterns) {
      if (existingPatterns.contains(pattern)) continue;
      // Pull the canonical rule (replacement + enabled defaults) from the
      // built-in defaults so the inserted rule matches a fresh install.
      // The defensive null-fallback guards against subset drift between
      // [_singleWPresetPatterns] and [defaultNicoDictionaryRules]: if a
      // future edit removes a referenced pattern from the defaults, skip
      // it instead of crashing app startup. The subset is also asserted
      // by a unit test so this branch should be unreachable in practice.
      ReplaceRule? preset;
      for (final ReplaceRule r in defaultNicoDictionaryRules) {
        if (r.pattern == pattern) {
          preset = r;
          break;
        }
      }
      if (preset == null) {
        log(
          'Single-w preset pattern not found in defaults; skipping: $pattern',
          name: 'AppMigrationRunner',
        );
        continue;
      }
      additions.add(preset);
    }

    if (additions.isEmpty) {
      return;
    }

    final List<ReplaceRule> merged = <ReplaceRule>[...rules, ...additions];
    await _prefs.setString(
      key,
      jsonEncode(merged.map((ReplaceRule r) => r.toMap()).toList()),
    );

    log(
      'Backfilled ${additions.length} single-w preset dictionary rule(s)',
      name: 'AppMigrationRunner',
    );
  }
}
