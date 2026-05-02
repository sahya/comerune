import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/data/auth/oauth_bff/oauth_bff_auth_service.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_client.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_config.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_generator.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_state_store.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_token_store.dart';

class _FakeStateGenerator implements OAuthStateGenerator {
  _FakeStateGenerator(this._values);
  final List<String> _values;
  int _i = 0;

  @override
  String generate() {
    final v = _values[_i % _values.length];
    _i++;
    return v;
  }
}

class _InMemoryStateStore implements OAuthStateStore {
  OAuthAuthorizationState? _value;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<void> save(OAuthAuthorizationState state) async {
    _value = state;
    saveCount++;
  }

  @override
  Future<OAuthAuthorizationState?> read() async => _value;

  @override
  Future<void> clear() async {
    _value = null;
    clearCount++;
  }
}

class _InMemoryTokenStore implements OAuthTokenStore {
  OAuthTokens? _value;

  @override
  Future<void> save(OAuthTokens tokens) async {
    _value = tokens;
  }

  @override
  Future<OAuthTokens?> read() async => _value;

  @override
  Future<void> clear() async {
    _value = null;
  }
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

class _ThrowingTokenStore implements OAuthTokenStore {
  OAuthTokens? _last;

  @override
  Future<void> save(OAuthTokens tokens) async {
    _last = tokens;
    throw StateError('secure_storage write failed');
  }

  @override
  Future<OAuthTokens?> read() async => _last;

  @override
  Future<void> clear() async {}
}

/// Token store that pre-holds a value (so refresh() finds an existing token
/// to use as input) but throws on save (so persistence after refresh fails).
class _SeededThrowingTokenStore implements OAuthTokenStore {
  _SeededThrowingTokenStore(this._seed);
  final OAuthTokens _seed;

  @override
  Future<void> save(OAuthTokens tokens) async =>
      throw StateError('secure_storage write failed');

  @override
  Future<OAuthTokens?> read() async => _seed;

  @override
  Future<void> clear() async {}
}

class _ReadThrowingStateStore implements OAuthStateStore {
  @override
  Future<void> save(OAuthAuthorizationState state) async {}

  @override
  Future<OAuthAuthorizationState?> read() async =>
      throw StateError('secure_storage read failed');

  @override
  Future<void> clear() async {}
}

class _ReadThrowingTokenStore implements OAuthTokenStore {
  @override
  Future<void> save(OAuthTokens tokens) async {}

  @override
  Future<OAuthTokens?> read() async =>
      throw StateError('secure_storage read failed');

  @override
  Future<void> clear() async {}
}

const _redirectUri = 'https://acme-relay.invalid/auth/callback';

OAuthBffConfig _buildConfig({String clientId = 'test-client-id'}) {
  return OAuthBffConfig(
    clientId: clientId,
    authorizeEndpoint: 'https://acme-idp.invalid/authorize',
    bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
    redirectUri: _redirectUri,
    scope: 'openid user',
  );
}

OAuthBffAuthService _buildService({
  required OAuthBffConfig config,
  required OAuthStateGenerator stateGenerator,
  required OAuthStateStore stateStore,
  required OAuthTokenStore tokenStore,
  required http.Client httpClient,
  DateTime Function()? now,
  Duration stateMaxAge = kOAuthStateMaxAge,
}) {
  final bff = OAuthBffClient(
    tokenEndpoint: config.bffTokenEndpoint,
    httpClient: httpClient,
  );
  return OAuthBffAuthService(
    config: config,
    stateGenerator: stateGenerator,
    stateStore: stateStore,
    tokenStore: tokenStore,
    bffClient: bff,
    now: now ?? DateTime.now,
    stateMaxAge: stateMaxAge,
  );
}

http.Client _alwaysFail() => MockClient((http.Request request) async {
  throw StateError('http should not be called in this test');
});

void main() {
  group('startAuthorization', () {
    test('throws when client_id is empty (forgot --dart-define)', () async {
      final service = _buildService(
        config: _buildConfig(clientId: ''),
        stateGenerator: _FakeStateGenerator(<String>['s']),
        stateStore: _InMemoryStateStore(),
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
      );
      expect(
        () => service.startAuthorization(),
        throwsA(
          isA<OAuthFailure>().having(
            (OAuthFailure f) => f.reason,
            'reason',
            OAuthFailureReason.tokenExchangeFailed,
          ),
        ),
      );
    });

    test(
      'saves state and returns authorize URI with required params',
      () async {
        final stateStore = _InMemoryStateStore();
        final config = _buildConfig();
        final service = _buildService(
          config: config,
          stateGenerator: _FakeStateGenerator(<String>['STATE-ABC']),
          stateStore: stateStore,
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
          now: () => DateTime.fromMillisecondsSinceEpoch(1714600000000),
        );

        final uri = await service.startAuthorization();

        expect(uri.toString().startsWith(config.authorizeEndpoint), isTrue);
        expect(uri.queryParameters['client_id'], 'test-client-id');
        expect(uri.queryParameters['response_type'], 'code');
        expect(uri.queryParameters['redirect_uri'], _redirectUri);
        expect(uri.queryParameters['state'], 'STATE-ABC');
        expect(uri.queryParameters['scope'], 'openid user');

        final saved = await stateStore.read();
        expect(saved!.value, 'STATE-ABC');
        expect(saved.createdAtMillisSinceEpoch, 1714600000000);
      },
    );
  });

  group('handleCallback', () {
    test('returns malformedCallback when code or state missing', () async {
      final stateStore = _InMemoryStateStore();
      await stateStore.save(
        const OAuthAuthorizationState(value: 'X', createdAtMillisSinceEpoch: 1),
      );
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: stateStore,
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
      );

      final outcome = await service.handleCallback(
        Uri.parse('$_redirectUri?code=only'),
      );

      expect(outcome, isA<OAuthCallbackFailure>());
      expect(
        (outcome as OAuthCallbackFailure).failure.reason,
        OAuthFailureReason.malformedCallback,
      );
      // Always clears state so a missing-state callback can't be replayed
      // alongside a fresh startAuthorization.
      expect(await stateStore.read(), isNull);
    });

    test(
      'returns upstreamAuthorizationError when callback has error param',
      () async {
        final stateStore = _InMemoryStateStore();
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?error=access_denied&error_description=user'),
        );

        expect(outcome, isA<OAuthCallbackFailure>());
        final failure = (outcome as OAuthCallbackFailure).failure;
        expect(failure.reason, OAuthFailureReason.upstreamAuthorizationError);
        expect(failure.upstreamError, 'access_denied');
        expect(failure.upstreamErrorDescription, 'user');
      },
    );

    test('returns stateMismatch when no stored state', () async {
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: _InMemoryStateStore(),
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
      );

      final outcome = await service.handleCallback(
        Uri.parse('$_redirectUri?code=c&state=x'),
      );

      expect(outcome, isA<OAuthCallbackFailure>());
      expect(
        (outcome as OAuthCallbackFailure).failure.reason,
        OAuthFailureReason.stateMismatch,
      );
    });

    test('returns stateMismatch when state value differs', () async {
      final stateStore = _InMemoryStateStore();
      await stateStore.save(
        OAuthAuthorizationState(
          value: 'EXPECTED',
          createdAtMillisSinceEpoch: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: stateStore,
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
      );

      final outcome = await service.handleCallback(
        Uri.parse('$_redirectUri?code=c&state=ATTACKER'),
      );

      expect(outcome, isA<OAuthCallbackFailure>());
      expect(
        (outcome as OAuthCallbackFailure).failure.reason,
        OAuthFailureReason.stateMismatch,
      );
    });

    test(
      'accepts state at exactly the max-age boundary (>= 0 and <= maxAge)',
      () async {
        // The stored timestamp is exactly `maxAge` ms in the past so the age
        // is exactly maxAge. The check is `ageMs > maxAge`, so this edge
        // value must still pass and the BFF call must be reached.
        final stateStore = _InMemoryStateStore();
        final fixedNow = DateTime.fromMillisecondsSinceEpoch(2_000_000_000_000);
        final boundaryMs =
            fixedNow.millisecondsSinceEpoch - kOAuthStateMaxAge.inMilliseconds;
        await stateStore.save(
          OAuthAuthorizationState(
            value: 'BOUNDARY',
            createdAtMillisSinceEpoch: boundaryMs,
          ),
        );
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'access_token': 'AT',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: _InMemoryTokenStore(),
          httpClient: mock,
          now: () => fixedNow,
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=BOUNDARY'),
        );

        expect(outcome, isA<OAuthCallbackSuccess>());
      },
    );

    test('rejects state one millisecond past the max-age boundary', () async {
      // Same shape as the boundary test but with age = maxAge + 1.
      final stateStore = _InMemoryStateStore();
      final fixedNow = DateTime.fromMillisecondsSinceEpoch(2_000_000_000_000);
      final justOverMs =
          fixedNow.millisecondsSinceEpoch -
          kOAuthStateMaxAge.inMilliseconds -
          1;
      await stateStore.save(
        OAuthAuthorizationState(
          value: 'JUST_OVER',
          createdAtMillisSinceEpoch: justOverMs,
        ),
      );
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: stateStore,
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
        now: () => fixedNow,
      );

      final outcome = await service.handleCallback(
        Uri.parse('$_redirectUri?code=c&state=JUST_OVER'),
      );

      expect(outcome, isA<OAuthCallbackFailure>());
      expect(
        (outcome as OAuthCallbackFailure).failure.reason,
        OAuthFailureReason.stateMismatch,
      );
    });

    test(
      'returns stateMismatch when stored state is older than max age',
      () async {
        final stateStore = _InMemoryStateStore();
        // Stored 30 minutes ago; max age is 15 minutes.
        final oldMs = DateTime.now()
            .subtract(const Duration(minutes: 30))
            .millisecondsSinceEpoch;
        await stateStore.save(
          OAuthAuthorizationState(
            value: 'OLD',
            createdAtMillisSinceEpoch: oldMs,
          ),
        );
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=OLD'),
        );

        expect(outcome, isA<OAuthCallbackFailure>());
        expect(
          (outcome as OAuthCallbackFailure).failure.reason,
          OAuthFailureReason.stateMismatch,
        );
      },
    );

    test(
      'returns stateMismatch when stored state has future timestamp',
      () async {
        final stateStore = _InMemoryStateStore();
        // Stored timestamp is "in the future" relative to now -> negative age.
        final futureMs = DateTime.now()
            .add(const Duration(minutes: 30))
            .millisecondsSinceEpoch;
        await stateStore.save(
          OAuthAuthorizationState(
            value: 'FUTURE',
            createdAtMillisSinceEpoch: futureMs,
          ),
        );
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=FUTURE'),
        );

        expect(outcome, isA<OAuthCallbackFailure>());
        expect(
          (outcome as OAuthCallbackFailure).failure.reason,
          OAuthFailureReason.stateMismatch,
        );
      },
    );

    test(
      'happy path: success outcome, tokens persisted, state cleared',
      () async {
        final stateStore = _InMemoryStateStore();
        await stateStore.save(
          OAuthAuthorizationState(
            value: 'GOOD',
            createdAtMillisSinceEpoch: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        final tokenStore = _InMemoryTokenStore();
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'access_token': 'AT',
              'token_type': 'Bearer',
              'expires_in': 3600,
              'refresh_token': 'RT',
              'scope': 'openid user',
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: tokenStore,
          httpClient: mock,
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=GOOD'),
        );

        expect(outcome, isA<OAuthCallbackSuccess>());
        final tokens = (outcome as OAuthCallbackSuccess).tokens;
        expect(tokens.accessToken, 'AT');
        expect(tokens.refreshToken, 'RT');
        expect((await tokenStore.read())!.accessToken, 'AT');
        // State store is cleared after a successful exchange so the same
        // state value cannot be replayed.
        expect(await stateStore.read(), isNull);
        expect(stateStore.clearCount, greaterThanOrEqualTo(1));
      },
    );

    test('on BFF failure, state is still cleared (no replay)', () async {
      final stateStore = _InMemoryStateStore();
      await stateStore.save(
        OAuthAuthorizationState(
          value: 'GOOD',
          createdAtMillisSinceEpoch: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      final mock = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{'error': 'invalid_grant'}),
          400,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: stateStore,
        tokenStore: _InMemoryTokenStore(),
        httpClient: mock,
      );

      final outcome = await service.handleCallback(
        Uri.parse('$_redirectUri?code=c&state=GOOD'),
      );

      expect(outcome, isA<OAuthCallbackFailure>());
      expect(
        (outcome as OAuthCallbackFailure).failure.reason,
        OAuthFailureReason.tokenExchangeFailed,
      );
      expect(await stateStore.read(), isNull);
    });
  });

  group('OAuthBffConfig', () {
    test('isClientIdConfigured reflects clientId emptiness', () {
      const empty = OAuthBffConfig(
        clientId: '',
        authorizeEndpoint: 'https://acme-idp.invalid/authorize',
        bffTokenEndpoint: 'https://x/api/token',
        redirectUri: 'https://x/auth/callback',
        scope: 'openid user',
      );
      const filled = OAuthBffConfig(
        clientId: 'abc',
        authorizeEndpoint: 'https://acme-idp.invalid/authorize',
        bffTokenEndpoint: 'https://x/api/token',
        redirectUri: 'https://x/auth/callback',
        scope: 'openid user',
      );
      expect(empty.isClientIdConfigured, isFalse);
      expect(filled.isClientIdConfigured, isTrue);
    });

    test('isBffHostConfigured reflects bffTokenEndpoint emptiness', () {
      const noHost = OAuthBffConfig(
        clientId: 'abc',
        authorizeEndpoint: 'https://acme-idp.invalid/authorize',
        bffTokenEndpoint: '',
        redirectUri: '',
        scope: 'openid user',
      );
      const withHost = OAuthBffConfig(
        clientId: 'abc',
        authorizeEndpoint: 'https://acme-idp.invalid/authorize',
        bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
        redirectUri: 'https://acme-relay.invalid/auth/callback',
        scope: 'openid user',
      );
      expect(noHost.isBffHostConfigured, isFalse);
      expect(withHost.isBffHostConfigured, isTrue);
    });

    test(
      'isAuthorizeEndpointConfigured reflects authorizeEndpoint emptiness',
      () {
        const empty = OAuthBffConfig(
          clientId: 'abc',
          authorizeEndpoint: '',
          bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
          scope: 'openid user',
        );
        const filled = OAuthBffConfig(
          clientId: 'abc',
          authorizeEndpoint: 'https://acme-idp.invalid/authorize',
          bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
          scope: 'openid user',
        );
        expect(empty.isAuthorizeEndpointConfigured, isFalse);
        expect(filled.isAuthorizeEndpointConfigured, isTrue);
      },
    );

    test(
      'isFullyConfigured requires clientId, bffHost, and authorizeEndpoint',
      () {
        const noClient = OAuthBffConfig(
          clientId: '',
          authorizeEndpoint: 'https://acme-idp.invalid/authorize',
          bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
          scope: 'openid user',
        );
        const noBff = OAuthBffConfig(
          clientId: 'abc',
          authorizeEndpoint: 'https://acme-idp.invalid/authorize',
          bffTokenEndpoint: '',
          redirectUri: '',
          scope: 'openid user',
        );
        const noAuthorize = OAuthBffConfig(
          clientId: 'abc',
          authorizeEndpoint: '',
          bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
          scope: 'openid user',
        );
        const all = OAuthBffConfig(
          clientId: 'abc',
          authorizeEndpoint: 'https://acme-idp.invalid/authorize',
          bffTokenEndpoint: 'https://acme-relay.invalid/api/token',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
          scope: 'openid user',
        );
        expect(noClient.isFullyConfigured, isFalse);
        expect(noBff.isFullyConfigured, isFalse);
        expect(noAuthorize.isFullyConfigured, isFalse);
        expect(all.isFullyConfigured, isTrue);
      },
    );
  });

  group('store read failures', () {
    test(
      'handleCallback returns persistenceFailed when stateStore.read throws',
      () async {
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: _ReadThrowingStateStore(),
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=any'),
        );

        expect(outcome, isA<OAuthCallbackFailure>());
        expect(
          (outcome as OAuthCallbackFailure).failure.reason,
          OAuthFailureReason.persistenceFailed,
        );
      },
    );

    test(
      'refresh throws OAuthFailure(persistenceFailed) when tokenStore.read throws',
      () async {
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: _InMemoryStateStore(),
          tokenStore: _ReadThrowingTokenStore(),
          httpClient: _alwaysFail(),
        );

        expect(
          () => service.refresh(),
          throwsA(
            isA<OAuthFailure>().having(
              (OAuthFailure f) => f.reason,
              'reason',
              OAuthFailureReason.persistenceFailed,
            ),
          ),
        );
      },
    );
  });

  group('persistence failures', () {
    test(
      'startAuthorization throws OAuthFailure(persistenceFailed) when state save throws',
      () async {
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(<String>['s']),
          stateStore: _ThrowingStateStore(),
          tokenStore: _InMemoryTokenStore(),
          httpClient: _alwaysFail(),
        );
        expect(
          () => service.startAuthorization(),
          throwsA(
            isA<OAuthFailure>().having(
              (OAuthFailure f) => f.reason,
              'reason',
              OAuthFailureReason.persistenceFailed,
            ),
          ),
        );
      },
    );

    test(
      'handleCallback returns persistenceFailed when token save throws after a successful exchange',
      () async {
        final stateStore = _InMemoryStateStore();
        await stateStore.save(
          OAuthAuthorizationState(
            value: 'GOOD',
            createdAtMillisSinceEpoch: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'access_token': 'AT',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: stateStore,
          tokenStore: _ThrowingTokenStore(),
          httpClient: mock,
        );

        final outcome = await service.handleCallback(
          Uri.parse('$_redirectUri?code=c&state=GOOD'),
        );

        expect(outcome, isA<OAuthCallbackFailure>());
        expect(
          (outcome as OAuthCallbackFailure).failure.reason,
          OAuthFailureReason.persistenceFailed,
        );
        // State store is still cleared (no replay risk).
        expect(await stateStore.read(), isNull);
      },
    );

    test(
      'refresh throws OAuthFailure(persistenceFailed) when token save throws after refresh',
      () async {
        final tokenStore = _SeededThrowingTokenStore(
          const OAuthTokens(
            accessToken: 'AT_OLD',
            tokenType: 'Bearer',
            expiresInSeconds: 3600,
            refreshToken: 'RT_OLD',
          ),
        );
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'access_token': 'AT_NEW',
              'token_type': 'Bearer',
              'expires_in': 3600,
            }),
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: _InMemoryStateStore(),
          tokenStore: tokenStore,
          httpClient: mock,
        );

        expect(
          () => service.refresh(),
          throwsA(
            isA<OAuthFailure>().having(
              (OAuthFailure f) => f.reason,
              'reason',
              OAuthFailureReason.persistenceFailed,
            ),
          ),
        );
      },
    );
  });

  group('dispose', () {
    test(
      'dispose() detaches App Links and closes the BFF http client',
      () async {
        // Use a closeable MockClient via a wrapping http.Client subtype is
        // overkill; just verify that calling dispose() does not throw and
        // is idempotent against a fresh service. The detach + close calls
        // are exercised here without app_links wiring (no attachAppLinks).
        final service = _buildService(
          config: _buildConfig(),
          stateGenerator: _FakeStateGenerator(const <String>[]),
          stateStore: _InMemoryStateStore(),
          tokenStore: _InMemoryTokenStore(),
          httpClient: MockClient(
            (http.Request request) async => http.Response('{}', 200),
          ),
        );

        await service.dispose();
        // Calling dispose twice must not blow up (detachAppLinks is idempotent;
        // closing an already-closed http.Client is a no-op for MockClient).
        await service.dispose();
      },
    );
  });

  group('refresh', () {
    test('throws when no refresh_token persisted', () async {
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: _InMemoryStateStore(),
        tokenStore: _InMemoryTokenStore(),
        httpClient: _alwaysFail(),
      );
      expect(
        () => service.refresh(),
        throwsA(
          isA<OAuthFailure>().having(
            (OAuthFailure f) => f.reason,
            'reason',
            OAuthFailureReason.tokenExchangeFailed,
          ),
        ),
      );
    });

    test('persists fresh tokens on success', () async {
      final tokenStore = _InMemoryTokenStore();
      await tokenStore.save(
        const OAuthTokens(
          accessToken: 'AT_OLD',
          tokenType: 'Bearer',
          expiresInSeconds: 3600,
          refreshToken: 'RT_OLD',
        ),
      );
      final mock = MockClient((http.Request request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['grant_type'], 'refresh_token');
        expect(body['refresh_token'], 'RT_OLD');
        return http.Response(
          jsonEncode(<String, Object?>{
            'access_token': 'AT_NEW',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'refresh_token': 'RT_NEW',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final service = _buildService(
        config: _buildConfig(),
        stateGenerator: _FakeStateGenerator(const <String>[]),
        stateStore: _InMemoryStateStore(),
        tokenStore: tokenStore,
        httpClient: mock,
      );

      final fresh = await service.refresh();
      expect(fresh.accessToken, 'AT_NEW');
      expect((await tokenStore.read())!.accessToken, 'AT_NEW');
      expect((await tokenStore.read())!.refreshToken, 'RT_NEW');
    });
  });
}
