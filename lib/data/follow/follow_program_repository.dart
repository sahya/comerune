import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'follow_program.dart';

/// Fetches the list of currently live programs from followed broadcasters.
///
/// Uses the niconico follow page API:
/// `GET https://live.nicovideo.jp/front/api/pages/follow/v1/programs?status=onair`
class FollowProgramRepository {
  FollowProgramRepository({
    HttpClient? httpClient,
    String userAgent = _defaultUserAgent,
  }) : _httpClient = httpClient ?? HttpClient(),
       _userAgent = userAgent {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _baseUrl =
      'https://live.nicovideo.jp/front/api/pages/follow/v1/programs';

  final HttpClient _httpClient;
  final String _userAgent;

  /// Fetches on-air programs from followed broadcasters.
  ///
  /// Requires a valid [userSession] for authentication.
  /// Returns an empty list on failure or when not logged in.
  Future<List<FollowProgram>> fetchOnAirPrograms({
    required String userSession,
  }) async {
    if (userSession.trim().isEmpty) {
      return const <FollowProgram>[];
    }

    try {
      final Uri uri = Uri.parse('$_baseUrl?status=onair&offset=0');
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.headers.set('Cookie', 'user_session=$userSession');
      request.headers.set('X-Niconico-Session', userSession);
      request.headers.set('User-Agent', _userAgent);

      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        log(
          'Failed to fetch follow programs: HTTP ${response.statusCode}',
          name: 'FollowProgramRepository',
        );
        return const <FollowProgram>[];
      }

      final String body = await response.transform(utf8.decoder).join();
      return _parseResponse(body);
    } on Exception catch (e) {
      log(
        'Error fetching follow programs: ${e.runtimeType}',
        name: 'FollowProgramRepository',
      );
      return const <FollowProgram>[];
    }
  }

  List<FollowProgram> _parseResponse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return const <FollowProgram>[];
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      return const <FollowProgram>[];
    }

    final Object? programs = data['programs'];
    if (programs is! List) {
      return const <FollowProgram>[];
    }

    final List<FollowProgram> result = <FollowProgram>[];
    for (final Object? item in programs) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final String? programId = item['id'] as String?;
      final String? title = item['title'] as String?;
      if (programId == null || title == null) {
        continue;
      }

      // Extract broadcaster name and icon from programProvider or supplier.
      final String? providerName = _extractProviderName(item);
      if (providerName == null) {
        continue;
      }

      final String? providerIconUrl = _extractProviderIconUrl(item);
      final String? communityName = _extractCommunityName(item);
      final DateTime? beginAt = _parseBeginAt(item);

      result.add(
        FollowProgram(
          programId: programId,
          title: title,
          providerName: providerName,
          providerIconUrl: providerIconUrl,
          communityName: communityName,
          beginAt: beginAt,
        ),
      );
    }

    return result;
  }

  static String? _extractProviderName(Map<String, dynamic> item) {
    final Object? provider = item['programProvider'];
    if (provider is Map<String, dynamic>) {
      final Object? name = provider['name'];
      if (name is String && name.isNotEmpty) {
        return name;
      }
    }

    final Object? supplier = item['supplier'];
    if (supplier is Map<String, dynamic>) {
      final Object? name = supplier['name'];
      if (name is String && name.isNotEmpty) {
        return name;
      }
    }

    return null;
  }

  static String? _extractProviderIconUrl(Map<String, dynamic> item) {
    final Object? provider = item['programProvider'];
    if (provider is Map<String, dynamic>) {
      final Object? iconSmall = provider['iconSmall'];
      if (iconSmall is String && _isHttpsUrl(iconSmall)) {
        return iconSmall;
      }
      final Object? icon = provider['icon'];
      if (icon is String && _isHttpsUrl(icon)) {
        return icon;
      }
    }

    final Object? supplier = item['supplier'];
    if (supplier is Map<String, dynamic>) {
      final Object? icons = supplier['icons'];
      if (icons is Map<String, dynamic>) {
        final Object? uri50 = icons['uri50x50'];
        if (uri50 is String && _isHttpsUrl(uri50)) {
          return uri50;
        }
        final Object? uri150 = icons['uri150x150'];
        if (uri150 is String && _isHttpsUrl(uri150)) {
          return uri150;
        }
      }
    }

    return null;
  }

  static bool _isHttpsUrl(String url) {
    return url.isNotEmpty && url.startsWith('https://');
  }

  static String? _extractCommunityName(Map<String, dynamic> item) {
    final Object? socialGroup = item['socialGroup'];
    if (socialGroup is Map<String, dynamic>) {
      final Object? name = socialGroup['name'];
      if (name is String && name.isNotEmpty) {
        return name;
      }
    }
    return null;
  }

  static DateTime? _parseBeginAt(Map<String, dynamic> item) {
    final Object? raw = item['beginAt'];
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
    }
    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}
