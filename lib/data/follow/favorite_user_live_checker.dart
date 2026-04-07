import 'dart:io';

import '../../app_logging.dart';

/// Checks whether favorite users are currently broadcasting on niconico.
///
/// For each user ID, makes a GET request to
/// `https://live.nicovideo.jp/watch/user/<userId>`.
/// If the server responds with a redirect (301/302/303/307/308), the user is
/// broadcasting and the redirect Location header contains the program URL
/// (e.g. `https://live.nicovideo.jp/watch/lv348712105`).
/// A 200 response or any error means the user is not broadcasting.
///
/// Battery-efficiency features:
/// - **Concurrency throttling**: At most [maxConcurrentRequests] HTTP requests
///   run in parallel, reducing CPU/radio wake-ups.
/// - **Result caching**: The last known on-air map is cached for
///   [minInterval]. Calls within that window return the cache immediately.
/// - **Staggered requests**: Users already known to be on-air are checked
///   less frequently (every other cycle) to halve redundant traffic.
class FavoriteUserLiveChecker {
  FavoriteUserLiveChecker({
    HttpClient? httpClient,
    this.maxConcurrentRequests = 3,
    this.minInterval = const Duration(seconds: 45),
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _baseUrl = 'https://live.nicovideo.jp/watch/user/';

  static const Duration _responseTimeout = Duration(seconds: 10);
  static final RegExp _lvProgramIdPattern = RegExp(
    r'^lv\d{1,18}$',
    caseSensitive: false,
  );

  final HttpClient _httpClient;

  /// Maximum number of HTTP requests that run concurrently.
  final int maxConcurrentRequests;

  /// Minimum interval between full network checks. Calls arriving before this
  /// window elapses return the cached result.
  final Duration minInterval;

  /// Cached result from the last successful network check.
  Map<String, String> _cachedOnAirMap = const <String, String>{};

  /// When the last network check completed.
  DateTime? _lastCheckTime;

  /// Counter used to skip re-checking already-on-air users every other cycle.
  int _cycleCounter = 0;

  /// Checks broadcast status for the given [userIds].
  ///
  /// Returns a map of userId to programId (e.g. `lv348712105`) for users
  /// who are currently broadcasting. Users who are not broadcasting are
  /// omitted from the result.
  ///
  /// When called within [minInterval] of the previous check, returns the
  /// cached result without making network requests.
  Future<Map<String, String>> checkBroadcastStatus(Set<String> userIds) async {
    if (userIds.isEmpty) {
      _cachedOnAirMap = const <String, String>{};
      return const <String, String>{};
    }

    // Return cached result when the minimum interval has not elapsed.
    if (_lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < minInterval) {
      appDebugLogLazy(
        () =>
            '[FavoriteUserLiveChecker] returning cached result: count=${_cachedOnAirMap.length}',
      );
      return Map<String, String>.of(_cachedOnAirMap);
    }

    appDebugLogLazy(
      () =>
          '[FavoriteUserLiveChecker] checking favorite users: count=${userIds.length}',
    );

    _cycleCounter++;

    // Split users into those that need checking this cycle.
    // Users already known to be on-air are only re-checked on even cycles,
    // halving redundant traffic for stable broadcasts.
    final Set<String> usersToCheck = <String>{};
    for (final String userId in userIds) {
      final bool knownOnAir = _cachedOnAirMap.containsKey(userId);
      if (!knownOnAir || _cycleCounter.isEven) {
        usersToCheck.add(userId);
      }
    }

    appDebugLogLazy(
      () =>
          '[FavoriteUserLiveChecker] checking ${usersToCheck.length} of ${userIds.length} users (cycle=$_cycleCounter)',
    );

    // Run requests with concurrency throttling.
    final Map<String, String> freshResults =
        await _checkWithThrottling(usersToCheck);

    // Merge: start from the previous cache (filtered to current favorites),
    // then overlay fresh results. Users that were skipped this cycle retain
    // their cached on-air status.
    final Map<String, String> merged = <String, String>{};
    for (final String userId in userIds) {
      if (freshResults.containsKey(userId)) {
        merged[userId] = freshResults[userId]!;
      } else if (_cachedOnAirMap.containsKey(userId) &&
          !usersToCheck.contains(userId)) {
        // Retain cached status for users skipped this cycle.
        merged[userId] = _cachedOnAirMap[userId]!;
      }
    }

    _cachedOnAirMap = merged;
    _lastCheckTime = DateTime.now();

    appDebugLogLazy(
      () =>
          '[FavoriteUserLiveChecker] on-air favorites resolved: count=${merged.length}',
    );
    return Map<String, String>.of(merged);
  }

  /// Invalidates the cached result so the next [checkBroadcastStatus] call
  /// will always perform network requests.
  void invalidateCache() {
    _lastCheckTime = null;
  }

  /// Runs HTTP checks for [userIds] with at most [maxConcurrentRequests]
  /// concurrent requests.
  Future<Map<String, String>> _checkWithThrottling(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const <String, String>{};
    }

    final List<String> queue = userIds.toList();
    final Map<String, String> results = <String, String>{};
    int index = 0;

    Future<void> worker() async {
      while (true) {
        final int myIndex = index++;
        if (myIndex >= queue.length) {
          break;
        }
        final MapEntry<String, String>? entry =
            await _checkSingleUser(queue[myIndex]);
        if (entry != null) {
          results[entry.key] = entry.value;
        }
      }
    }

    final int workerCount =
        maxConcurrentRequests.clamp(1, queue.length);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    return results;
  }

  Future<MapEntry<String, String>?> _checkSingleUser(String userId) async {
    final String maskedUserId = _maskUserIdForLog(userId);
    try {
      final Uri uri = Uri.parse('$_baseUrl$userId');
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.followRedirects = false;

      final HttpClientResponse response = await request.close().timeout(
            _responseTimeout,
          );
      try {
        final int statusCode = response.statusCode;
        appDebugLogLazy(
          () =>
              '[FavoriteUserLiveChecker] user=$maskedUserId status=$statusCode',
        );
        if (_isRedirect(statusCode)) {
          final String? location = response.headers.value('location');
          if (location != null) {
            final String? programId = _extractProgramId(location);
            if (programId != null) {
              appDebugLogLazy(
                () =>
                    '[FavoriteUserLiveChecker] user=$maskedUserId on-air program=$programId',
              );
              return MapEntry<String, String>(userId, programId);
            }
            appDebugLogLazy(
              () =>
                  '[FavoriteUserLiveChecker] user=$maskedUserId redirect had no lv program id',
            );
          } else {
            appDebugLogLazy(
              () =>
                  '[FavoriteUserLiveChecker] user=$maskedUserId redirect had no location header',
            );
          }
        }
      } finally {
        await response.drain<void>();
      }
    } on Exception catch (e) {
      appErrorLog(
        name: 'FavoriteUserLiveChecker',
        message:
            'Error checking broadcast status for favorite user $maskedUserId',
        error: e,
      );
    }
    return null;
  }

  static bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  /// Extracts the program ID (e.g. `lv348712105`) from a redirect Location URL.
  ///
  /// Expected format: `https://live.nicovideo.jp/watch/lv348712105`
  static String? _extractProgramId(String location) {
    try {
      final Uri uri = Uri.parse(location);
      final List<String> segments = uri.pathSegments;
      for (final String segment in segments.reversed) {
        if (_lvProgramIdPattern.hasMatch(segment)) {
          return segment.toLowerCase();
        }
      }
    } on FormatException {
      // Malformed Location header; ignore.
    }
    return null;
  }

  String _maskUserIdForLog(String userId) {
    if (userId.length <= 2) {
      return '**';
    }
    final String first = userId.substring(0, 1);
    final String last = userId.substring(userId.length - 1);
    return '$first***$last';
  }

  void dispose() {
    _httpClient.close();
  }
}
