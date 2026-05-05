import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import 'oauth_bff_models.dart';

/// Calls the project's edge BFF (`POST /api/token`) to exchange an
/// authorization code or refresh token for OAuth tokens. The BFF is the
/// only entity that knows the upstream OAuth `client_secret`.
class OAuthBffClient {
  OAuthBffClient({
    required this.tokenEndpoint,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  final String tokenEndpoint;
  final http.Client _httpClient;
  final Duration _timeout;

  /// Exchange an authorization code for tokens.
  Future<OAuthTokens> exchangeAuthorizationCode({
    required String code,
    required String redirectUri,
  }) {
    return _post(<String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
    });
  }

  /// Exchange a refresh token for fresh tokens. The BFF forwards the call
  /// upstream with the server-held `client_secret`.
  Future<OAuthTokens> exchangeRefreshToken(String refreshToken) {
    return _post(<String, String>{
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
  }

  Future<OAuthTokens> _post(Map<String, String> body) async {
    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(tokenEndpoint),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      // Avoid interpolating `$e`: some network exceptions stringify the
      // request body, which contains the authorization code or refresh
      // token. Surface the error type only — matches the convention used
      // for the malformed-JSON branch below.
      log(
        'BFF token endpoint unreachable (error type: ${e.runtimeType})',
        name: 'OAuthBffClient',
      );
      throw const OAuthFailure(
        reason: OAuthFailureReason.networkFailure,
        message: 'Failed to reach BFF token endpoint',
      );
    }

    Map<String, Object?>? jsonBody;
    try {
      jsonBody = jsonDecode(response.body) as Map<String, Object?>;
    } catch (_) {
      // Non-JSON body. Fall through to error handling below.
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (jsonBody == null) {
        throw OAuthFailure(
          reason: OAuthFailureReason.tokenExchangeFailed,
          message: 'BFF returned 2xx with non-JSON body',
          httpStatus: response.statusCode,
        );
      }
      try {
        return OAuthTokens.fromUpstreamJson(jsonBody);
      } catch (e) {
        // Do NOT include $e content: type-cast / NoSuchMethodError exceptions
        // may stringify the offending field value, which can be the real
        // access_token or refresh_token. Surface the error type only.
        throw OAuthFailure(
          reason: OAuthFailureReason.tokenExchangeFailed,
          message:
              'BFF returned malformed token JSON '
              '(error type: ${e.runtimeType})',
          httpStatus: response.statusCode,
        );
      }
    }

    throw OAuthFailure(
      reason: OAuthFailureReason.tokenExchangeFailed,
      message: 'BFF returned ${response.statusCode}',
      upstreamError: jsonBody?['error'] as String?,
      upstreamErrorDescription: jsonBody?['error_description'] as String?,
      httpStatus: response.statusCode,
    );
  }

  /// Release the underlying http.Client. Call once at app shutdown.
  void close() {
    _httpClient.close();
  }
}
