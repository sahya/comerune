import 'dart:developer';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the niconico user_session cookie value.
///
/// The user_session cookie is obtained when a user logs in to niconico.
/// It is used to authenticate API calls via the X-Niconico-Session header
/// (same approach as N Air, the official niconico streaming tool).
abstract class UserSessionStore {
  Future<String> load();
  Future<void> save(String userSession);
  Future<void> clear();
}

/// Secure storage-backed implementation using flutter_secure_storage.
///
/// Uses Android Keystore on Android and Keychain on iOS for
/// encrypted credential storage. On first use, automatically migrates
/// any existing plaintext session from SharedPreferences.
class SecureUserSessionStore implements UserSessionStore {
  SecureUserSessionStore({
    required SharedPreferences prefs,
    FlutterSecureStorage? secureStorage,
  }) : _prefs = prefs,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  static const String _secureKey = 'auth.userSession';

  /// Legacy key used by the old SharedPreferences-only implementation.
  /// Same key name is reused in secure storage for simplicity.
  static const String _legacyPrefsKey = _secureKey;

  Future<void>? _migrationFuture;

  @override
  Future<String> load() async {
    await (_migrationFuture ??= _doMigrate());
    return await _secureStorage.read(key: _secureKey) ?? '';
  }

  @override
  Future<void> save(String userSession) async {
    await _secureStorage.write(key: _secureKey, value: userSession);
    log('User session saved', name: 'UserSessionStore');
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: _secureKey);
    log('User session cleared', name: 'UserSessionStore');
  }

  /// Migrates from SharedPreferences (plaintext) to secure storage.
  /// Runs at most once per app lifetime. Deletes the legacy key after
  /// successful migration.
  Future<void> _doMigrate() async {
    final String? legacy = _prefs.getString(_legacyPrefsKey);
    if (legacy == null || legacy.isEmpty) {
      return;
    }

    // Check if secure storage already has a value (no need to overwrite)
    final String? existing = await _secureStorage.read(key: _secureKey);
    if (existing != null && existing.isNotEmpty) {
      // Secure storage already has data — just delete legacy
      await _prefs.remove(_legacyPrefsKey);
      log(
        'Removed legacy plaintext session (secure storage already populated)',
        name: 'UserSessionStore',
      );
      return;
    }

    // Migrate: copy to secure storage, then delete from SharedPreferences
    await _secureStorage.write(key: _secureKey, value: legacy);
    await _prefs.remove(_legacyPrefsKey);
    log(
      'Migrated user session from SharedPreferences to secure storage',
      name: 'UserSessionStore',
    );
  }
}
