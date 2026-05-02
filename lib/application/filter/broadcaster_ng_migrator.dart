import 'dart:convert';
import 'dart:developer' as developer;

import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/ng_word_rule.dart';
import '../../domain/utils/newline_parser.dart';
import '../settings/settings_store.dart';

/// One-shot migrator that converts the legacy global NG configuration
/// (`settings.filter.ngWords`, `settings.filter.ngUserIds`,
/// `settings.filter.ngWordRules`) into the new per-broadcaster scheme
/// backed by [BroadcasterNgStore].
///
/// Behavior:
/// - The combined NG user IDs / NG word rules are written as the
///   "template" — the seed value that any future broadcaster's first-access
///   init will copy.
/// - Each known broadcaster (passed via `knownBroadcasterIds`) is also
///   seeded with the same content so existing relationships immediately
///   inherit the user's pre-migration NG settings.
/// - Legacy SharedPreferences keys are NOT deleted; the legacy NG-list
///   screens will keep editing them until PR2 retargets them. A flag at
///   [migrationFlagKey] makes the migration idempotent.
///
/// Failures while reading any individual legacy key are logged via
/// `dart:developer` and treated as "no legacy data for that key" so a
/// malformed entry never blocks app startup.
///
/// TODO(#727):
///   - PR2 will retarget the NG user / NG word list screens to write
///     through [BroadcasterNgStore] instead of `AppSettings.ngUserIds` /
///     `AppSettings.ngWordRules`.
///   - PR3 will move Export/Import (`AppSettings.toJson` / `fromJson`) to
///     include the per-broadcaster slots.
class BroadcasterNgMigrator {
  const BroadcasterNgMigrator._();

  /// SharedPreferences flag key that records the migration as done.
  /// Subsequent calls to [migrateIfNeeded] short-circuit when this is set.
  static const String migrationFlagKey = 'settings.filter.migration.v1Completed';

  // Legacy key names — kept aligned with [SharedPreferencesSettingsStore].
  static const String _legacyNgWordsKey = 'settings.filter.ngWords';
  static const String _legacyNgUserIdsKey = 'settings.filter.ngUserIds';
  static const String _legacyNgWordRulesKey = 'settings.filter.ngWordRules';

  /// Runs the migration unless [migrationFlagKey] is already set.
  ///
  /// [knownBroadcasterIds] is the set of broadcasters that should receive
  /// an explicit per-broadcaster copy of the legacy NG data. Typically
  /// sourced from the user attribute store's index, since that is the
  /// list of broadcasters the user has interacted with so far.
  ///
  /// Empty / duplicated IDs are silently dropped. Errors during seeding
  /// of an individual broadcaster are logged and do not abort the run —
  /// the migration flag is still set so the migrator does not retry the
  /// same partial work indefinitely.
  static Future<void> migrateIfNeeded({
    required SharedPreferencesLike prefs,
    required BroadcasterNgStore store,
    required Iterable<String> knownBroadcasterIds,
  }) async {
    if (prefs.getBool(migrationFlagKey) == true) {
      return;
    }

    Set<String> ngUserIds = <String>{};
    List<NgWordRule> ngWordRules = <NgWordRule>[];

    try {
      ngUserIds = _readLegacyNgUserIds(prefs);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to read legacy ngUserIds: $error',
        name: 'BroadcasterNgMigrator',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      ngWordRules = _readLegacyNgWordRules(prefs);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to read legacy ngWordRules / ngWords: $error',
        name: 'BroadcasterNgMigrator',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await store.saveTemplateNgUserIds(ngUserIds);
      await store.saveTemplateNgWordRules(ngWordRules);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to write template NG data: $error',
        name: 'BroadcasterNgMigrator',
        error: error,
        stackTrace: stackTrace,
      );
    }

    final Set<String> seen = <String>{};
    for (final String broadcasterId in knownBroadcasterIds) {
      if (broadcasterId.isEmpty) {
        continue;
      }
      if (!seen.add(broadcasterId)) {
        continue;
      }
      try {
        await store.saveNgUserIds(broadcasterId, ngUserIds);
        await store.saveNgWordRules(broadcasterId, ngWordRules);
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to seed NG data for broadcaster '
          '${_redactBroadcasterId(broadcasterId)}: $error',
          name: 'BroadcasterNgMigrator',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    try {
      await prefs.setBool(migrationFlagKey, true);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to set migration flag: $error',
        name: 'BroadcasterNgMigrator',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Set<String> _readLegacyNgUserIds(SharedPreferencesLike prefs) {
    final String? raw = prefs.getString(_legacyNgUserIdsKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    return parseNewlineSeparatedSet(raw);
  }

  /// Combined view of the legacy `ngWordRules` JSON list and the older
  /// newline-separated `ngWords` plain string. Lines from `ngWords` whose
  /// pattern is already present in `ngWordRules` are skipped to avoid
  /// double-listing the same word after migration.
  static List<NgWordRule> _readLegacyNgWordRules(SharedPreferencesLike prefs) {
    final List<NgWordRule> rules = <NgWordRule>[];
    final Set<String> seenPatterns = <String>{};

    final String? rulesRaw = prefs.getString(_legacyNgWordRulesKey);
    if (rulesRaw != null && rulesRaw.isNotEmpty) {
      try {
        final List<dynamic> decoded = json.decode(rulesRaw) as List<dynamic>;
        for (final dynamic item in decoded) {
          if (item is! Map) {
            continue;
          }
          try {
            final NgWordRule rule = NgWordRule.fromMap(
              item.cast<String, dynamic>(),
            );
            if (rule.pattern.isEmpty) {
              continue;
            }
            if (seenPatterns.add(rule.pattern)) {
              rules.add(rule);
            }
          } on Object catch (error) {
            developer.log(
              'Skipped malformed ngWordRules entry: $error',
              name: 'BroadcasterNgMigrator',
            );
          }
        }
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to parse legacy ngWordRules JSON: $error',
          name: 'BroadcasterNgMigrator',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final String? wordsRaw = prefs.getString(_legacyNgWordsKey);
    if (wordsRaw != null && wordsRaw.isNotEmpty) {
      for (final String line in wordsRaw.split('\n')) {
        final String pattern = line.trim();
        if (pattern.isEmpty) {
          continue;
        }
        if (seenPatterns.add(pattern)) {
          rules.add(NgWordRule(pattern: pattern));
        }
      }
    }

    return rules;
  }

  /// Returns a short prefix-only form of [broadcasterId] suitable for
  /// developer-log output, so error messages do not leak full IDs into
  /// device logs / crash reports.
  static String _redactBroadcasterId(String broadcasterId) {
    if (broadcasterId.length > 4) {
      return '${broadcasterId.substring(0, 4)}***';
    }
    return '***';
  }
}
