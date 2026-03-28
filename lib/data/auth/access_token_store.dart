import 'dart:developer';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores the OAuth access token separately from general settings.
///
/// Uses SharedPreferences as the underlying storage for now.
/// When flutter_secure_storage is added as a dependency, this class
/// should be updated to use it instead for secure credential storage.
///
/// This abstraction isolates the token storage concern so that:
/// - The token is not mixed into AppSettings
/// - The storage backend can be swapped without changing callers
abstract class AccessTokenStore {
  Future<String> load();
  Future<void> save(String token);
  Future<void> clear();
}

/// SharedPreferences-backed implementation.
///
/// NOTE: SharedPreferences stores data in plaintext. For production use,
/// consider migrating to flutter_secure_storage (Android Keystore / iOS
/// Keychain) once added as a dependency.
class SharedPreferencesAccessTokenStore implements AccessTokenStore {
  SharedPreferencesAccessTokenStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _key = 'auth.accessToken';

  @override
  Future<String> load() async {
    return _prefs.getString(_key) ?? '';
  }

  @override
  Future<void> save(String token) async {
    await _prefs.setString(_key, token);
    log('Access token saved', name: 'AccessTokenStore');
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
    log('Access token cleared', name: 'AccessTokenStore');
  }
}
