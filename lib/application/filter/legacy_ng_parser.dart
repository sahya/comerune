import 'dart:convert';
import 'dart:developer' as developer;

import '../../domain/models/ng_word_rule.dart';
import '../../domain/utils/newline_parser.dart';
import '../settings/settings_store.dart';

/// Issue #727: shared helpers for parsing the legacy global NG storage.
///
/// Originally lived as private helpers in
/// [BroadcasterNgMigrator] but were promoted so the settings importer can
/// reuse the exact same parsing rules when restoring a legacy export file.
/// Both code paths must agree on what counts as "the user's pre-migration
/// NG state", otherwise import-after-fresh-install behaves differently
/// from the in-place migration.
///
/// Two flavors of helpers live here:
///   - [readLegacyNgUserIds] / [readLegacyNgWordRules] operate directly
///     on a [SharedPreferencesLike] backend and are used by the migrator
///     during app startup, when only raw preference strings are available.
///   - [mergeLegacyNgWordRules] operates on already-parsed
///     `AppSettings.ngWordRules` / `AppSettings.ngWords` fields and is
///     used by the importer, which has decoded the export JSON into the
///     model and only needs the merge / dedup logic.
class LegacyNgParser {
  const LegacyNgParser._();

  /// Legacy SharedPreferences key for the newline-separated NG user IDs
  /// list. Kept aligned with [SharedPreferencesSettingsStore].
  static const String legacyNgUserIdsKey = 'settings.filter.ngUserIds';

  /// Legacy SharedPreferences key for the JSON-encoded structured NG word
  /// rules list. Kept aligned with [SharedPreferencesSettingsStore].
  static const String legacyNgWordRulesKey = 'settings.filter.ngWordRules';

  /// Legacy SharedPreferences key for the older newline-separated NG words
  /// plain string. Kept aligned with [SharedPreferencesSettingsStore].
  static const String legacyNgWordsKey = 'settings.filter.ngWords';

  /// Reads the newline-separated NG user IDs from [prefs].
  ///
  /// Empty / missing values yield an empty set. Whitespace-only and
  /// duplicate entries are dropped via [parseNewlineSeparatedSet].
  static Set<String> readLegacyNgUserIds(SharedPreferencesLike prefs) {
    final String? raw = prefs.getString(legacyNgUserIdsKey);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    return parseNewlineSeparatedSet(raw);
  }

  /// Combined view of the legacy `ngWordRules` JSON list and the older
  /// newline-separated `ngWords` plain string.
  ///
  /// Lines from `ngWords` whose pattern is already present in `ngWordRules`
  /// are skipped to avoid double-listing the same word after migration /
  /// import.
  ///
  /// Failures while parsing individual entries are logged via
  /// `dart:developer` and treated as "skip this entry" so a single
  /// malformed item never aborts the whole legacy restore.
  static List<NgWordRule> readLegacyNgWordRules(SharedPreferencesLike prefs) {
    final List<NgWordRule> rules = <NgWordRule>[];
    final Set<String> seenPatterns = <String>{};

    final String? rulesRaw = prefs.getString(legacyNgWordRulesKey);
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
              name: 'LegacyNgParser',
            );
          }
        }
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to parse legacy ngWordRules JSON: $error',
          name: 'LegacyNgParser',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final String? wordsRaw = prefs.getString(legacyNgWordsKey);
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

  /// Merges a structured `ngWordRules` list with the older newline-separated
  /// `ngWords` plain string into a deduplicated list of rules.
  ///
  /// Used by the settings importer when restoring a legacy export JSON: the
  /// JSON has already been parsed into [AppSettings.ngWordRules] /
  /// [AppSettings.ngWords] by [AppSettings.fromJson], so this helper
  /// operates on the parsed values rather than re-reading from preferences.
  ///
  /// Falsy / empty inputs yield an empty list. Empty patterns and duplicate
  /// patterns are dropped — duplicates are resolved in favor of the entry
  /// from [structuredRules] (which carries the user's enabled flag).
  static List<NgWordRule> mergeLegacyNgWordRules({
    required List<NgWordRule> structuredRules,
    required String legacyNgWords,
  }) {
    final List<NgWordRule> rules = <NgWordRule>[];
    final Set<String> seenPatterns = <String>{};

    for (final NgWordRule rule in structuredRules) {
      if (rule.pattern.isEmpty) {
        continue;
      }
      if (seenPatterns.add(rule.pattern)) {
        rules.add(rule);
      }
    }

    if (legacyNgWords.isNotEmpty) {
      for (final String line in legacyNgWords.split('\n')) {
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
}
