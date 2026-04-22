import 'dart:convert';
import 'dart:developer' as developer;

import '../../application/settings/settings_store.dart';
import 'file_user_attribute_store.dart';

/// One-shot migrator that copies per-broadcaster user attribute entries
/// from legacy `SharedPreferences` storage into [FileUserAttributeStore].
///
/// The migration runs at most once per install: once the `_migrationDone`
/// marker key is set in SharedPreferences, subsequent calls are no-ops.
///
/// Legacy rows (keys starting with `usercolor.`) are left in place after
/// migration. We do not delete them defensively so a future rollback can
/// still fall back to the old store; they will be removed by the existing
/// `cleanup()` routine on the old store if it is ever invoked.
class UserAttributeStoreMigrator {
  const UserAttributeStoreMigrator({
    required SharedPreferencesLike prefs,
    required FileUserAttributeStore fileStore,
  }) : _prefs = prefs,
       _fileStore = fileStore;

  final SharedPreferencesLike _prefs;
  final FileUserAttributeStore _fileStore;

  static const String _migrationDoneKey = 'usercolor.migratedToFile';
  static const String _legacyIndexKey = 'usercolor._index';
  static const String _legacyKeyPrefix = 'usercolor.';

  /// Copies legacy SharedPreferences data into [FileUserAttributeStore].
  /// Returns the number of broadcasters migrated.
  Future<int> run() async {
    if (_prefs.getBool(_migrationDoneKey) == true) {
      return 0;
    }

    final String? indexRaw = _prefs.getString(_legacyIndexKey);
    if (indexRaw == null || indexRaw.isEmpty) {
      await _prefs.setBool(_migrationDoneKey, true);
      return 0;
    }

    final List<String> broadcasterIds = _parseIndex(indexRaw);
    int migrated = 0;

    for (final String broadcasterId in broadcasterIds) {
      try {
        final String? rawJson = _prefs.getString(
          '$_legacyKeyPrefix$broadcasterId',
        );
        if (rawJson == null || rawJson.isEmpty) {
          continue;
        }
        await _fileStore.importRawJson(broadcasterId, rawJson);
        migrated++;
      } on Object catch (e) {
        developer.log(
          'Failed to migrate user attributes for $broadcasterId: $e',
          name: 'UserAttributeStoreMigrator',
        );
      }
    }

    await _prefs.setBool(_migrationDoneKey, true);
    developer.log(
      'Migrated $migrated broadcaster entries from SharedPreferences to file',
      name: 'UserAttributeStoreMigrator',
    );
    return migrated;
  }

  List<String> _parseIndex(String raw) {
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return <String>[];
    } on Object {
      return <String>[];
    }
  }
}
