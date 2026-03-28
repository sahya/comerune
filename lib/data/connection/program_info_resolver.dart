import 'dart:convert';
import 'dart:developer';
import 'dart:io';

/// Resolves the NDGR view URI from the niconico programinfo API.
///
/// Follows the same flow as N Air (official niconico streaming tool):
/// 1. Call programinfo API with user_session cookie
/// 2. Extract rooms[].viewUri from the response
///
/// This bypasses the WebSocket handshake entirely — the viewUri is
/// obtained directly via a single HTTP call.
class ProgramInfoResolver {
  ProgramInfoResolver({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    String userAgent = defaultUserAgent,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _userAgent = userAgent,
        _connectionTimeout = connectionTimeout {
    if (httpClient != null) {
      _seedHttpClient = httpClient;
    }
  }

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _live2BaseUrl = 'https://live2.nicovideo.jp';

  final HttpClient Function() _httpClientFactory;
  final String _userAgent;
  final Duration _connectionTimeout;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;

  HttpClient get _activeHttpClient {
    final HttpClient? current = _httpClient;
    if (current != null) {
      return current;
    }
    final HttpClient? seed = _seedHttpClient;
    if (seed != null) {
      _seedHttpClient = null;
      _httpClient = seed;
      seed.connectionTimeout = _connectionTimeout;
      return seed;
    }
    final HttpClient created = _httpClientFactory();
    created.connectionTimeout = _connectionTimeout;
    _httpClient = created;
    return created;
  }

  /// Resolves the NDGR view URI for the given live program.
  ///
  /// [lv] is the live program ID (e.g., "lv350186414").
  /// [userSession] is the value of the user_session cookie.
  ///
  /// Returns the NDGR view URI to connect to.
  /// Throws [ProgramInfoResolveException] on failure.
  Future<Uri> resolve({
    required String lv,
    required String userSession,
  }) async {
    if (userSession.trim().isEmpty) {
      throw ProgramInfoResolveException('user_session is empty');
    }

    final Uri uri = Uri.parse('$_live2BaseUrl/watch/$lv/programinfo');
    final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
    request.headers.set('X-Niconico-Session', userSession);
    request.headers.set('User-Agent', _userAgent);

    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      final String body = await _readLimitedBody(response);
      await response.drain<void>();
      throw ProgramInfoResolveException(
        'Failed to fetch program info: HTTP ${response.statusCode}: $body',
      );
    }

    final String body = await response.transform(utf8.decoder).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info response is not a JSON object',
      );
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info response missing "data" field',
      );
    }

    final Object? rooms = data['rooms'];
    if (rooms is! List || rooms.isEmpty) {
      throw ProgramInfoResolveException(
        'Program info response has no rooms',
      );
    }

    final Object? firstRoom = rooms[0];
    if (firstRoom is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info room entry is not a JSON object',
      );
    }

    final String? viewUri = firstRoom['viewUri'] as String?;
    if (viewUri == null || viewUri.isEmpty) {
      throw ProgramInfoResolveException(
        'Program info room missing "viewUri" field',
      );
    }

    final Uri? parsed = Uri.tryParse(viewUri);
    if (parsed == null) {
      throw ProgramInfoResolveException(
        'Invalid viewUri: $viewUri',
      );
    }

    log(
      'Resolved NDGR viewUri for $lv via programinfo',
      name: 'ProgramInfoResolver',
    );
    return parsed;
  }

  /// Reads at most [_maxErrorBodyBytes] bytes from the response to avoid
  /// consuming excessive memory on large error responses.
  static const int _maxErrorBodyBytes = 512;

  Future<String> _readLimitedBody(HttpClientResponse response) async {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length >= _maxErrorBodyBytes) {
        break;
      }
    }
    final String result = utf8.decode(
      bytes.length > _maxErrorBodyBytes
          ? bytes.sublist(0, _maxErrorBodyBytes)
          : bytes,
      allowMalformed: true,
    );
    return bytes.length >= _maxErrorBodyBytes ? '$result...' : result;
  }

  void dispose() {
    _httpClient?.close();
    _httpClient = null;
    _seedHttpClient = null;
  }
}

class ProgramInfoResolveException implements Exception {
  ProgramInfoResolveException(this.message);

  final String message;

  @override
  String toString() => 'ProgramInfoResolveException: $message';
}
