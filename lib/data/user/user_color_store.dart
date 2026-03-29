import 'dart:convert';

import '../../application/settings/settings_store.dart';

/// Persists per-user comment color settings, scoped by broadcaster ID.
///
/// Colors are stored as integer values corresponding to [Color.value].
/// A `null` color means "use default" (i.e. no custom color).
abstract class UserColorStore {
  /// Returns the color map for all users under the given broadcaster.
  ///
  /// Keys are user IDs, values are [Color.value] integers.
  Future<Map<String, int>> load(String broadcasterId);

  /// Sets a custom color for a user under the given broadcaster.
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  });

  /// Removes the custom color for a user under the given broadcaster.
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  });
}

class SharedPreferencesUserColorStore implements UserColorStore {
  const SharedPreferencesUserColorStore({
    required SharedPreferencesLike prefs,
  }) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static String _key(String broadcasterId) => 'usercolor.$broadcasterId';

  @override
  Future<Map<String, int>> load(String broadcasterId) async {
    final String? raw = _prefs.getString(_key(broadcasterId));
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }
    try {
      final Map<String, dynamic> decoded =
          json.decode(raw) as Map<String, dynamic>;
      final Map<String, int> result = <String, int>{};
      for (final MapEntry<String, dynamic> entry in decoded.entries) {
        if (entry.value is int) {
          result[entry.key] = entry.value as int;
        }
      }
      return result;
    } on Object {
      return <String, int>{};
    }
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    final Map<String, int> current = await load(broadcasterId);
    current[userId] = colorValue;
    await _prefs.setString(_key(broadcasterId), json.encode(current));
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    final Map<String, int> current = await load(broadcasterId);
    if (!current.containsKey(userId)) {
      return;
    }
    current.remove(userId);
    await _prefs.setString(_key(broadcasterId), json.encode(current));
  }
}
