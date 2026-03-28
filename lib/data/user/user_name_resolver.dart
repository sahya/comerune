import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves numeric niconico user IDs to nicknames.
///
/// Uses the nvapi user nickname endpoint (same approach as Hakumai and N Air).
/// Results are cached in memory to avoid redundant network calls.
class UserNameResolver extends ChangeNotifier {
  UserNameResolver({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    Duration connectionTimeout = const Duration(seconds: 5),
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _connectionTimeout = connectionTimeout {
    if (httpClient != null) {
      _seedHttpClient = httpClient;
    }
  }

  static const String _baseUrl = 'https://nvapi.nicovideo.jp/v1/users';

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  final HttpClient Function() _httpClientFactory;
  final Duration _connectionTimeout;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;

  final Map<String, String> _cache = <String, String>{};
  final Set<String> _pending = <String>{};
  bool _disposed = false;

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

  /// Returns the cached nickname for [userId], or null if not yet resolved.
  String? getCachedName(String userId) => _cache[userId];

  /// Requests resolution of the given [userId].
  ///
  /// If already cached or pending, this is a no-op.
  /// When the name is resolved, listeners are notified.
  void requestResolve(String userId) {
    if (_cache.containsKey(userId) || _pending.contains(userId)) {
      return;
    }

    if (!_isNumericUserId(userId)) {
      return;
    }

    _pending.add(userId);
    _fetchNickname(userId);
  }

  Future<void> _fetchNickname(String userId) async {
    try {
      final Uri uri = Uri.parse('$_baseUrl/$userId');
      final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
      request.headers.set('User-Agent', _userAgent);
      request.headers.set('X-Frontend-Id', '6');

      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        _pending.remove(userId);
        return;
      }

      final String body = await response.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        _pending.remove(userId);
        return;
      }

      final Object? data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        _pending.remove(userId);
        return;
      }

      final Object? user = data['user'];
      if (user is! Map<String, dynamic>) {
        _pending.remove(userId);
        return;
      }

      final String? nickname = user['nickname'] as String?;
      _pending.remove(userId);
      if (nickname != null && nickname.isNotEmpty && !_disposed) {
        _cache[userId] = nickname;
        notifyListeners();
      }
    } catch (error) {
      log(
        'Failed to resolve user $userId: $error',
        name: 'UserNameResolver',
      );
      _pending.remove(userId);
    }
  }

  static bool _isNumericUserId(String userId) {
    return userId.isNotEmpty && int.tryParse(userId) != null;
  }

  void clearCache() {
    _cache.clear();
    _pending.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _httpClient?.close();
    _httpClient = null;
    _seedHttpClient = null;
    super.dispose();
  }
}
