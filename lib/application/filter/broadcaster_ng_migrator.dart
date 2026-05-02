import 'dart:developer' as developer;

import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/ng_word_rule.dart';
import '../settings/settings_store.dart';
import 'legacy_ng_parser.dart';

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
  static const String migrationFlagKey =
      'settings.filter.migration.v1Completed';

  /// Number of leading characters of a broadcaster ID kept verbatim in
  /// redacted log output. Anything past this prefix is replaced with
  /// `***` so device logs / crash reports never carry the full ID.
  static const int _redactPrefixLength = 4;

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
      ngUserIds = LegacyNgParser.readLegacyNgUserIds(prefs);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to read legacy ngUserIds: $error',
        name: 'BroadcasterNgMigrator',
        error: error,
        stackTrace: stackTrace,
      );
    }

    try {
      ngWordRules = LegacyNgParser.readLegacyNgWordRules(prefs);
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

  /// Returns a short prefix-only form of [broadcasterId] suitable for
  /// developer-log output, so error messages do not leak full IDs into
  /// device logs / crash reports.
  static String _redactBroadcasterId(String broadcasterId) {
    if (broadcasterId.length > _redactPrefixLength) {
      return '${broadcasterId.substring(0, _redactPrefixLength)}***';
    }
    return '***';
  }
}
