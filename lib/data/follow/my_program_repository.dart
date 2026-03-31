import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'follow_program.dart';
import 'program_parser.dart';

/// Fetches the user's own currently live program from niconico.
///
/// Uses the niconico on-air programs API filtered to the logged-in user:
/// `GET https://live.nicovideo.jp/front/api/pages/my/v1/programs?status=onair`
///
/// This endpoint is inferred from the existing follow-programs API pattern
/// (`/pages/follow/v1/programs`). If it does not exist, the method returns
/// `null` gracefully. Potential fallback strategies include:
/// - `GET https://live2.nicovideo.jp/unama/api/v3/contents/{liveId}` for
///   individual program availability checks.
/// - Redirecting via `https://live.nicovideo.jp/watch/user/{userId}` to
///   discover the user's active broadcast.
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
      log(
        'Skipped fetch: user session is empty',
        name: 'MyProgramRepository',
      );
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
      log(
        'Unexpected response type: ${decoded.runtimeType}',
        name: 'MyProgramRepository',
      );
      return null;
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      log(
        'Missing or invalid "data" field in response',
        name: 'MyProgramRepository',
      );
      return null;
    }

    final Object? programs = data['programs'];
    if (programs is! List || programs.isEmpty) {
      // Not broadcasting — this is a normal case, no warning needed.
      return null;
    }

    // The user can only have one on-air program at a time.
    final Object? item = programs.first;
    if (item is! Map<String, dynamic>) {
      log(
        'First program item has unexpected type: ${item.runtimeType}',
        name: 'MyProgramRepository',
      );
      return null;
    }

    final FollowProgram? result = parseProgramItem(
      item,
      requireProviderName: false,
      isOwnBroadcast: true,
    );
    if (result == null) {
      log(
        'Failed to parse own program item (missing id or title)',
        name: 'MyProgramRepository',
      );
    }
    return result;
  }

  void dispose() {
    _httpClient.close();
  }
}
