import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';

void main() {
  group('OAuthAuthorizationState JSON round-trip', () {
    test('toJson / fromJson preserves value and timestamp', () {
      const original = OAuthAuthorizationState(
        value: 'random-state-abc',
        createdAtMillisSinceEpoch: 1714600000000,
      );
      final restored = OAuthAuthorizationState.fromJson(original.toJson());
      expect(restored.value, original.value);
      expect(
        restored.createdAtMillisSinceEpoch,
        original.createdAtMillisSinceEpoch,
      );
    });
  });

  group('OAuthTokens', () {
    test('fromUpstreamJson parses a typical RFC 6749 success response', () {
      final tokens = OAuthTokens.fromUpstreamJson(<String, Object?>{
        'access_token': 'a',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'refresh_token': 'r',
        'scope': 'openid user',
      });
      expect(tokens.accessToken, 'a');
      expect(tokens.tokenType, 'Bearer');
      expect(tokens.expiresInSeconds, 3600);
      expect(tokens.refreshToken, 'r');
      expect(tokens.scope, 'openid user');
    });

    test('fromUpstreamJson defaults token_type to Bearer when omitted', () {
      final tokens = OAuthTokens.fromUpstreamJson(<String, Object?>{
        'access_token': 'a',
        'expires_in': 3600,
      });
      expect(tokens.tokenType, 'Bearer');
    });

    test('fromUpstreamJson tolerates missing expires_in (defaults to 0)', () {
      final tokens = OAuthTokens.fromUpstreamJson(<String, Object?>{
        'access_token': 'a',
        'token_type': 'Bearer',
      });
      expect(tokens.expiresInSeconds, 0);
    });

    test('fromUpstreamJson throws when access_token is missing', () {
      expect(
        () => OAuthTokens.fromUpstreamJson(const <String, Object?>{
          'token_type': 'Bearer',
          'expires_in': 3600,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('toJson / fromJson round-trip preserves optional null fields', () {
      const tokens = OAuthTokens(
        accessToken: 'a',
        tokenType: 'Bearer',
        expiresInSeconds: 3600,
      );
      final restored = OAuthTokens.fromJson(tokens.toJson());
      expect(restored.accessToken, 'a');
      expect(restored.refreshToken, isNull);
      expect(restored.scope, isNull);
    });
  });

  group('OAuthFailure', () {
    test('toString includes reason name and HTTP status when present', () {
      const failure = OAuthFailure(
        reason: OAuthFailureReason.tokenExchangeFailed,
        message: 'BFF returned 502',
        httpStatus: 502,
        upstreamError: 'upstream_unreachable',
      );
      final s = failure.toString();
      expect(s, contains('tokenExchangeFailed'));
      expect(s, contains('HTTP 502'));
      expect(s, contains('upstream_unreachable'));
    });
  });
}
