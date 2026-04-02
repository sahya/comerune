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
class FavoriteUserLiveChecker {
  FavoriteUserLiveChecker({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _baseUrl = 'https://live.nicovideo.jp/watch/user/';

  static const Duration _responseTimeout = Duration(seconds: 10);
  static final RegExp _lvProgramIdPattern = RegExp(
    r'^lv\d{1,18}$',
    caseSensitive: false,
  );

  final HttpClient _httpClient;

  /// Checks broadcast status for the given [userIds].
  ///
  /// Returns a map of userId to programId (e.g. `lv348712105`) for users
  /// who are currently broadcasting. Users who are not broadcasting are
  /// omitted from the result.
  Future<Map<String, String>> checkBroadcastStatus(Set<String> userIds) async {
    if (userIds.isEmpty) {
      return const <String, String>{};
    }

    appDebugLog(
      '[FavoriteUserLiveChecker] checking favorite users: count=${userIds.length}',
    );
    final List<Future<MapEntry<String, String>?>> futures =
        userIds.map(_checkSingleUser).toList();
    final List<MapEntry<String, String>?> results = await Future.wait(futures);

    final Map<String, String> onAirMap = <String, String>{};
    for (final MapEntry<String, String>? entry in results) {
      if (entry != null) {
        onAirMap[entry.key] = entry.value;
      }
    }
    appDebugLog(
      '[FavoriteUserLiveChecker] on-air favorites resolved: count=${onAirMap.length}',
    );
    return onAirMap;
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
        appDebugLog(
          '[FavoriteUserLiveChecker] user=$maskedUserId status=$statusCode',
        );
        if (_isRedirect(statusCode)) {
          final String? location = response.headers.value('location');
          if (location != null) {
            final String? programId = _extractProgramId(location);
            if (programId != null) {
              appDebugLog(
                '[FavoriteUserLiveChecker] user=$maskedUserId on-air program=$programId',
              );
              return MapEntry<String, String>(userId, programId);
            }
            appDebugLog(
              '[FavoriteUserLiveChecker] user=$maskedUserId redirect had no lv program id',
            );
          } else {
            appDebugLog(
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
