import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app_logging.dart';
import '../../domain/models/broadcast_control_result.dart';
import '../niconico/niconico_authed_http_client.dart';

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
class BroadcastControlRepository extends NiconicoAuthedHttpClient {
  BroadcastControlRepository({
    HttpClient? httpClient,
    String userAgent = NiconicoAuthedHttpClient.defaultUserAgent,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : super(
         httpClient: httpClient,
         userAgent: userAgent,
         requestTimeout: requestTimeout,
       );

  static const String _baseUrl = 'https://live2.nicovideo.jp/watch';

  /// Log tag used for error / debug logging in this repository.
  static const String _logName = 'BroadcastControlRepository';

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
    final BroadcastControlResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_baseUrl/$programId/extension');
      request = await httpClient.postUrl(uri);
      setAuthHeaders(request, userSession);
      request.write(jsonEncode(<String, int>{'minutes': minutes}));

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      return await _parseResponse(response, 'extendBroadcast');
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, 'extendBroadcast');
    } on Exception catch (e) {
      return _toExceptionResult(e, 'extendBroadcast');
    }
  }

  Future<BroadcastControlResult> _updateSegmentState({
    required String programId,
    required String userSession,
    required String state,
    required String operationName,
  }) async {
    final BroadcastControlResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_baseUrl/$programId/segment');
      request = await httpClient.putUrl(uri);
      setAuthHeaders(request, userSession);
      request.write(jsonEncode(<String, String>{'state': state}));

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      return await _parseResponse(response, operationName);
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, operationName);
    } on Exception catch (e) {
      return _toExceptionResult(e, operationName);
    }
  }

  /// Maps a timeout into a [BroadcastControlResult] failure, delegating
  /// the abort + logging to the base class.
  BroadcastControlResult _toTimeoutResult(
    HttpClientRequest? request,
    TimeoutException e,
    String operationName,
  ) {
    final String message = handleTimeout(request, e, operationName, _logName);
    return BroadcastControlResult(
      success: false,
      errorCode: 'NETWORK_ERROR',
      errorMessage: message,
    );
  }

  /// Maps a non-timeout exception into a [BroadcastControlResult] failure,
  /// delegating the logging to the base class.
  BroadcastControlResult _toExceptionResult(Exception e, String operationName) {
    final String message = handleException(e, operationName, _logName);
    return BroadcastControlResult(
      success: false,
      errorCode: 'NETWORK_ERROR',
      errorMessage: message,
    );
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

    // Apply the same response-wait timeout to the body-read phase as we do
    // around `request.close()`. Without this guard, a server that
    // responds with headers quickly but then stalls while streaming the
    // body would leave the broadcast-control call hanging indefinitely
    // (and mirrors the pattern already in place on
    // [LiveCommentRepository._parseResponse]). The surrounding callers
    // catch any [TimeoutException] thrown here and route it through
    // [_handleTimeout] so the underlying request is aborted and the UI
    // surfaces NETWORK_ERROR.
    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(requestTimeout);

    if (response.statusCode == 200) {
      return _parseSuccessBody(body, operationName);
    }

    final NiconicoErrorFields error = parseErrorBody(
      body,
      response.statusCode,
      operationName,
      _logName,
    );
    return BroadcastControlResult(
      success: false,
      errorCode: error.errorCode,
      errorMessage: error.errorMessage,
    );
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

  /// Combined entry-guard for all broadcast control methods. Returns a
  /// failure [BroadcastControlResult] when the inputs are rejected, or
  /// `null` when the call may proceed.
  ///
  /// Mirrors `LiveCommentRepository._checkCallInputs` to keep the two
  /// repositories in lock step on defensive input validation. The shared
  /// `isValidAuthHeaderValue` / `isValidLv` validators live on the base
  /// class [NiconicoAuthedHttpClient] so both repositories apply identical
  /// CRLF / NUL / lv path-injection filtering.
  ///
  /// The emptiness check runs before the malformed-value check so callers
  /// get the more specific "required" error message when a field is missing.
  BroadcastControlResult? _checkCallInputs({
    required String programId,
    required String userSession,
  }) {
    if (programId.isEmpty || userSession.trim().isEmpty) {
      return const BroadcastControlResult(
        success: false,
        errorCode: 'INVALID_PARAMS',
        errorMessage: 'programId and userSession are required',
      );
    }
    final bool sessionOk = NiconicoAuthedHttpClient.isValidAuthHeaderValue(
      userSession,
    );
    final bool lvOk = NiconicoAuthedHttpClient.isValidLv(programId);
    if (!sessionOk || !lvOk) {
      appDebugLogLazy(
        () =>
            '[$_logName] input rejected: '
            'session=${sessionOk ? 'ok' : 'bad'} lv=${lvOk ? 'ok' : 'bad'}',
      );
      return const BroadcastControlResult(
        success: false,
        errorCode: 'INVALID_PARAMS',
        errorMessage: 'userSession or programId contains invalid characters',
      );
    }
    return null;
  }
}
