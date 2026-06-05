import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../app_logging.dart';
import '../../domain/models/comment_post_result.dart';
import '../niconico/niconico_authed_http_client.dart';

/// Re-exports [CommentPostResult] from the domain layer.
///
/// Prefer importing `package:comerune/domain/models/comment_post_result.dart`
/// directly in new code.
export '../../domain/models/comment_post_result.dart';

/// Posts live comments to niconico (normal viewer comments and operator
/// comments).
///
/// Uses the same API surface as N Air:
/// - Operator comment: `PUT /watch/{programId}/operator_comment`
///   with `{ "text": "...", "isPermCommand": false }`.
/// - Normal comment:   `POST /unama/tool/v2/programs/{programId}/comments`
///   with `{ "text": "...", "vpos": N }` and the `x-frontend-id: 134` header.
class LiveCommentRepository extends NiconicoAuthedHttpClient {
  LiveCommentRepository({
    HttpClient? httpClient,
    String userAgent = NiconicoAuthedHttpClient.defaultUserAgent,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : super(
         httpClient: httpClient,
         userAgent: userAgent,
         requestTimeout: requestTimeout,
       );

  static const String _operatorBaseUrl = 'https://live2.nicovideo.jp/watch';
  static const String _normalBaseUrl =
      'https://live2.nicovideo.jp/unama/tool/v2/programs';

  /// `x-frontend-id` value expected by the normal comment endpoint.
  /// 134 is the value N Air uses and is required for the endpoint to accept
  /// the request.
  static const String _frontendId = '134';

  /// Log tag used for error / debug logging in this repository.
  static const String _logName = 'LiveCommentRepository';

  /// Posts an operator comment (broadcaster only).
  ///
  /// [programId] must be a valid program id (e.g. "lv348712105"). The
  /// [userSession] must be non-empty. [text] is sent as-is (caller is
  /// responsible for client-side length validation).
  ///
  /// [isPermCommand] is forwarded to the API but the current UI always sends
  /// `false`. Kept as a parameter for symmetry with the API.
  Future<CommentPostResult> postOperatorComment({
    required String programId,
    required String userSession,
    required String text,
    bool isPermCommand = false,
  }) async {
    if (kDebugMode) {
      appDebugLog(
        '[$_logName] postOperatorComment START: '
        'programId=$programId text="${text.length > 20 ? '${text.substring(0, 20)}...' : text}" '
        '(${text.length} chars) isPermCommand=$isPermCommand',
      );
    }

    final CommentPostResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postOperatorComment ABORTED by input validation: '
          'errorCode=${invalid.errorCode} errorMessage=${invalid.errorMessage}',
        );
      }
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse(
        '$_operatorBaseUrl/$programId/operator_comment',
      );
      if (kDebugMode) {
        appDebugLog('[$_logName] postOperatorComment PUT $uri');
      }
      request = await httpClient.putUrl(uri);
      setAuthHeaders(request, userSession);

      final Map<String, Object> body = <String, Object>{
        'text': text,
        'isPermCommand': isPermCommand,
      };
      final String encodedBody = jsonEncode(body);
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postOperatorComment request body: $encodedBody',
        );
      }
      request.write(encodedBody);

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postOperatorComment response: '
          'HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
        _debugLogResponseHeaders(response, 'postOperatorComment');
      }
      return await _parseResponse(response, 'postOperatorComment');
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, 'postOperatorComment');
    } on Exception catch (e) {
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postOperatorComment EXCEPTION: '
          '${e.runtimeType}: $e',
        );
      }
      return _toExceptionResult(e, 'postOperatorComment');
    }
  }

  /// Posts a normal viewer comment.
  ///
  /// [programId] must be a valid program id, [userSession] must be non-empty,
  /// and [vpos] is the 1/100-second offset from the program's `beginAt`.
  /// Caller should validate [text] length before calling.
  ///
  /// When [isAnonymous] is `true`, the request asks the server to treat the
  /// comment as a 184 (anonymous) post so the viewer's nickname / id is not
  /// displayed to other clients. When `false` (the default) the request body
  /// is byte-identical to the pre-toggle form (`{text, vpos}`), guaranteeing
  /// zero regression for existing callers.
  Future<CommentPostResult> postNormalComment({
    required String programId,
    required String userSession,
    required String text,
    required int vpos,
    bool isAnonymous = false,
  }) async {
    if (kDebugMode) {
      appDebugLog(
        '[$_logName] postNormalComment START: '
        'programId=$programId '
        'text="${text.length > 20 ? '${text.substring(0, 20)}...' : text}" '
        '(${text.length} chars) vpos=$vpos isAnonymous=$isAnonymous',
      );
    }

    final CommentPostResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postNormalComment ABORTED by input validation: '
          'errorCode=${invalid.errorCode} errorMessage=${invalid.errorMessage}',
        );
      }
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_normalBaseUrl/$programId/comments');
      if (kDebugMode) {
        appDebugLog('[$_logName] postNormalComment POST $uri');
      }
      request = await httpClient.postUrl(uri);
      setAuthHeaders(request, userSession);
      request.headers.set('x-frontend-id', _frontendId);
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postNormalComment x-frontend-id=$_frontendId '
          '(NOTE: 134 is N-Air\'s registered ID; may need a different '
          'value for this client)',
        );
      }

      final Map<String, Object> bodyMap = _buildNormalCommentBody(
        text: text,
        vpos: vpos,
        isAnonymous: isAnonymous,
      );
      final String encodedBody = jsonEncode(bodyMap);
      if (kDebugMode) {
        appDebugLog('[$_logName] postNormalComment request body: $encodedBody');
      }
      request.write(encodedBody);

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postNormalComment response: '
          'HTTP ${response.statusCode} ${response.reasonPhrase}',
        );
        _debugLogResponseHeaders(response, 'postNormalComment');
      }
      return await _parseResponse(response, 'postNormalComment');
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, 'postNormalComment');
    } on Exception catch (e) {
      if (kDebugMode) {
        appDebugLog(
          '[$_logName] postNormalComment EXCEPTION: '
          '${e.runtimeType}: $e',
        );
      }
      return _toExceptionResult(e, 'postNormalComment');
    }
  }

  /// Maps a timeout into a [CommentPostResult] failure, delegating the
  /// abort + logging to the base class.
  CommentPostResult _toTimeoutResult(
    HttpClientRequest? request,
    TimeoutException e,
    String operationName,
  ) {
    final String message = handleTimeout(request, e, operationName, _logName);
    return CommentPostResult(
      success: false,
      errorCode: CommentPostErrorCode.networkError,
      errorMessage: message,
    );
  }

  /// Maps a non-timeout exception into a [CommentPostResult] failure,
  /// delegating the logging to the base class.
  CommentPostResult _toExceptionResult(Exception e, String operationName) {
    final String message = handleException(e, operationName, _logName);
    return CommentPostResult(
      success: false,
      errorCode: CommentPostErrorCode.networkError,
      errorMessage: message,
    );
  }

  /// Builds the JSON body for the normal-comment endpoint.
  ///
  /// Two shapes are known in the wild for the anonymous flag:
  /// - Candidate A: `{text, vpos, modifier: {isAnonymous: true}}` (same slot
  ///   niconico uses for color/size/position modifiers).
  /// - Candidate B: `{text, vpos, isAnonymous: true}` (top-level — the shape
  ///   Hakumai `NicoManager.swift` and nicolivehelperxx `main.js` both send
  ///   over the WebSocket comment stream).
  ///
  /// This implementation adopts **Candidate B** because both widely-used
  /// open-source niconico clients ship it in production. The HTTP
  /// `POST /unama/tool/v2/programs/{lv}/comments` endpoint has not been
  /// verified end-to-end by this project yet — see Issue #463's "実機検証"
  /// note.
  ///
  /// Invariants:
  /// - When [isAnonymous] is `false` the `isAnonymous` key is omitted
  ///   entirely. The resulting body is byte-identical to the pre-toggle
  ///   `{text, vpos}` body so the default call path is guaranteed free of
  ///   regressions.
  /// - When [isAnonymous] is `true` the flag is placed at the top level.
  ///
  /// TODO(#463): After a live-server trial confirms which shape the HTTP
  /// endpoint accepts, either remove this TODO (if Candidate B is correct)
  /// or switch the `isAnonymous: true` branch to emit
  /// `modifier: {isAnonymous: true}` instead. The switch is one-line because
  /// the body construction is localised to this helper.
  static Map<String, Object> _buildNormalCommentBody({
    required String text,
    required int vpos,
    required bool isAnonymous,
  }) {
    if (!isAnonymous) {
      return <String, Object>{'text': text, 'vpos': vpos};
    }
    return <String, Object>{'text': text, 'vpos': vpos, 'isAnonymous': true};
  }

  Future<CommentPostResult> _parseResponse(
    HttpClientResponse response,
    String operationName,
  ) async {
    if (kDebugMode) {
      appDebugLog(
        '[$_logName] _parseResponse($operationName): '
        'statusCode=${response.statusCode}',
      );
    }

    // HTTP 204: success with no body.
    if (response.statusCode == 204) {
      if (kDebugMode) {
        appDebugLog('[$_logName] $operationName SUCCESS (HTTP 204 No Content)');
      }
      await response.drain<void>();
      return const CommentPostResult(success: true);
    }

    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(requestTimeout);

    if (kDebugMode) {
      appDebugLog(
        '[$_logName] $operationName response body '
        '(${body.length} chars): '
        '${body.length > 2000 ? '${body.substring(0, 2000)}...(truncated)' : body}',
      );
    }

    if (response.statusCode == 200) {
      final CommentPostResult? metaError = _parseMetaError(body);
      if (metaError != null) {
        if (kDebugMode) {
          appDebugLog(
            '[$_logName] $operationName FAILED via meta error: '
            'errorCode=${metaError.errorCode} '
            'errorMessage=${metaError.errorMessage}',
          );
        }
        return metaError;
      }
      if (kDebugMode) {
        appDebugLog('[$_logName] $operationName SUCCESS (HTTP 200, meta OK)');
      }
      return const CommentPostResult(success: true);
    }

    if (kDebugMode) {
      appDebugLog(
        '[$_logName] $operationName HTTP error ${response.statusCode}, '
        'parsing error body...',
      );
    }
    final NiconicoErrorFields error = parseErrorBody(
      body,
      response.statusCode,
      operationName,
      _logName,
    );
    if (kDebugMode) {
      appDebugLog(
        '[$_logName] $operationName FAILED: '
        'errorCode=${error.errorCode} errorMessage=${error.errorMessage}',
      );
    }
    return CommentPostResult(
      success: false,
      errorCode: error.errorCode,
      errorMessage: error.errorMessage,
    );
  }

  void _debugLogResponseHeaders(
    HttpClientResponse response,
    String operationName,
  ) {
    if (!kDebugMode) {
      return;
    }
    final StringBuffer sb = StringBuffer();
    sb.writeln('[$_logName] $operationName response headers:');
    response.headers.forEach((String name, List<String> values) {
      sb.writeln('  $name: ${values.join(', ')}');
    });
    appDebugLog(sb.toString());
  }

  /// Returns a failure [CommentPostResult] when the response body advertises
  /// an error via `meta.status` / `meta.errorCode`, or `null` when the body
  /// indicates success (or is non-JSON / empty, in which case the HTTP status
  /// is authoritative).
  static CommentPostResult? _parseMetaError(String body) {
    if (body.isEmpty) {
      if (kDebugMode) {
        appDebugLog('[LiveCommentRepository] _parseMetaError: empty body');
      }
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      if (kDebugMode) {
        appDebugLog('[LiveCommentRepository] _parseMetaError: not JSON: $e');
      }
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      if (kDebugMode) {
        appDebugLog(
          '[LiveCommentRepository] _parseMetaError: decoded is not Map, '
          'type=${decoded.runtimeType}',
        );
      }
      return null;
    }
    final Object? meta = decoded['meta'];
    if (meta is! Map<String, dynamic>) {
      if (kDebugMode) {
        appDebugLog(
          '[LiveCommentRepository] _parseMetaError: no meta map, '
          'meta=${meta.runtimeType}: $meta',
        );
      }
      return null;
    }
    final Object? status = meta['status'];
    final Object? errorCode = meta['errorCode'];
    if (kDebugMode) {
      appDebugLog(
        '[LiveCommentRepository] _parseMetaError: '
        'meta.status=$status (${status.runtimeType}) '
        'meta.errorCode=$errorCode (${errorCode.runtimeType}) '
        'all meta keys: ${meta.keys.toList()}',
      );
    }
    final bool statusIsOk =
        (status is int && status == 200) ||
        (status is String && status == '200');
    final bool errorCodeIsOk =
        errorCode == null || (errorCode is String && errorCode == 'OK');
    if (errorCode is String && errorCode == 'OK') {
      if (kDebugMode) {
        appDebugLog(
          '[LiveCommentRepository] _parseMetaError: errorCode=OK → success',
        );
      }
      return null;
    }
    if (statusIsOk && errorCodeIsOk) {
      if (kDebugMode) {
        appDebugLog(
          '[LiveCommentRepository] _parseMetaError: status+errorCode OK → success',
        );
      }
      return null;
    }
    // Otherwise treat as failure even though HTTP was 200.
    final String? resolvedCode = errorCode is String && errorCode.isNotEmpty
        ? errorCode
        : (status is int
              ? 'HTTP_$status'
              : (status is String ? 'HTTP_$status' : 'UNKNOWN'));
    final Object? rawMessage = meta['errorMessage'];
    String? resolvedMessage = rawMessage is String ? rawMessage : null;
    if (resolvedMessage == null) {
      final Object? data = decoded['data'];
      if (data is Map<String, dynamic>) {
        final Object? message = data['message'];
        if (message is String) {
          resolvedMessage = message;
        }
      }
    }
    if (kDebugMode) {
      appDebugLog(
        '[LiveCommentRepository] _parseMetaError FAILURE: '
        'resolvedCode=$resolvedCode resolvedMessage=$resolvedMessage '
        'full body=$body',
      );
    }
    return CommentPostResult(
      success: false,
      errorCode: resolvedCode,
      errorMessage: resolvedMessage,
    );
  }

  /// Overrides the base mapping to include HTTP 429 (rate-limiting),
  /// which is specific to comment endpoints.
  @override
  String httpStatusToErrorCode(int statusCode) {
    if (statusCode == 429) {
      return CommentPostErrorCode.rateLimited;
    }
    return super.httpStatusToErrorCode(statusCode);
  }

  /// Thin wrapper around [NiconicoAuthedHttpClient.validateCallInputs]
  /// that maps the shared validation outcome to a [CommentPostResult]
  /// failure, or returns `null` when the call may proceed. See the
  /// base-class method for validation semantics.
  CommentPostResult? _checkCallInputs({
    required String programId,
    required String userSession,
  }) {
    if (kDebugMode) {
      appDebugLog(
        '[$_logName] _checkCallInputs: programId=$programId '
        'session.length=${userSession.length}',
      );
    }
    final NiconicoInputValidationStatus status = validateCallInputs(
      programId: programId,
      userSession: userSession,
      logName: _logName,
    );
    if (kDebugMode) {
      appDebugLog('[$_logName] _checkCallInputs result: $status');
    }
    switch (status) {
      case NiconicoInputValidationStatus.ok:
        return null;
      case NiconicoInputValidationStatus.empty:
        return const CommentPostResult(
          success: false,
          errorCode: CommentPostErrorCode.invalidParams,
          errorMessage: 'programId and userSession are required',
        );
      case NiconicoInputValidationStatus.malformed:
        return const CommentPostResult(
          success: false,
          errorCode: CommentPostErrorCode.malformedInput,
          errorMessage: 'userSession or programId contains invalid characters',
        );
    }
  }
}
