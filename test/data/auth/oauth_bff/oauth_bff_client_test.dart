import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/data/auth/oauth_bff/oauth_bff_client.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';

const String _endpoint = 'https://acme-relay.invalid/api/token';

OAuthBffClient _buildClient(MockClient mockClient) {
  return OAuthBffClient(tokenEndpoint: _endpoint, httpClient: mockClient);
}

void main() {
  group('exchangeAuthorizationCode', () {
    test(
      'posts JSON body with expected fields and parses 200 response',
      () async {
        late http.Request lastRequest;
        final mock = MockClient((http.Request request) async {
          lastRequest = request;
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
        final client = _buildClient(mock);

        final tokens = await client.exchangeAuthorizationCode(
          code: 'auth-code-xyz',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
        );

        expect(lastRequest.method, 'POST');
        expect(lastRequest.url.toString(), _endpoint);
        expect(
          lastRequest.headers['content-type'],
          contains('application/json'),
        );
        final sent = jsonDecode(lastRequest.body) as Map<String, Object?>;
        expect(sent['grant_type'], 'authorization_code');
        expect(sent['code'], 'auth-code-xyz');
        expect(
          sent['redirect_uri'],
          'https://acme-relay.invalid/auth/callback',
        );

        expect(tokens.accessToken, 'AT');
        expect(tokens.refreshToken, 'RT');
      },
    );

    test(
      'throws OAuthFailure(tokenExchangeFailed) on 4xx with error body',
      () async {
        final mock = MockClient((http.Request request) async {
          return http.Response(
            jsonEncode(<String, Object?>{
              'error': 'invalid_grant',
              'error_description': 'expired',
            }),
            400,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final client = _buildClient(mock);

        try {
          await client.exchangeAuthorizationCode(
            code: 'c',
            redirectUri: 'https://acme-relay.invalid/auth/callback',
          );
          fail('Expected OAuthFailure');
        } on OAuthFailure catch (failure) {
          expect(failure.reason, OAuthFailureReason.tokenExchangeFailed);
          expect(failure.httpStatus, 400);
          expect(failure.upstreamError, 'invalid_grant');
          expect(failure.upstreamErrorDescription, 'expired');
        }
      },
    );

    test('throws OAuthFailure(networkFailure) when http throws', () async {
      final mock = MockClient((http.Request request) async {
        throw const _FakeNetworkException();
      });
      final client = _buildClient(mock);

      try {
        await client.exchangeAuthorizationCode(
          code: 'c',
          redirectUri: 'https://acme-relay.invalid/auth/callback',
        );
        fail('Expected OAuthFailure');
      } on OAuthFailure catch (failure) {
        expect(failure.reason, OAuthFailureReason.networkFailure);
      }
    });

    test(
      'throws OAuthFailure(tokenExchangeFailed) on 2xx with non-JSON body',
      () async {
        final mock = MockClient((http.Request request) async {
          return http.Response(
            'not json',
            200,
            headers: <String, String>{'content-type': 'application/json'},
          );
        });
        final client = _buildClient(mock);

        try {
          await client.exchangeAuthorizationCode(
            code: 'c',
            redirectUri: 'https://acme-relay.invalid/auth/callback',
          );
          fail('Expected OAuthFailure');
        } on OAuthFailure catch (failure) {
          expect(failure.reason, OAuthFailureReason.tokenExchangeFailed);
          expect(failure.httpStatus, 200);
        }
      },
    );
  });

  group('exchangeRefreshToken', () {
    test('posts grant_type=refresh_token without code/redirect_uri', () async {
      late http.Request lastRequest;
      final mock = MockClient((http.Request request) async {
        lastRequest = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'access_token': 'AT2',
            'token_type': 'Bearer',
            'expires_in': 3600,
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final client = _buildClient(mock);

      final tokens = await client.exchangeRefreshToken('RT');

      final sent = jsonDecode(lastRequest.body) as Map<String, Object?>;
      expect(sent['grant_type'], 'refresh_token');
      expect(sent['refresh_token'], 'RT');
      expect(sent.containsKey('code'), isFalse);
      expect(sent.containsKey('redirect_uri'), isFalse);
      expect(tokens.accessToken, 'AT2');
    });
  });
}

class _FakeNetworkException implements Exception {
  const _FakeNetworkException();
}
