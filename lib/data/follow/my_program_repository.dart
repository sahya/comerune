import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import '../utils/begin_at_parser.dart';
import 'follow_program.dart';

/// Fetches the user's own currently live program from niconico.
///
/// Uses the niconico on-air programs API filtered to the logged-in user:
/// `GET https://live.nicovideo.jp/front/api/pages/my/v1/programs?status=onair`
class MyProgramRepository {
  MyProgramRepository({
    HttpClient? httpClient,
    String userAgent = _defaultUserAgent,
  })  : _httpClient = httpClient ?? HttpClient(),
        _userAgent = userAgent {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _baseUrl =
      'https://live.nicovideo.jp/front/api/pages/my/v1/programs';

  final HttpClient _httpClient;
  final String _userAgent;

  /// Fetches the user's own on-air program, if any.
  ///
  /// Requires a valid [userSession] for authentication.
  /// Returns `null` if the user is not broadcasting or on failure.
  Future<FollowProgram?> fetchOwnProgram({
    required String userSession,
  }) async {
    if (userSession.trim().isEmpty) {
      return null;
    }

    try {
      final Uri uri = Uri.parse('$_baseUrl?status=onair');
      final HttpClientRequest request = await _httpClient.getUrl(uri);
      request.headers.set('Cookie', 'user_session=$userSession');
      request.headers.set('X-Niconico-Session', userSession);
      request.headers.set('User-Agent', _userAgent);

      final HttpClientResponse response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        log(
          'Failed to fetch own program: HTTP ${response.statusCode}',
          name: 'MyProgramRepository',
        );
        return null;
      }

      final String body = await response.transform(utf8.decoder).join();
      return _parseResponse(body);
    } on Exception catch (e) {
      log(
        'Error fetching own program: ${e.runtimeType}',
        name: 'MyProgramRepository',
      );
      return null;
    }
  }

  FollowProgram? _parseResponse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      return null;
    }

    final Object? programs = data['programs'];
    if (programs is! List || programs.isEmpty) {
      return null;
    }

    // The user can only have one on-air program at a time.
    final Object? item = programs.first;
    if (item is! Map<String, dynamic>) {
      return null;
    }

    final String? programId = item['id'] as String?;
    final String? title = item['title'] as String?;
    if (programId == null || title == null) {
      return null;
    }

    final String? providerName = _extractProviderName(item);
    final String? providerIconUrl = _extractProviderIconUrl(item);
    final DateTime? beginAt = parseBeginAt(item);

    return FollowProgram(
      programId: programId,
      title: title,
      providerName: providerName ?? '',
      providerIconUrl: providerIconUrl,
      beginAt: beginAt,
      isOwnBroadcast: true,
    );
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

  void dispose() {
    _httpClient.close();
  }
}
