import 'dart:convert';
import 'dart:io';

/// Resolves the WebSocket endpoint URL from the niconico API.
///
/// Follows the same flow as Hakumai (Mac comment viewer):
/// 1. Call userinfo API to get userId
/// 2. Call wsendpoint API with lv + userId to get WebSocket URL
class WsEndpointResolver {
  WsEndpointResolver({
    HttpClient? httpClient,
    String userAgent = defaultUserAgent,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _httpClient = httpClient ?? HttpClient(),
        _userAgent = userAgent {
    _httpClient.connectionTimeout = connectionTimeout;
  }

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _wsEndpointApiUrl =
      'https://api.live2.nicovideo.jp/api/v1/wsendpoint';
  static const String _userinfoApiUrl =
      'https://oauth.nicovideo.jp/open_id/userinfo';

  final HttpClient _httpClient;
  final String _userAgent;

  /// Resolves the WebSocket endpoint URL for the given live program.
  ///
  /// [lv] is the live program ID (e.g., "lv350186414").
  /// [accessToken] is the OAuth2 access token.
  ///
  /// Returns the WebSocket URI to connect to.
  Future<Uri> resolve({
    required String lv,
    required String accessToken,
  }) async {
    final String userId = await _fetchUserId(accessToken);
    return _fetchWsEndpoint(
      lv: lv,
      userId: userId,
      accessToken: accessToken,
    );
  }

  Future<String> _fetchUserId(String accessToken) async {
    final Uri uri = Uri.parse(_userinfoApiUrl);
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $accessToken');
    request.headers.set('User-Agent', _userAgent);

    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      final String body = await response.transform(utf8.decoder).join();
      throw WsEndpointResolveException(
        'Failed to fetch user info: HTTP ${response.statusCode}: $body',
      );
    }

    final String body = await response.transform(utf8.decoder).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw WsEndpointResolveException(
        'User info response is not a JSON object',
      );
    }

    final String? sub = decoded['sub'] as String?;
    if (sub == null || sub.isEmpty) {
      throw WsEndpointResolveException(
        'User info response missing "sub" field',
      );
    }
    return sub;
  }

  Future<Uri> _fetchWsEndpoint({
    required String lv,
    required String userId,
    required String accessToken,
  }) async {
    final Uri uri = Uri.parse(_wsEndpointApiUrl).replace(
      queryParameters: <String, String>{
        'nicoliveProgramId': lv,
        'userId': userId,
      },
    );
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set('Authorization', 'Bearer $accessToken');
    request.headers.set('User-Agent', _userAgent);

    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      final String body = await response.transform(utf8.decoder).join();
      throw WsEndpointResolveException(
        'Failed to fetch WS endpoint: HTTP ${response.statusCode}: $body',
      );
    }

    final String body = await response.transform(utf8.decoder).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw WsEndpointResolveException(
        'WS endpoint response is not a JSON object',
      );
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw WsEndpointResolveException(
        'WS endpoint response missing "data" field',
      );
    }

    final String? urlStr = data['url'] as String?;
    if (urlStr == null || urlStr.isEmpty) {
      throw WsEndpointResolveException(
        'WS endpoint response missing "data.url" field',
      );
    }

    final Uri? wsUri = Uri.tryParse(urlStr);
    if (wsUri == null) {
      throw WsEndpointResolveException(
        'Invalid WS endpoint URL: $urlStr',
      );
    }
    return wsUri;
  }

  void dispose() {
    _httpClient.close();
  }
}

class WsEndpointResolveException implements Exception {
  WsEndpointResolveException(this.message);

  final String message;

  @override
  String toString() => 'WsEndpointResolveException: $message';
}
