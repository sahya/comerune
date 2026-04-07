import 'dart:convert';

import '../../application/settings/settings_store.dart';

/// Persists per-user attributes (comment color, nickname, etc.) scoped by
/// broadcaster ID.
///
/// This is the unified store for all per-user customization data.
/// Colors are stored as ARGB32 integer values (see `Color.toARGB32()`).
/// Nicknames are stored as plain strings.
///
/// Each broadcaster entry tracks a `_lastUsedAt` timestamp (milliseconds
/// since epoch). [cleanup] removes entries that have not been accessed
/// for longer than [maxAge].
///
/// **Data format (backward compatible):**
/// ```json
/// {
///   "user1": 0xFFE53935,                         // legacy color-only
///   "user2": {"c": 0xFF1E88E5, "n": "たろう"},   // color + nickname
///   "user3": {"n": "じろう"},                     // nickname only
///   "_lastUsedAt": 1234567890
/// }
/// ```
/// Values that are plain `int` are treated as legacy color-only entries.
/// Values that are `Map` contain optional `"c"` (color) and `"n"` (nickname).
abstract class UserAttributeStore {
  /// Returns the color map for all users under the given broadcaster.
  ///
  /// Keys are user IDs, values are ARGB32 integers.
  Future<Map<String, int>> loadColors(String broadcasterId);

  /// Returns the nickname map for all users under the given broadcaster.
  ///
  /// Keys are user IDs, values are nickname strings.
  Future<Map<String, String>> loadNicknames(String broadcasterId);

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

  /// Sets a nickname for a user under the given broadcaster.
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  });

  /// Removes the nickname for a user under the given broadcaster.
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  });

  /// Removes broadcaster entries that have not been accessed for longer
  /// than [maxAge]. Defaults to 365 days.
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)});
}

class SharedPreferencesUserAttributeStore implements UserAttributeStore {
  const SharedPreferencesUserAttributeStore({
    required SharedPreferencesLike prefs,
  }) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _indexKey = 'usercolor._index';
  static const String _lastUsedAtField = '_lastUsedAt';
  static const String _colorField = 'c';
  static const String _nicknameField = 'n';

  // Keep the same key prefix for backward compatibility with existing data.
  static String _key(String broadcasterId) => 'usercolor.$broadcasterId';

  @override
  Future<Map<String, int>> loadColors(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return <String, int>{};
    }
    await _touchLastUsedAt(broadcasterId, raw);
    return _extractColors(raw);
  }

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return <String, String>{};
    }
    await _touchLastUsedAt(broadcasterId, raw);
    return _extractNicknames(raw);
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    final _UserEntry existing = _readEntry(raw, userId);
    final _UserEntry updated = existing.copyWith(color: colorValue);
    raw[userId] = updated.toJson();
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
    final _UserEntry existing = _readEntry(raw, userId);
    if (existing.color == null) {
      return;
    }
    final _UserEntry updated = existing.copyWithoutColor();
    if (updated.isEmpty) {
      raw.remove(userId);
    } else {
      raw[userId] = updated.toJson();
    }
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_key(broadcasterId), json.encode(raw));
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    final _UserEntry existing = _readEntry(raw, userId);
    final _UserEntry updated = existing.copyWith(nickname: nickname);
    raw[userId] = updated.toJson();
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setString(_key(broadcasterId), json.encode(raw));
    await _addToIndex(broadcasterId);
  }

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    final _UserEntry existing = _readEntry(raw, userId);
    if (existing.nickname == null) {
      return;
    }
    final _UserEntry updated = existing.copyWithoutNickname();
    if (updated.isEmpty) {
      raw.remove(userId);
    } else {
      raw[userId] = updated.toJson();
    }
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

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

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

  /// Reads a single user entry from the raw map, handling both legacy (int)
  /// and new (Map) formats.
  _UserEntry _readEntry(Map<String, dynamic> raw, String userId) {
    final Object? value = raw[userId];
    if (value == null) {
      return const _UserEntry();
    }
    if (value is int) {
      // Legacy format: plain int = color only.
      return _UserEntry(color: value);
    }
    if (value is Map<String, dynamic>) {
      return _UserEntry(
        color: value[_colorField] is int ? value[_colorField] as int : null,
        nickname: value[_nicknameField] is String
            ? value[_nicknameField] as String
            : null,
      );
    }
    return const _UserEntry();
  }

  Map<String, int> _extractColors(Map<String, dynamic> raw) {
    final Map<String, int> result = <String, int>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      if (entry.key == _lastUsedAtField) {
        continue;
      }
      if (entry.value is int) {
        // Legacy format: plain int = color.
        result[entry.key] = entry.value as int;
      } else if (entry.value is Map<String, dynamic>) {
        final Map<String, dynamic> map = entry.value as Map<String, dynamic>;
        if (map[_colorField] is int) {
          result[entry.key] = map[_colorField] as int;
        }
      }
    }
    return result;
  }

  Map<String, String> _extractNicknames(Map<String, dynamic> raw) {
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      if (entry.key == _lastUsedAtField) {
        continue;
      }
      if (entry.value is Map<String, dynamic>) {
        final Map<String, dynamic> map = entry.value as Map<String, dynamic>;
        if (map[_nicknameField] is String) {
          result[entry.key] = map[_nicknameField] as String;
        }
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

/// Internal value object representing a single user's attributes.
class _UserEntry {
  const _UserEntry({this.color, this.nickname});

  final int? color;
  final String? nickname;

  bool get isEmpty => color == null && nickname == null;

  _UserEntry copyWith({int? color, String? nickname}) {
    return _UserEntry(
      color: color ?? this.color,
      nickname: nickname ?? this.nickname,
    );
  }

  _UserEntry copyWithoutColor() {
    return _UserEntry(nickname: nickname);
  }

  _UserEntry copyWithoutNickname() {
    return _UserEntry(color: color);
  }

  /// Serializes to JSON-compatible value.
  ///
  /// If only color is set and no nickname, returns the color int directly
  /// for backward compatibility. Otherwise returns a Map.
  Object toJson() {
    if (nickname == null && color != null) {
      // Backward-compatible format: plain int.
      return color!;
    }
    final Map<String, dynamic> map = <String, dynamic>{};
    if (color != null) {
      map['c'] = color;
    }
    if (nickname != null) {
      map['n'] = nickname;
    }
    return map;
  }
}
