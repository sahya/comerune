import 'dart:convert';
import 'dart:io';

import '../../app_logging.dart';
import '../../domain/models/follow_program.dart';

/// Checks whether favorite users are currently broadcasting on niconico.
///
/// Uses the broadcast-history API:
/// `GET https://live.nicovideo.jp/front/api/v2/user-broadcast-history?providerId={userId}&providerType=user&isIncludeNonPublic=false&offset=0&limit=1&withTotalCount=false`
///
/// Fetches only the most recent broadcast (`limit=1`) and checks whether its
/// status is `ON_AIR`. This is lightweight (small JSON response) and does not
/// require authentication.
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
    this.minInterval = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _providerType = 'user';

  /// The schedule status value indicating an active broadcast.
  static const String _statusOnAir = 'ON_AIR';

  static const Duration _responseTimeout = Duration(seconds: 10);

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  final HttpClient _httpClient;

  /// Maximum number of HTTP requests that run concurrently.
  final int maxConcurrentRequests;

  /// Minimum interval between full network checks. Calls arriving before this
  /// window elapses return the cached result.
  final Duration minInterval;

  /// Cached result from the last successful network check.
  Map<String, FollowProgram> _cachedOnAirMap = const <String, FollowProgram>{};

  /// When the last network check completed.
  DateTime? _lastCheckTime;

  /// Counter used to skip re-checking already-on-air users every other cycle.
  int _pollCycleCounter = 0;

  /// Checks broadcast status for the given [userIds].
  ///
  /// Returns a map of userId to [FollowProgram] for users who are currently
  /// broadcasting. Users who are not broadcasting are omitted.
  ///
  /// When called within [minInterval] of the previous check, returns the
  /// cached result without making network requests.
  Future<Map<String, FollowProgram>> checkBroadcastStatus(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      _cachedOnAirMap = const <String, FollowProgram>{};
      return const <String, FollowProgram>{};
    }

    // Return cached result when the minimum interval has not elapsed.
    if (_lastCheckTime != null &&
        DateTime.now().difference(_lastCheckTime!) < minInterval) {
      appDebugLogLazy(
        () =>
            '[FavoriteUserLiveChecker] returning cached result: count=${_cachedOnAirMap.length}',
      );
      return Map<String, FollowProgram>.of(_cachedOnAirMap);
    }

    appDebugLogLazy(
      () =>
          '[FavoriteUserLiveChecker] checking favorite users: count=${userIds.length}',
    );

    _pollCycleCounter++;

    // Split users into those that need checking this cycle.
    // Users already known to be on-air are only re-checked on even cycles,
    // halving redundant traffic for stable broadcasts.
    final Set<String> usersToCheck = <String>{};
    for (final String userId in userIds) {
      final bool knownOnAir = _cachedOnAirMap.containsKey(userId);
      if (!knownOnAir || _pollCycleCounter.isEven) {
        usersToCheck.add(userId);
      }
    }

    appDebugLogLazy(
      () =>
          '[FavoriteUserLiveChecker] checking ${usersToCheck.length} of ${userIds.length} users (cycle=$_pollCycleCounter)',
    );

    // Run requests with concurrency throttling.
    final Map<String, FollowProgram> freshResults = await _checkWithThrottling(
      usersToCheck,
    );

    // Merge: start from the previous cache (filtered to current favorites),
    // then overlay fresh results. Users that were skipped this cycle retain
    // their cached on-air status.
    final Map<String, FollowProgram> merged = <String, FollowProgram>{};
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
    return Map<String, FollowProgram>.of(merged);
  }

  /// Invalidates the cached result so the next [checkBroadcastStatus] call
  /// will always perform network requests.
  void invalidateCache() {
    _lastCheckTime = null;
  }

  /// Runs HTTP checks for [userIds] with at most [maxConcurrentRequests]
  /// concurrent requests.
  Future<Map<String, FollowProgram>> _checkWithThrottling(
    Set<String> userIds,
  ) async {
    if (userIds.isEmpty) {
      return const <String, FollowProgram>{};
    }

    final List<String> queue = userIds.toList();
    final Map<String, FollowProgram> results = <String, FollowProgram>{};
    int index = 0;

    Future<void> worker() async {
      while (true) {
        final int myIndex = index++;
        if (myIndex >= queue.length) {
          break;
        }
        final MapEntry<String, FollowProgram>? entry = await _checkSingleUser(
          queue[myIndex],
        );
        if (entry != null) {
          results[entry.key] = entry.value;
        }
      }
    }

    final int workerCount = maxConcurrentRequests.clamp(1, queue.length);
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );

    return results;
  }

  Future<MapEntry<String, FollowProgram>?> _checkSingleUser(
    String userId,
  ) async {
    final String maskedUserId = _maskUserIdForLog(userId);
    try {
      final Uri uri = Uri(
        scheme: 'https',
        host: 'live.nicovideo.jp',
        path: '/front/api/v2/user-broadcast-history',
        queryParameters: <String, String>{
          'providerId': userId,
          'providerType': _providerType,
          'isIncludeNonPublic': 'false',
          'offset': '0',
          'limit': '1',
          'withTotalCount': 'false',
        },
      );
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.headers.set('User-Agent', _defaultUserAgent);

      final HttpClientResponse response = await request.close().timeout(
        _responseTimeout,
      );
      if (response.statusCode != 200) {
        appDebugLogLazy(
          () =>
              '[FavoriteUserLiveChecker] user=$maskedUserId http=${response.statusCode}',
        );
        await response.drain<void>();
        return null;
      }

      final String body = await response.transform(utf8.decoder).join();
      return _parseResponse(userId, body);
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

  /// Parses the broadcast-history API response and returns an entry if the
  /// most recent program is currently ON_AIR.
  MapEntry<String, FollowProgram>? _parseResponse(String userId, String body) {
    final String maskedUserId = _maskUserIdForLog(userId);
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final Object? data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }

      final Object? programsList = data['programsList'];
      if (programsList is! List || programsList.isEmpty) {
        return null;
      }

      final Object? first = programsList[0];
      if (first is! Map<String, dynamic>) {
        return null;
      }

      final Object? program = first['program'];
      if (program is! Map<String, dynamic>) {
        return null;
      }

      final Object? schedule = program['schedule'];
      if (schedule is! Map<String, dynamic>) {
        return null;
      }

      final Object? status = schedule['status'];
      if (status is! String || status != _statusOnAir) {
        appDebugLogLazy(
          () =>
              '[FavoriteUserLiveChecker] user=$maskedUserId status=$status (not on-air)',
        );
        return null;
      }

      final String? programId = _extractNestedValue(first['id']);
      if (programId == null) {
        return null;
      }

      final String title = (program['title'] as String?) ?? '';

      appDebugLogLazy(
        () =>
            '[FavoriteUserLiveChecker] user=$maskedUserId on-air program=$programId',
      );

      return MapEntry<String, FollowProgram>(
        userId,
        FollowProgram(
          programId: programId,
          title: title,
          providerName: _extractProviderName(first),
          providerIconUrl: _extractProviderIconUrl(first),
          communityName: _extractCommunityName(first),
          beginAt: _extractTimestamp(schedule['beginTime']),
          endAt: _extractTimestamp(schedule['scheduledEndTime']),
          status: ProgramStatus.onAir,
        ),
      );
    } on FormatException catch (e) {
      appErrorLog(
        name: 'FavoriteUserLiveChecker',
        message: 'Error parsing broadcast history for user $maskedUserId',
        error: e,
      );
    }
    return null;
  }

  static String _extractProviderName(Map<String, dynamic> item) {
    final Object? provider = item['programProvider'];
    if (provider is Map<String, dynamic>) {
      final Object? name = provider['name'];
      if (name is String && name.isNotEmpty) {
        return name;
      }
    }
    return '';
  }

  static String? _extractProviderIconUrl(Map<String, dynamic> item) {
    final Object? provider = item['programProvider'];
    if (provider is Map<String, dynamic>) {
      final Object? icons = provider['icons'];
      if (icons is Map<String, dynamic>) {
        final Object? uri50 = icons['uri50x50'];
        if (uri50 is String && uri50.isNotEmpty) {
          return uri50;
        }
        final Object? uri150 = icons['uri150x150'];
        if (uri150 is String && uri150.isNotEmpty) {
          return uri150;
        }
      }
    }
    return null;
  }

  static String? _extractCommunityName(Map<String, dynamic> item) {
    final Object? socialGroup = item['socialGroup'];
    if (socialGroup is Map<String, dynamic>) {
      final Object? isDeleted = socialGroup['isDeleted'];
      final bool deleted =
          isDeleted is Map<String, dynamic> && isDeleted['value'] == true;
      if (!deleted) {
        final Object? name = socialGroup['name'];
        if (name is String && name.isNotEmpty) {
          return name;
        }
      }
    }
    return null;
  }

  /// Extracts a [DateTime] from a `{ "seconds": <int> }` timestamp object.
  static DateTime? _extractTimestamp(Object? obj) {
    if (obj is Map<String, dynamic>) {
      final Object? seconds = obj['seconds'];
      if (seconds is int) {
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      }
    }
    return null;
  }

  /// Extracts the string value from a nested `{ "value": "..." }` object,
  /// or returns the value directly if it is already a string.
  static String? _extractNestedValue(Object? obj) {
    if (obj is String && obj.isNotEmpty) {
      return obj;
    }
    if (obj is Map<String, dynamic>) {
      final Object? value = obj['value'];
      if (value is String && value.isNotEmpty) {
        return value;
      }
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
