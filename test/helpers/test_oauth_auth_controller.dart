import 'package:http/testing.dart';

import 'package:comerune/application/auth/oauth_auth_controller.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_auth_service.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_client.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_config.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_generator.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_store.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_token_store.dart';

import 'in_memory_oauth_token_store.dart';

export 'in_memory_oauth_token_store.dart';

/// Test helper: builds an [OAuthAuthController] backed by in-memory stores
/// and a MockClient that fails any unexpected HTTP call. Pass [tokenStore]
/// to inspect or seed the stored tokens.
///
/// Default config has all three values empty, so
/// [OAuthAuthController.isFullyConfigured] returns false and OAuth UI
/// entry points stay hidden in widget tests that do not exercise the
/// flow. Callers needing the configured branch can pass a custom [config].
OAuthAuthController buildTestOAuthAuthController({
  OAuthBffConfig? config,
  OAuthTokenStore? tokenStore,
}) {
  final OAuthBffConfig effectiveConfig =
      config ??
      const OAuthBffConfig(
        clientId: '',
        authorizeEndpoint: '',
        bffTokenEndpoint: '',
        redirectUri: '',
        scope: 'openid user',
      );
  final service = OAuthBffAuthService(
    config: effectiveConfig,
    stateGenerator: SecureOAuthStateGenerator(),
    stateStore: _InMemoryStateStore(),
    tokenStore: tokenStore ?? InMemoryOAuthTokenStore(),
    bffClient: OAuthBffClient(
      tokenEndpoint: effectiveConfig.bffTokenEndpoint,
      httpClient: MockClient(
        (_) async => throw StateError(
          'OAuthBffClient must not be called in this widget test',
        ),
      ),
    ),
  );
  return OAuthAuthController(service: service);
}

class _InMemoryStateStore implements OAuthStateStore {
  OAuthAuthorizationState? _v;

  @override
  Future<void> save(OAuthAuthorizationState state) async => _v = state;

  @override
  Future<OAuthAuthorizationState?> read() async => _v;

  @override
  Future<void> clear() async => _v = null;
}
