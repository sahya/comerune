import 'dart:convert';

import '../../application/settings/settings_store.dart';

/// Persists per-user comment color settings, scoped by broadcaster ID.
///
/// Colors are stored as ARGB32 integer values (see `Color.toARGB32()`).
/// A `null` color means "use default" (i.e. no custom color).
///
/// Each broadcaster entry tracks a `_lastUsedAt` timestamp (milliseconds
/// since epoch). [cleanup] removes entries that have not been accessed
/// for longer than [maxAge].
abstract class UserColorStore {
  /// Returns the color map for all users under the given broadcaster.
  ///
  /// Keys are user IDs, values are ARGB32 integers.
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

  /// Removes broadcaster entries that have not been accessed for longer
  /// than [maxAge]. Defaults to 365 days.
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)});
}

class SharedPreferencesUserColorStore implements UserColorStore {
  const SharedPreferencesUserColorStore({
    required SharedPreferencesLike prefs,
  }) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _indexKey = 'usercolor._index';
  static const String _lastUsedAtField = '_lastUsedAt';

  static String _key(String broadcasterId) => 'usercolor.$broadcasterId';

  @override
  Future<Map<String, int>> load(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return <String, int>{};
    }

    // Update last-used timestamp on every access.
    await _touchLastUsedAt(broadcasterId, raw);

    return _extractColors(raw);
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    raw[userId] = colorValue;
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_key(broadcasterId), json.encode(raw));
    await _addToIndex(broadcasterId);
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (!raw.containsKey(userId)) {
      return;
    }
    raw.remove(userId);
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_key(broadcasterId), json.encode(raw));
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    final List<String> index = _readIndex();
    if (index.isEmpty) {
      return 0;
    }

    final int cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final List<String> remaining = <String>[];
    int removedCount = 0;

    for (final String broadcasterId in index) {
      final Map<String, dynamic> raw = _readRaw(broadcasterId);
      final int lastUsedAt =
          raw[_lastUsedAtField] is int ? raw[_lastUsedAtField] as int : 0;

      if (lastUsedAt < cutoff) {
        await _prefs.remove(_key(broadcasterId));
        removedCount++;
      } else {
        remaining.add(broadcasterId);
      }
    }

    await _prefs.setString(_indexKey, json.encode(remaining));
    return removedCount;
  }

  Map<String, dynamic> _readRaw(String broadcasterId) {
    final String? rawStr = _prefs.getString(_key(broadcasterId));
    if (rawStr == null || rawStr.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return json.decode(rawStr) as Map<String, dynamic>;
    } on Object {
      return <String, dynamic>{};
    }
  }

  Map<String, int> _extractColors(Map<String, dynamic> raw) {
    final Map<String, int> result = <String, int>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      if (entry.key == _lastUsedAtField) {
        continue;
      }
      if (entry.value is int) {
        result[entry.key] = entry.value as int;
      }
    }
    return result;
  }

  Future<void> _touchLastUsedAt(
    String broadcasterId,
    Map<String, dynamic> raw,
  ) async {
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_key(broadcasterId), json.encode(raw));
    await _addToIndex(broadcasterId);
  }

  List<String> _readIndex() {
    final String? rawStr = _prefs.getString(_indexKey);
    if (rawStr == null || rawStr.isEmpty) {
      return <String>[];
    }
    try {
      final List<dynamic> decoded = json.decode(rawStr) as List<dynamic>;
      return decoded.cast<String>().toList();
    } on Object {
      return <String>[];
    }
  }

  Future<void> _addToIndex(String broadcasterId) async {
    final List<String> index = _readIndex();
    if (index.contains(broadcasterId)) {
      return;
    }
    index.add(broadcasterId);
    await _prefs.setString(_indexKey, json.encode(index));
  }
}
