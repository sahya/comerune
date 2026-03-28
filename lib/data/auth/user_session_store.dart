import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores the niconico user_session cookie value.
///
/// The user_session cookie is obtained when a user logs in to niconico.
/// It is used to authenticate API calls via the X-Niconico-Session header
/// (same approach as N Air, the official niconico streaming tool).
///
/// Uses SharedPreferences as the underlying storage for now.
/// When flutter_secure_storage is added as a dependency, this class
/// should be updated to use it instead for secure credential storage.
abstract class UserSessionStore {
  Future<String> load();
  Future<void> save(String userSession);
  Future<void> clear();
}

/// SharedPreferences-backed implementation.
///
/// NOTE: SharedPreferences stores data in plaintext. For production use,
/// migrate to flutter_secure_storage (Android Keystore / iOS Keychain).
/// See: https://github.com/sahya/comerune/issues/50
class SharedPreferencesUserSessionStore implements UserSessionStore {
  SharedPreferencesUserSessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'auth.userSession';

  @override
  Future<String> load() async {
    return _prefs.getString(_key) ?? '';
  }

  @override
  Future<void> save(String userSession) async {
    await _prefs.setString(_key, userSession);
    log('User session saved', name: 'UserSessionStore');
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
    log('User session cleared', name: 'UserSessionStore');
  }
}
