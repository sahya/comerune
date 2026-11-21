import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_token_store.dart';

/// In-memory [OAuthTokenStore] for tests.
class InMemoryOAuthTokenStore implements OAuthTokenStore {
  OAuthTokens? _v;

  @override
  Future<void> save(OAuthTokens tokens) async => _v = tokens;

  @override
  Future<OAuthTokens?> read() async => _v;

  @override
  Future<void> clear() async => _v = null;
}

/// [OAuthTokenStore] whose [clear] fails, to test that a failed token
/// deletion is handled (e.g. logout still completes).
class ClearThrowingOAuthTokenStore extends InMemoryOAuthTokenStore {
  @override
  Future<void> clear() async =>
      throw StateError('secure_storage delete failed');
}
