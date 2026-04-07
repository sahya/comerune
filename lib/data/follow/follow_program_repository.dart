import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'follow_program.dart';
import 'program_parser.dart';

/// Fetches the list of currently live programs from followed broadcasters.
///
/// Uses the niconico follow page API:
/// `GET https://live.nicovideo.jp/front/api/pages/follow/v1/programs?status=onair`
class FollowProgramRepository {
  FollowProgramRepository({
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

      final FollowProgram? program = parseProgramItem(item);
      if (program != null) {
        result.add(program);
      }
    }

    return result;
  }

  void dispose() {
    _httpClient.close();
  }
}
