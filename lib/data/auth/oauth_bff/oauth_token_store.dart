import 'dart:convert';
import 'dart:developer';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'oauth_bff_models.dart';

/// Persists OAuth tokens (access + optional refresh) in secure storage so
/// the app can resume an authenticated session across launches without
/// re-running the full authorization flow.
abstract class OAuthTokenStore {
  Future<void> save(OAuthTokens tokens);
  Future<OAuthTokens?> read();
  Future<void> clear();
}

class SecureOAuthTokenStore implements OAuthTokenStore {
  SecureOAuthTokenStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const String _key = 'auth.oauth.tokens';

  @override
  Future<void> save(OAuthTokens tokens) async {
    await _secureStorage.write(key: _key, value: jsonEncode(tokens.toJson()));
  }

  @override
  Future<OAuthTokens?> read() async {
    final raw = await _secureStorage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return OAuthTokens.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (e) {
      // Do NOT include $e content: jsonDecode exceptions may echo a slice of
      // the corrupt JSON, which for this store contains real access/refresh
      // tokens. Log the error type only.
      log(
        'Failed to decode persisted OAuth tokens, treating as missing '
        '(error type: ${e.runtimeType})',
        name: 'OAuthTokenStore',
      );
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _secureStorage.delete(key: _key);
  }
}
