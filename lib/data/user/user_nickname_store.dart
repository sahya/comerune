import 'dart:convert';

import '../../application/settings/settings_store.dart';

/// Persists user nickname (コテハン) mappings globally.
///
/// Nicknames are stored as a JSON map of user IDs to nickname strings.
/// Unlike [UserColorStore], nicknames are not scoped by broadcaster —
/// they are global across all broadcasts.
abstract class UserNicknameStore {
  /// Returns the nickname map for all registered users.
  ///
  /// Keys are user IDs, values are nickname strings.
  Future<Map<String, String>> loadAll();

  /// Sets a nickname for a user.
  Future<void> setNickname({
    required String userId,
    required String nickname,
  });

  /// Removes the nickname for a user.
  Future<void> removeNickname(String userId);
}

class SharedPreferencesUserNicknameStore implements UserNicknameStore {
  const SharedPreferencesUserNicknameStore({
    required SharedPreferencesLike prefs,
  }) : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _key = 'user_nicknames';

  @override
  Future<Map<String, String>> loadAll() async {
    final Map<String, dynamic> raw = _readRaw();
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, dynamic> entry in raw.entries) {
      if (entry.value is String) {
        result[entry.key] = entry.value as String;
      }
    }
    return result;
  }

  @override
  Future<void> setNickname({
    required String userId,
    required String nickname,
  }) async {
    final Map<String, dynamic> raw = _readRaw();
    raw[userId] = nickname;
    await _prefs.setString(_key, json.encode(raw));
  }

  @override
  Future<void> removeNickname(String userId) async {
    final Map<String, dynamic> raw = _readRaw();
    if (!raw.containsKey(userId)) {
      return;
    }
    raw.remove(userId);
    await _prefs.setString(_key, json.encode(raw));
  }

  Map<String, dynamic> _readRaw() {
    final String? rawStr = _prefs.getString(_key);
    if (rawStr == null || rawStr.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return json.decode(rawStr) as Map<String, dynamic>;
    } on Object {
      return <String, dynamic>{};
    }
  }
}
