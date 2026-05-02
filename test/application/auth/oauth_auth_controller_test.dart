import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'package:comerune/application/auth/oauth_auth_controller.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_auth_service.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_client.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_config.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_generator.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_store.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_token_store.dart';

class _FakeStateGenerator implements OAuthStateGenerator {
  _FakeStateGenerator(this._value);
  final String _value;

  @override
  String generate() => _value;
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

class _InMemoryTokenStore implements OAuthTokenStore {
  OAuthTokens? _v;

  @override
  Future<void> save(OAuthTokens tokens) async => _v = tokens;

  @override
  Future<OAuthTokens?> read() async => _v;

  @override
  Future<void> clear() async => _v = null;
}

class _ThrowingStateStore implements OAuthStateStore {
  @override
  Future<void> save(OAuthAuthorizationState state) async =>
      throw StateError('secure_storage write failed');

  @override
  Future<OAuthAuthorizationState?> read() async => null;

  @override
  Future<void> clear() async {}
}

OAuthBffConfig _config({
  String clientId = 'test-client-id',
  String authorizeEndpoint = 'https://acme-idp.invalid/authorize',
  String bffTokenEndpoint = 'https://acme-relay.invalid/api/token',
  String redirectUri = 'https://acme-relay.invalid/auth/callback',
}) => OAuthBffConfig(
  clientId: clientId,
  authorizeEndpoint: authorizeEndpoint,
  bffTokenEndpoint: bffTokenEndpoint,
  redirectUri: redirectUri,
  scope: 'openid user',
);

OAuthAuthController _build({
  required OAuthBffConfig config,
  OAuthStateStore? stateStore,
  OAuthTokenStore? tokenStore,
}) {
  final service = OAuthBffAuthService(
    config: config,
    stateGenerator: _FakeStateGenerator('STATE-X'),
    stateStore: stateStore ?? _InMemoryStateStore(),
    tokenStore: tokenStore ?? _InMemoryTokenStore(),
    bffClient: OAuthBffClient(
      tokenEndpoint: config.bffTokenEndpoint,
      httpClient: MockClient((_) async => throw StateError('no http')),
    ),
  );
  return OAuthAuthController(service: service);
}

void main() {
  group('isFullyConfigured', () {
    test('reflects the underlying config (true case)', () {
      final c = _build(config: _config());
      expect(c.isFullyConfigured, isTrue);
    });

    test('reflects the underlying config (false case: empty clientId)', () {
      final c = _build(config: _config(clientId: ''));
      expect(c.isFullyConfigured, isFalse);
    });

    test('reflects the underlying config (false case: empty bff host)', () {
      final c = _build(
        config: _config(bffTokenEndpoint: '', redirectUri: ''),
      );
      expect(c.isFullyConfigured, isFalse);
    });
  });

  group('startLogin', () {
    test(
      'returns null without invoking the service when build is not configured',
      () async {
        final c = _build(config: _config(clientId: ''));
        final uri = await c.startLogin();
        expect(uri, isNull);
        expect(c.outcome.value, isNull);
      },
    );

    test('returns the authorize URI when configured', () async {
      final c = _build(config: _config());
      final uri = await c.startLogin();
      expect(uri, isNotNull);
      expect(uri!.queryParameters['state'], 'STATE-X');
      expect(uri.queryParameters['client_id'], 'test-client-id');
      expect(uri.queryParameters['response_type'], 'code');
    });

    test(
      'surfaces an OAuthFailure through outcome when state save throws',
      () async {
        final c = _build(config: _config(), stateStore: _ThrowingStateStore());
        final uri = await c.startLogin();
        expect(uri, isNull);
        expect(c.outcome.value, isA<OAuthCallbackFailure>());
        expect(
          (c.outcome.value! as OAuthCallbackFailure).failure.reason,
          OAuthFailureReason.persistenceFailed,
        );
      },
    );
  });
}
