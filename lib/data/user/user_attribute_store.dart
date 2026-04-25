import 'dart:convert';

import '../../application/settings/settings_store.dart';

/// Snapshot of all per-user attributes for a single broadcaster, returned
/// by [UserAttributeStore.loadAttributes].
///
/// Defined as a typedef over a Record so that callers and implementations
/// share a stable type name. Adding a new field in the future only requires
/// updating this typedef and the implementations — call-sites that destructure
/// known fields keep working.
typedef UserAttributesSnapshot = ({
  Map<String, int> colors,
  Map<String, String> nicknames,
});

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
  ///
  /// New code should prefer [loadAttributes] over calling [loadColors] and
  /// [loadNicknames] back-to-back: a single combined call halves the
  /// underlying I/O (one read + one `_lastUsedAt` write instead of two of
  /// each). [loadColors] is retained for backward compatibility.
  Future<Map<String, int>> loadColors(String broadcasterId);

  /// Returns the nickname map for all users under the given broadcaster.
  ///
  /// Keys are user IDs, values are nickname strings.
  ///
  /// New code should prefer [loadAttributes] over calling [loadColors] and
  /// [loadNicknames] back-to-back: a single combined call halves the
  /// underlying I/O. [loadNicknames] is retained for backward compatibility.
  Future<Map<String, String>> loadNicknames(String broadcasterId);

  /// Loads colors and nicknames in a single I/O round-trip.
  ///
  /// **New call-sites should use [loadAttributes] instead of calling
  /// [loadColors] and [loadNicknames] separately.** The legacy two-call
  /// pattern is retained only for backward compatibility.
  ///
  /// Implementations must read the underlying storage only once and update
  /// `_lastUsedAt` only once. The returned tuple is equivalent to calling
  /// [loadColors] and [loadNicknames] back-to-back, but avoids the duplicate
  /// read and the duplicate fsynced write that the two-call sequence would
  /// otherwise perform.
  ///
  /// Because both fields are derived from the same raw snapshot, internal
  /// consistency between `colors` and `nicknames` is guaranteed (no torn
  /// read can interleave a concurrent mutation between the two extractions).
  Future<UserAttributesSnapshot> loadAttributes(String broadcasterId);

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

  /// Waits for any in-flight persistence writes to complete.
  ///
  /// Implementations that write synchronously may return immediately.
  Future<void> flushPendingWrites();
}

class SharedPreferencesUserAttributeStore implements UserAttributeStore {
  SharedPreferencesUserAttributeStore({required SharedPreferencesLike prefs})
    : _prefs = prefs;

  final SharedPreferencesLike _prefs;
  Future<void> _pendingWriteChain = Future<void>.value();

  static const String _indexKey = 'usercolor._index';
  static const String _lastUsedAtField = userAttrLastUsedAtField;

  // Keep the same key prefix for backward compatibility with existing data.
  static String _key(String broadcasterId) => 'usercolor.$broadcasterId';

  @override
  Future<Map<String, int>> loadColors(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return <String, int>{};
    }
    await _touchLastUsedAt(broadcasterId);
    return extractColors(raw);
  }

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return <String, String>{};
    }
    await _touchLastUsedAt(broadcasterId);
    return extractNicknames(raw);
  }

  @override
  Future<UserAttributesSnapshot> loadAttributes(String broadcasterId) async {
    final Map<String, dynamic> raw = _readRaw(broadcasterId);
    if (raw.isEmpty) {
      return (colors: <String, int>{}, nicknames: <String, String>{});
    }
    await _touchLastUsedAt(broadcasterId);
    return (colors: extractColors(raw), nicknames: extractNicknames(raw));
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    await _enqueueWrite(() async {
      final Map<String, dynamic> raw = _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      final UserEntry updated = existing.copyWith(color: colorValue);
      raw[userId] = updated.toJson();
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setString(_key(broadcasterId), json.encode(raw));
      await _addToIndex(broadcasterId);
    });
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    await _enqueueWrite(() async {
      final Map<String, dynamic> raw = _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      if (existing.color == null) {
        return;
      }
      final UserEntry updated = existing.copyWithoutColor();
      if (updated.isEmpty) {
        raw.remove(userId);
      } else {
        raw[userId] = updated.toJson();
      }
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setString(_key(broadcasterId), json.encode(raw));
    });
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {
    await _enqueueWrite(() async {
      final Map<String, dynamic> raw = _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      final UserEntry updated = existing.copyWith(nickname: nickname);
      raw[userId] = updated.toJson();
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setString(_key(broadcasterId), json.encode(raw));
      await _addToIndex(broadcasterId);
    });
  }

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) async {
    await _enqueueWrite(() async {
      final Map<String, dynamic> raw = _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      if (existing.nickname == null) {
        return;
      }
      final UserEntry updated = existing.copyWithoutNickname();
      if (updated.isEmpty) {
        raw.remove(userId);
      } else {
        raw[userId] = updated.toJson();
      }
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setString(_key(broadcasterId), json.encode(raw));
    });
  }

  @override
  Future<void> flushPendingWrites() => _pendingWriteChain;

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    return _enqueueWrite(() async {
      final List<String> index = _readIndex();
      if (index.isEmpty) {
        return 0;
      }

      final int cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      final List<String> remaining = <String>[];
      int removedCount = 0;

      for (final String broadcasterId in index) {
        final Map<String, dynamic> raw = _readRaw(broadcasterId);
        final int lastUsedAt = raw[_lastUsedAtField] is int
            ? raw[_lastUsedAtField] as int
            : 0;

        if (lastUsedAt < cutoff) {
          await _prefs.remove(_key(broadcasterId));
          removedCount++;
        } else {
          remaining.add(broadcasterId);
        }
      }

      await _prefs.setString(_indexKey, json.encode(remaining));
      return removedCount;
    });
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

  Future<void> _touchLastUsedAt(String broadcasterId) async {
    await _enqueueWrite(() async {
      final Map<String, dynamic> latestRaw = _readRaw(broadcasterId);
      if (latestRaw.isEmpty) {
        return;
      }
      latestRaw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _prefs.setString(_key(broadcasterId), json.encode(latestRaw));
      await _addToIndex(broadcasterId);
    });
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

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final Future<T> scheduled = _pendingWriteChain.then<T>((_) => operation());
    _pendingWriteChain = scheduled
        .then<void>((_) {})
        .catchError((Object error, StackTrace stackTrace) {});
    return scheduled;
  }
}

// ---------------------------------------------------------------------------
// Shared helpers — used by FileUserAttributeStore (and available to any
// future UserAttributeStore implementation) so the JSON payload shape
// stays identical across implementations.
// ---------------------------------------------------------------------------

const String userAttrColorField = 'c';
const String userAttrNicknameField = 'n';
const String userAttrLastUsedAtField = '_lastUsedAt';

/// Value object representing a single user's attributes.
class UserEntry {
  const UserEntry({this.color, this.nickname});

  final int? color;
  final String? nickname;

  bool get isEmpty => color == null && nickname == null;

  UserEntry copyWith({int? color, String? nickname}) {
    return UserEntry(
      color: color ?? this.color,
      nickname: nickname ?? this.nickname,
    );
  }

  UserEntry copyWithoutColor() => UserEntry(nickname: nickname);

  UserEntry copyWithoutNickname() => UserEntry(color: color);

  Object toJson() {
    if (nickname == null && color != null) {
      return color!;
    }
    final Map<String, dynamic> map = <String, dynamic>{};
    if (color != null) {
      map[userAttrColorField] = color;
    }
    if (nickname != null) {
      map[userAttrNicknameField] = nickname;
    }
    return map;
  }
}

UserEntry readUserEntry(Map<String, dynamic> raw, String userId) {
  final Object? value = raw[userId];
  if (value == null) {
    return const UserEntry();
  }
  if (value is int) {
    return UserEntry(color: value);
  }
  if (value is Map<String, dynamic>) {
    return UserEntry(
      color: value[userAttrColorField] is int
          ? value[userAttrColorField] as int
          : null,
      nickname: value[userAttrNicknameField] is String
          ? value[userAttrNicknameField] as String
          : null,
    );
  }
  return const UserEntry();
}

Map<String, int> extractColors(Map<String, dynamic> raw) {
  final Map<String, int> result = <String, int>{};
  for (final MapEntry<String, dynamic> entry in raw.entries) {
    if (entry.key == userAttrLastUsedAtField) {
      continue;
    }
    if (entry.value is int) {
      result[entry.key] = entry.value as int;
    } else if (entry.value is Map<String, dynamic>) {
      final Map<String, dynamic> map = entry.value as Map<String, dynamic>;
      if (map[userAttrColorField] is int) {
        result[entry.key] = map[userAttrColorField] as int;
      }
    }
  }
  return result;
}

Map<String, String> extractNicknames(Map<String, dynamic> raw) {
  final Map<String, String> result = <String, String>{};
  for (final MapEntry<String, dynamic> entry in raw.entries) {
    if (entry.key == userAttrLastUsedAtField) {
      continue;
    }
    if (entry.value is Map<String, dynamic>) {
      final Map<String, dynamic> map = entry.value as Map<String, dynamic>;
      if (map[userAttrNicknameField] is String) {
        result[entry.key] = map[userAttrNicknameField] as String;
      }
    }
  }
  return result;
}
