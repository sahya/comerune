import 'dart:convert';
import 'dart:developer';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'oauth_bff_models.dart';

/// Stores the in-flight OIDC `state` value across app backgrounding while
/// the user is in the browser. Persisted to secure storage because Android
/// can kill the app process while the browser owns the foreground.
abstract class OAuthStateStore {
  Future<void> save(OAuthAuthorizationState state);
  Future<OAuthAuthorizationState?> read();
  Future<void> clear();
}

class SecureOAuthStateStore implements OAuthStateStore {
  SecureOAuthStateStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const String _key = 'auth.oauth.state';

  @override
  Future<void> save(OAuthAuthorizationState state) async {
    await _secureStorage.write(key: _key, value: jsonEncode(state.toJson()));
  }

  @override
  Future<OAuthAuthorizationState?> read() async {
    final raw = await _secureStorage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return OAuthAuthorizationState.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (e) {
      // Symmetry with OAuthTokenStore: the persisted JSON happens to contain
      // only the state value (anti-CSRF, not a real secret), but logging the
      // raw exception risks leaking that value to dev logs. Log the error
      // type only.
      log(
        'Failed to decode persisted OAuth state, treating as missing '
        '(error type: ${e.runtimeType})',
        name: 'OAuthStateStore',
      );
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: _key);
  }
}
