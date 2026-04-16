import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app_logging.dart';
import '../../domain/models/broadcast_control_result.dart';

/// Re-exports [BroadcastControlResult] from the domain layer.
///
/// Prefer importing `package:comerune/domain/models/broadcast_control_result.dart`
/// directly in new code.
export '../../domain/models/broadcast_control_result.dart';

/// Controls niconico live broadcast lifecycle (start / stop / extend).
///
/// Uses the segment API at `https://live2.nicovideo.jp/watch/{programID}/segment`
/// discovered from N-Air's implementation:
/// - Start broadcast: `PUT /segment` with `{ "state": "on_air" }`
/// - End broadcast:   `PUT /segment` with `{ "state": "end" }`
/// - Extend:          `POST /extension` with `{ "minutes": N }`
class BroadcastControlRepository {
  BroadcastControlRepository({
    HttpClient? httpClient,
    String userAgent = _defaultUserAgent,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? HttpClient(),
       _userAgent = userAgent,
       _requestTimeout = requestTimeout {
    _httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _baseUrl = 'https://live2.nicovideo.jp/watch';

  final HttpClient _httpClient;
  final String _userAgent;

  /// Deadline for the full request/response roundtrip after the TCP
  /// connection has been established. `HttpClient.connectionTimeout` only
  /// guards the initial connect; without this guard a stalled server keeps
  /// the broadcast-control call hanging indefinitely. Mirrors the pattern in
  /// [LiveCommentRepository] so the two repositories can be unified in the
  /// future.
  final Duration _requestTimeout;

  /// Starts a broadcast (transitions to on-air state).
  ///
  /// The [programId] must be a valid program ID (e.g. "lv348712105").
  /// Requires a valid [userSession] for authentication.
  Future<BroadcastControlResult> startBroadcast({
    required String programId,
    required String userSession,
  }) async {
    return _updateSegmentState(
      programId: programId,
      userSession: userSession,
      state: 'on_air',
      operationName: 'startBroadcast',
    );
  }

  /// Ends a broadcast.
  ///
  /// The [programId] must be a valid program ID (e.g. "lv348712105").
  /// Requires a valid [userSession] for authentication.
  Future<BroadcastControlResult> endBroadcast({
    required String programId,
    required String userSession,
  }) async {
    return _updateSegmentState(
      programId: programId,
      userSession: userSession,
      state: 'end',
      operationName: 'endBroadcast',
    );
  }

  /// Extends a broadcast by [minutes] (default 30).
  ///
  /// The [programId] must be a valid program ID (e.g. "lv348712105").
  /// Requires a valid [userSession] for authentication.
  Future<BroadcastControlResult> extendBroadcast({
    required String programId,
    required String userSession,
    int minutes = 30,
  }) async {
    if (programId.isEmpty || userSession.trim().isEmpty) {
      return const BroadcastControlResult(
        success: false,
        errorCode: 'INVALID_PARAMS',
        errorMessage: 'programId and userSession are required',
      );
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_baseUrl/$programId/extension');
      request = await _httpClient.postUrl(uri);
      _setHeaders(request, userSession);
      request.write(jsonEncode(<String, int>{'minutes': minutes}));

      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      return await _parseResponse(response, 'extendBroadcast');
    } on TimeoutException catch (e) {
      return _handleTimeout(request, e, 'extendBroadcast');
    } on Exception catch (e) {
      return _handleException(e, 'extendBroadcast');
    }
  }

  Future<BroadcastControlResult> _updateSegmentState({
    required String programId,
    required String userSession,
    required String state,
    required String operationName,
  }) async {
    if (programId.isEmpty || userSession.trim().isEmpty) {
      return const BroadcastControlResult(
        success: false,
        errorCode: 'INVALID_PARAMS',
        errorMessage: 'programId and userSession are required',
      );
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_baseUrl/$programId/segment');
      request = await _httpClient.putUrl(uri);
      _setHeaders(request, userSession);
      request.write(jsonEncode(<String, String>{'state': state}));

      final HttpClientResponse response = await request.close().timeout(
        _requestTimeout,
      );
      return await _parseResponse(response, operationName);
    } on TimeoutException catch (e) {
      return _handleTimeout(request, e, operationName);
    } on Exception catch (e) {
      return _handleException(e, operationName);
    }
  }

  /// Shared timeout handler: aborts the stalled request so its underlying
  /// socket is returned to the OS (preventing fd / connection-pool leaks on
  /// long-running broadcaster sessions — #485) and maps the failure to the
  /// `NETWORK_ERROR` code.
  ///
  /// `abort()` is idempotent per the Dart SDK, so it is safe even if the
  /// request has already completed by the time we enter the handler.
  ///
  /// Mirrored byte-for-byte by [LiveCommentRepository]; both copies are
  /// expected to be lifted into a shared base class by #464.
  BroadcastControlResult _handleTimeout(
    HttpClientRequest? request,
    TimeoutException e,
    String operationName,
  ) {
    request?.abort();
    appErrorLog(
      name: 'BroadcastControlRepository',
      message: 'Timeout in $operationName',
      error: e,
    );
    // Use `e.toString()` here (rather than `e.runtimeType.toString()`) so the
    // failure message preserves the configured timeout duration, aiding
    // incident triage without leaking any user / session data.
    return BroadcastControlResult(
      success: false,
      errorCode: 'NETWORK_ERROR',
      errorMessage: e.toString(),
    );
  }

  /// Shared fallback handler for non-timeout exceptions (SocketException,
  /// HandshakeException, etc.). Keeps the error message to the runtime type
  /// only to avoid inadvertently leaking socket-level details.
  ///
  /// Mirrored byte-for-byte by [LiveCommentRepository]; both copies are
  /// expected to be lifted into a shared base class by #464.
  BroadcastControlResult _handleException(Exception e, String operationName) {
    appErrorLog(
      name: 'BroadcastControlRepository',
      message: 'Error in $operationName',
      error: e,
    );
    return BroadcastControlResult(
      success: false,
      errorCode: 'NETWORK_ERROR',
      errorMessage: e.runtimeType.toString(),
    );
  }

  void _setHeaders(HttpClientRequest request, String userSession) {
    request.headers.set('Cookie', 'user_session=$userSession');
    request.headers.set('X-Niconico-Session', userSession);
    request.headers.set('User-Agent', _userAgent);
    request.headers.set('Content-Type', 'application/json');
  }

  Future<BroadcastControlResult> _parseResponse(
    HttpClientResponse response,
    String operationName,
  ) async {
    // HTTP 204: success with no body (some endpoints).
    if (response.statusCode == 204) {
      await response.drain<void>();
      return const BroadcastControlResult(success: true);
    }

    final String body = await response.transform(utf8.decoder).join();

    if (response.statusCode == 200) {
      return _parseSuccessBody(body, operationName);
    }

    return _parseErrorBody(body, response.statusCode, operationName);
  }

  BroadcastControlResult _parseSuccessBody(String body, String operationName) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      appDebugLogLazy(
        () =>
            '[BroadcastControlRepository] $operationName: unexpected response type: ${decoded.runtimeType}',
      );
      return const BroadcastControlResult(success: true);
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      return const BroadcastControlResult(success: true);
    }

    return BroadcastControlResult(
      success: true,
      startTime: data['start_time'] as int?,
      endTime: data['end_time'] as int?,
    );
  }

  BroadcastControlResult _parseErrorBody(
    String body,
    int statusCode,
    String operationName,
  ) {
    appDebugLogLazy(
      () =>
          '[BroadcastControlRepository] $operationName failed: HTTP $statusCode',
    );

    String? errorCode;
    String? errorMessage;

    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final Object? meta = decoded['meta'];
        if (meta is Map<String, dynamic>) {
          errorCode = meta['errorCode'] as String?;
          errorMessage = meta['errorMessage'] as String?;
        }
        if (errorMessage == null) {
          final Object? data = decoded['data'];
          if (data is Map<String, dynamic>) {
            errorMessage = data['message'] as String?;
          }
        }
      }
    } on FormatException {
      // Non-JSON error response — use status code.
    }

    // Map common HTTP status codes to readable error codes.
    errorCode ??= _httpStatusToErrorCode(statusCode);

    return BroadcastControlResult(
      success: false,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  static String _httpStatusToErrorCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'BAD_REQUEST';
      case 401:
        return 'UNAUTHORIZED';
      case 403:
        return 'FORBIDDEN';
      case 404:
        return 'NOT_FOUND';
      case 409:
        return 'CONFLICT';
      default:
        return 'HTTP_$statusCode';
    }
  }

  void dispose() {
    _httpClient.close();
  }
}
