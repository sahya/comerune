import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    final CommentPostResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse(
        '$_operatorBaseUrl/$programId/operator_comment',
      );
      request = await httpClient.putUrl(uri);
      setAuthHeaders(request, userSession);
      request.write(
        jsonEncode(<String, Object>{
          'text': text,
          'isPermCommand': isPermCommand,
        }),
      );

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      return await _parseResponse(response, 'postOperatorComment');
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, 'postOperatorComment');
    } on Exception catch (e) {
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
    final CommentPostResult? invalid = _checkCallInputs(
      programId: programId,
      userSession: userSession,
    );
    if (invalid != null) {
      return invalid;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_normalBaseUrl/$programId/comments');
      request = await httpClient.postUrl(uri);
      setAuthHeaders(request, userSession);
      request.headers.set('x-frontend-id', _frontendId);
      request.write(
        jsonEncode(
          _buildNormalCommentBody(
            text: text,
            vpos: vpos,
            isAnonymous: isAnonymous,
          ),
        ),
      );

      final HttpClientResponse response = await request.close().timeout(
        requestTimeout,
      );
      return await _parseResponse(response, 'postNormalComment');
    } on TimeoutException catch (e) {
      return _toTimeoutResult(request, e, 'postNormalComment');
    } on Exception catch (e) {
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
    // HTTP 204: success with no body.
    if (response.statusCode == 204) {
      await response.drain<void>();
      return const CommentPostResult(success: true);
    }

    final String body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(requestTimeout);

    if (response.statusCode == 200) {
      // N Air's `WrappedResult` treats `meta.status != 200` (or a non-"OK"
      // `errorCode`) as failure even when HTTP is 200 — comment endpoints
      // can return rate-limit / forbidden-word errors inside a 200 body.
      // Inspect the body and map to an error when present.
      final CommentPostResult? metaError = _parseMetaError(body);
      if (metaError != null) {
        appDebugLogLazy(
          () =>
              '[LiveCommentRepository] $operationName failed via meta: '
              '${metaError.errorCode}',
        );
        return metaError;
      }
      return const CommentPostResult(success: true);
    }

    final NiconicoErrorFields error = parseErrorBody(
      body,
      response.statusCode,
      operationName,
      _logName,
    );
    return CommentPostResult(
      success: false,
      errorCode: error.errorCode,
      errorMessage: error.errorMessage,
    );
  }

  /// Returns a failure [CommentPostResult] when the response body advertises
  /// an error via `meta.status` / `meta.errorCode`, or `null` when the body
  /// indicates success (or is non-JSON / empty, in which case the HTTP status
  /// is authoritative).
  static CommentPostResult? _parseMetaError(String body) {
    if (body.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final Object? meta = decoded['meta'];
    if (meta is! Map<String, dynamic>) {
      return null;
    }
    final Object? status = meta['status'];
    final Object? errorCode = meta['errorCode'];
    // Success shapes (defensively tolerate string/int for `status` since the
    // N Air type declares `number` but some related APIs serialize it as a
    // string):
    //   {status: 200}
    //   {status: "200"}
    //   {status: 200, errorCode: "OK"}
    //   {errorCode: "OK"}
    final bool statusIsOk =
        (status is int && status == 200) ||
        (status is String && status == '200');
    final bool errorCodeIsOk =
        errorCode == null || (errorCode is String && errorCode == 'OK');
    // Explicit OK code overrides a missing / odd status; otherwise require
    // both the status and error code to look healthy.
    if (errorCode is String && errorCode == 'OK') {
      return null;
    }
    if (statusIsOk && errorCodeIsOk) {
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

  /// Combined entry-guard for both post methods. Returns a failure
  /// [CommentPostResult] when the inputs are rejected, or `null` when the
  /// call may proceed. Centralises the previously duplicated empty /
  /// malformed-value checks so the two post methods stay in lock step and
  /// a single audit-log call covers both.
  CommentPostResult? _checkCallInputs({
    required String programId,
    required String userSession,
  }) {
    if (programId.isEmpty || userSession.trim().isEmpty) {
      return const CommentPostResult(
        success: false,
        errorCode: CommentPostErrorCode.invalidParams,
        errorMessage: 'programId and userSession are required',
      );
    }
    final bool sessionOk = _isValidHeaderValue(userSession);
    final bool lvOk = _isValidLv(programId);
    if (!sessionOk || !lvOk) {
      appDebugLogLazy(
        () =>
            '[LiveCommentRepository] input rejected: '
            'session=${sessionOk ? 'ok' : 'bad'} lv=${lvOk ? 'ok' : 'bad'}',
      );
      return const CommentPostResult(
        success: false,
        errorCode: CommentPostErrorCode.invalidParams,
        errorMessage: 'userSession or programId contains invalid characters',
      );
    }
    return null;
  }

  /// Defensive check: reject values containing CR, LF, or NUL which could
  /// otherwise split the `Cookie` / `X-Niconico-Session` headers and
  /// inject arbitrary request headers.
  ///
  /// Scope is intentionally limited to the three ASCII control characters
  /// that classic CRLF-injection advisories cite: Dart's `HttpHeaders.set`
  /// does not sanitise the value, but niconico's `user_session` is
  /// URL-safe in practice so stricter filtering (e.g. U+0085 / U+2028 /
  /// U+2029 or all C0 controls) would risk rejecting otherwise valid
  /// sessions for no additional protection in a niconico-only context.
  static bool _isValidHeaderValue(String value) {
    for (int i = 0; i < value.length; i++) {
      final int c = value.codeUnitAt(i);
      if (c == 0x00 || c == 0x0A || c == 0x0D) {
        return false;
      }
    }
    return true;
  }

  /// Live program IDs are of the form `lv` + decimal digits. Reject
  /// anything else so that a malformed program id cannot inject extra
  /// URL path segments (e.g. `lv123/../admin`) when interpolated into the
  /// request URL.
  ///
  /// Only ASCII `0`-`9` are accepted — full-width (`１２３`), Arabic-Indic
  /// digits and other Unicode decimal numerals are rejected because the
  /// niconico API normalises ids as ASCII decimals.
  static bool _isValidLv(String lv) {
    if (lv.length < 3 || !lv.startsWith('lv')) {
      return false;
    }
    for (int i = 2; i < lv.length; i++) {
      final int c = lv.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) {
        return false;
      }
    }
    return true;
  }
}
