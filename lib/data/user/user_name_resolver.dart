import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves numeric niconico user IDs to nicknames.
///
/// Uses the nvapi user nickname endpoint (same approach as Hakumai and N Air).
/// Results are cached in memory to avoid redundant network calls.
/// Concurrent HTTP requests are capped at [_maxConcurrentRequests] to avoid
/// rate-limiting or socket exhaustion.
class UserNameResolver extends ChangeNotifier {
  UserNameResolver({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    Duration connectionTimeout = const Duration(seconds: 5),
    Duration debounceDuration = const Duration(milliseconds: 200),
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _connectionTimeout = connectionTimeout,
        _debounceDuration = debounceDuration {
    if (httpClient != null) {
      _seedHttpClient = httpClient;
    }
  }

  /// Uses the same endpoint as Hakumai (macOS niconico comment viewer).
  /// This endpoint does not require authentication.
  static const String _baseUrl =
      'https://api.live2.nicovideo.jp/api/v1/user/nickname';

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const int _maxConcurrentRequests = 3;

  final HttpClient Function() _httpClientFactory;
  final Duration _connectionTimeout;
  final Duration _debounceDuration;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;

  final Map<String, String> _cache = <String, String>{};
  final Set<String> _pending = <String>{};
  final Queue<String> _queue = Queue<String>();
  int _activeRequests = 0;
  bool _disposed = false;
  Timer? _debounceTimer;
  bool _hasPendingNotification = false;

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

  /// Pre-populates the cache with a known name (e.g. from the programinfo
  /// API `broadcaster[0].name` field). This avoids the need for an additional
  /// HTTP request to the nickname endpoint.
  void seedCache(String userId, String name) {
    if (name.isEmpty || _disposed) {
      return;
    }
    _cache[userId] = name;
    _pending.remove(userId);
    _scheduleNotification();
  }

  /// Requests resolution of the given [userId].
  ///
  /// If already cached or pending, this is a no-op.
  /// When the name is resolved, listeners are notified (debounced).
  void requestResolve(String userId) {
    if (_cache.containsKey(userId) || _pending.contains(userId)) {
      return;
    }

    if (!_isNumericUserId(userId)) {
      return;
    }

    _pending.add(userId);
    _queue.add(userId);
    _drainQueue();
  }

  void _drainQueue() {
    while (_activeRequests < _maxConcurrentRequests && _queue.isNotEmpty) {
      final String userId = _queue.removeFirst();
      _activeRequests++;
      _fetchNickname(userId);
    }
  }

  Future<void> _fetchNickname(String userId) async {
    try {
      final Uri uri = Uri.parse('$_baseUrl?userId=$userId');
      log('Fetching nickname for $userId', name: 'UserNameResolver');
      final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
      request.headers.set('User-Agent', _userAgent);

      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        log(
          'User $userId: HTTP ${response.statusCode}',
          name: 'UserNameResolver',
        );
        await response.drain<void>();
        _pending.remove(userId);
        _onRequestDone();
        return;
      }

      final String body = await response.transform(utf8.decoder).join();
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        log(
          'User $userId: response is not a JSON object',
          name: 'UserNameResolver',
        );
        _pending.remove(userId);
        _onRequestDone();
        return;
      }

      final Object? data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        log('User $userId: missing "data" field', name: 'UserNameResolver');
        _pending.remove(userId);
        _onRequestDone();
        return;
      }

      // api.live2.nicovideo.jp returns { data: { nickname: "..." } }
      final String? nickname = data['nickname'] as String?;
      _pending.remove(userId);
      if (nickname != null && nickname.isNotEmpty && !_disposed) {
        _cache[userId] = nickname;
        _scheduleNotification();
        log('Resolved user $userId → $nickname', name: 'UserNameResolver');
      }
      _onRequestDone();
    } catch (error) {
      log('Failed to resolve user $userId: $error', name: 'UserNameResolver');
      _pending.remove(userId);
      _onRequestDone();
    }
  }

  void _onRequestDone() {
    if (_disposed) {
      return;
    }
    _activeRequests--;
    _drainQueue();
  }

  void _scheduleNotification() {
    _hasPendingNotification = true;
    if (_debounceTimer?.isActive ?? false) {
      return;
    }
    _debounceTimer = Timer(_debounceDuration, () {
      if (_hasPendingNotification && !_disposed) {
        _hasPendingNotification = false;
        notifyListeners();
      }
    });
  }

  static bool _isNumericUserId(String userId) {
    return userId.isNotEmpty && int.tryParse(userId) != null;
  }

  void clearCache() {
    _cache.clear();
    _pending.clear();
    _queue.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _httpClient?.close();
    _httpClient = null;
    _seedHttpClient = null;
    super.dispose();
  }
}
