import 'dart:convert';
import 'dart:io';

import '../../app_logging.dart';
import 'follow_program.dart';
import 'program_parser.dart';

/// Fetches the user's own currently live program from niconico.
///
/// First checks:
/// `GET https://live.nicovideo.jp/front/api/pages/my/v1/programs?status=onair`
///
/// If no on-air program can be resolved from that response, falls back to:
/// `GET https://live2.nicovideo.jp/unama/tool/v1/program_schedules`
class MyProgramRepository {
  MyProgramRepository({
    HttpClient? httpClient,
    String userAgent = _defaultUserAgent,
  }) : _httpClient = httpClient ?? HttpClient(),
       _userAgent = userAgent {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _frontApiBaseUrl =
      'https://live.nicovideo.jp/front/api/pages/my/v1/programs';
  static const String _toolApiBaseUrl =
      'https://live2.nicovideo.jp/unama/tool/v1/program_schedules';

  final HttpClient _httpClient;
  final String _userAgent;

  /// Fetches the user's own on-air program, if any.
  ///
  /// Requires a valid [userSession] for authentication.
  /// Returns `null` if the user is not broadcasting or on failure.
  Future<FollowProgram?> fetchOwnProgram({required String userSession}) async {
    if (userSession.trim().isEmpty) {
      appDebugLog(
        '[MyProgramRepository] Skip own-program fetch because session is empty',
      );
      return null;
    }

    final FollowProgram? fromFront = await _fetchFromFrontApi(
      userSession: userSession,
    );
    if (fromFront != null) {
      appDebugLog(
        '[MyProgramRepository] Resolved own program from front-api endpoint: ${fromFront.programId}',
      );
      return fromFront;
    }

    appDebugLog(
      '[MyProgramRepository] Front-api own program not found; trying tool endpoint',
    );
    final FollowProgram? fromTool = await _fetchFromToolApi(
      userSession: userSession,
    );
    if (fromTool != null) {
      appDebugLog(
        '[MyProgramRepository] Resolved own program from tool endpoint: ${fromTool.programId}',
      );
    }
    return fromTool;
  }

  Future<FollowProgram?> _fetchFromFrontApi({
    required String userSession,
  }) async {
    try {
      final Uri uri = Uri.parse('$_frontApiBaseUrl?status=onair');
      final HttpClientResponse response = await _sendGet(
        uri: uri,
        userSession: userSession,
      );
      appDebugLog(
        '[MyProgramRepository] front-api response status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        await response.drain<void>();
        appDebugLog(
          '[MyProgramRepository] front-api returned non-200: ${response.statusCode}',
        );
        return null;
      }

      final String body = await response.transform(utf8.decoder).join();
      return _parseFrontApiResponse(body);
    } on Exception catch (e) {
      appErrorLog(
        name: 'MyProgramRepository',
        message: 'Error fetching own program from front-api endpoint',
        error: e,
      );
      return null;
    }
  }

  Future<FollowProgram?> _fetchFromToolApi({
    required String userSession,
  }) async {
    try {
      final Uri uri = Uri.parse(_toolApiBaseUrl);
      final HttpClientResponse response = await _sendGet(
        uri: uri,
        userSession: userSession,
      );
      appDebugLog(
        '[MyProgramRepository] tool endpoint response status: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        await response.drain<void>();
        appDebugLog(
          '[MyProgramRepository] tool endpoint returned non-200: ${response.statusCode}',
        );
        return null;
      }

      final String body = await response.transform(utf8.decoder).join();
      return _parseToolApiResponse(body);
    } on Exception catch (e) {
      appErrorLog(
        name: 'MyProgramRepository',
        message: 'Error fetching own program from tool endpoint',
        error: e,
      );
      return null;
    }
  }

  Future<HttpClientResponse> _sendGet({
    required Uri uri,
    required String userSession,
  }) async {
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    request.headers.set('Cookie', 'user_session=$userSession');
    request.headers.set('X-Niconico-Session', userSession);
    request.headers.set('User-Agent', _userAgent);
    return request.close();
  }

  FollowProgram? _parseFrontApiResponse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      appDebugLog(
        '[MyProgramRepository] front-api response root is not object: ${decoded.runtimeType}',
      );
      return null;
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      appDebugLog(
        '[MyProgramRepository] front-api response has invalid data field',
      );
      return null;
    }

    final Object? programs = data['programs'];
    if (programs is! List || programs.isEmpty) {
      appDebugLog('[MyProgramRepository] front-api programs is empty');
      return null;
    }

    // The user can only have one on-air program at a time.
    final Object? item = programs.first;
    if (item is! Map<String, dynamic>) {
      appDebugLog(
        '[MyProgramRepository] front-api first program has invalid type: ${item.runtimeType}',
      );
      return null;
    }

    final FollowProgram? result = parseProgramItem(
      item,
      requireProviderName: false,
      isOwnBroadcast: true,
    );
    if (result == null) {
      appDebugLog(
        '[MyProgramRepository] front-api first program could not be parsed',
      );
    }
    return result;
  }

  FollowProgram? _parseToolApiResponse(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      appDebugLog(
        '[MyProgramRepository] tool response root is not object: ${decoded.runtimeType}',
      );
      return null;
    }

    final Object? data = decoded['data'];
    if (data is! List) {
      appDebugLog('[MyProgramRepository] tool response data is not a list');
      return null;
    }

    for (final Object? raw in data) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      if (!_isOnAirStatus(raw['status'])) {
        continue;
      }

      final Map<String, dynamic> normalized = Map<String, dynamic>.from(raw);
      normalized['id'] ??= _asNonEmptyString(raw['nicoliveProgramId']);
      normalized['title'] ??= _asNonEmptyString(raw['title']) ?? '配信中の番組';
      normalized['beginAt'] ??= _parseEpochSeconds(raw['onAirBeginAt']);

      final FollowProgram? program = parseProgramItem(
        normalized,
        requireProviderName: false,
        isOwnBroadcast: true,
      );
      if (program != null) {
        return program;
      }
    }

    appDebugLog('[MyProgramRepository] tool endpoint returned no on-air item');
    return null;
  }

  bool _isOnAirStatus(Object? rawStatus) {
    final String? status = _asNonEmptyString(rawStatus);
    if (status == null) {
      return true;
    }
    return status.toLowerCase() == 'onair';
  }

  String? _asNonEmptyString(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  int? _parseEpochSeconds(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}
