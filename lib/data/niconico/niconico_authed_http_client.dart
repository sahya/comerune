import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../../app_logging.dart';

/// Parsed error fields extracted from a niconico API error response body.
///
/// Used by [NiconicoAuthedHttpClient.parseErrorBody] to return raw error data
/// without coupling to a specific result type. Each repository subclass maps
/// this into its own domain result (e.g. `BroadcastControlResult`,
/// `CommentPostResult`).
class NiconicoErrorFields {
  const NiconicoErrorFields({this.errorCode, this.errorMessage});

  /// Error code from `meta.errorCode` or a mapped HTTP status code.
  final String? errorCode;

  /// Human-readable error description from `meta.errorMessage` or
  /// `data.message`.
  final String? errorMessage;
}

/// Common HTTP plumbing for authenticated niconico live API clients.
///
/// Encapsulates the shared boilerplate that every niconico repository needs:
/// default User-Agent, connection timeout, auth header assembly, error body
/// parsing, HTTP-status-to-error-code mapping, request timeout handling, and
/// `HttpClient` lifecycle.
///
/// Subclasses provide their own endpoint URLs, request bodies, and
/// domain-specific result types. This base class intentionally does **not**
/// know about `BroadcastControlResult` or `CommentPostResult` — it returns
/// raw strings / [NiconicoErrorFields] and lets each subclass wrap them.
///
/// Design note: extracted by issue #464 to eliminate byte-for-byte duplication
/// between `BroadcastControlRepository` and `LiveCommentRepository`.
abstract class NiconicoAuthedHttpClient {
  NiconicoAuthedHttpClient({
    HttpClient? httpClient,
    String userAgent = defaultUserAgent,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : httpClient = httpClient ?? HttpClient(),
       userAgent = userAgent,
       requestTimeout = requestTimeout {
    this.httpClient.connectionTimeout = const Duration(seconds: 10);
  }

  /// Default User-Agent string shared across all niconico API clients.
  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  /// The underlying HTTP client. Exposed to subclasses for making requests.
  ///
  /// Marked `@protected`: only subclasses should reference this directly.
  /// Tests construct a real subclass to exercise behaviour, so they do not
  /// need this field externally.
  @protected
  final HttpClient httpClient;

  /// The User-Agent string for this client instance.
  @protected
  final String userAgent;

  /// Deadline for the full request/response roundtrip after the TCP
  /// connection has been established. `HttpClient.connectionTimeout` only
  /// guards the initial connect; without this guard a stalled server keeps
  /// the call hanging indefinitely.
  @protected
  final Duration requestTimeout;

  /// Sets the standard authentication and content headers on a request.
  ///
  /// Headers set:
  /// - `Cookie: user_session=<userSession>`
  /// - `X-Niconico-Session: <userSession>`
  /// - `User-Agent: <userAgent>`
  /// - `Content-Type: application/json`
  /// - `Accept: application/json`
  ///
  /// `Accept: application/json` is included to prevent CDN / WAF layers from
  /// returning an HTML error page that the JSON parser would silently treat
  /// as a non-JSON success body.
  ///
  /// Subclasses may add additional headers after calling this method.
  @protected
  void setAuthHeaders(HttpClientRequest request, String userSession) {
    request.headers.set('Cookie', 'user_session=$userSession');
    request.headers.set('X-Niconico-Session', userSession);
    request.headers.set('User-Agent', userAgent);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');

    appDebugLogLazy(
      () =>
          '[NiconicoAuthedHttpClient] setAuthHeaders: '
          'method=${request.method} url=${request.uri} '
          'session=${debugMaskSession(userSession)} (${userSession.length} chars)',
    );
  }

  /// Parses a non-success HTTP response body and extracts error fields.
  ///
  /// Attempts to decode the [body] as JSON and extract:
  /// 1. `meta.errorCode` and `meta.errorMessage`
  /// 2. `data.message` as a fallback for `errorMessage`
  /// 3. [httpStatusToErrorCode] mapping when no `meta.errorCode` is present
  ///
  /// Logs the failure at debug level using the [logName] (repository class
  /// name) and [operationName] (method name).
  @protected
  NiconicoErrorFields parseErrorBody(
    String body,
    int statusCode,
    String operationName,
    String logName,
  ) {
    appDebugLogLazy(() => '[$logName] $operationName failed: HTTP $statusCode');
    appDebugLogLazy(
      () =>
          '[$logName] $operationName response body (${body.length} chars): '
          '${body.length > 2000 ? '${body.substring(0, 2000)}...(truncated)' : body}',
    );

    String? errorCode;
    String? errorMessage;

    try {
      final Object? decoded = jsonDecode(body);
      appDebugLogLazy(
        () =>
            '[$logName] $operationName parsed JSON type: '
            '${decoded.runtimeType}',
      );
      if (decoded is Map<String, dynamic>) {
        final Object? meta = decoded['meta'];
        appDebugLogLazy(() => '[$logName] $operationName meta: $meta');
        if (meta is Map<String, dynamic>) {
          errorCode = meta['errorCode'] as String?;
          errorMessage = meta['errorMessage'] as String?;
          appDebugLogLazy(
            () =>
                '[$logName] $operationName meta.errorCode=$errorCode '
                'meta.errorMessage=$errorMessage '
                'meta.status=${meta['status']}',
          );
        }
        if (errorMessage == null) {
          final Object? data = decoded['data'];
          if (data is Map<String, dynamic>) {
            errorMessage = data['message'] as String?;
            appDebugLogLazy(
              () => '[$logName] $operationName data.message=$errorMessage',
            );
          }
        }
      }
    } on FormatException catch (e) {
      appDebugLogLazy(() => '[$logName] $operationName body is not JSON: $e');
    }

    errorCode ??= httpStatusToErrorCode(statusCode);

    appDebugLogLazy(
      () =>
          '[$logName] $operationName final error: '
          'code=$errorCode message=$errorMessage',
    );

    return NiconicoErrorFields(
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  /// Maps common HTTP status codes to readable error code strings.
  ///
  /// Subclasses may override to add endpoint-specific status codes (e.g.
  /// HTTP 429 for rate-limiting on comment endpoints).
  @protected
  String httpStatusToErrorCode(int statusCode) {
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

  /// Aborts a stalled request and logs a timeout error, returning the
  /// timeout exception's `toString()` as the error message for the caller.
  ///
  /// `abort()` is idempotent per the Dart SDK, so it is safe even if the
  /// request has already completed by the time we enter the handler.
  ///
  /// `e.toString()` (rather than `e.runtimeType.toString()`) is returned so
  /// the failure message preserves the configured timeout duration, aiding
  /// incident triage without leaking any user / session data.
  @protected
  String handleTimeout(
    HttpClientRequest? request,
    TimeoutException e,
    String operationName,
    String logName,
  ) {
    request?.abort();
    appErrorLog(name: logName, message: 'Timeout in $operationName', error: e);
    return e.toString();
  }

  /// Logs a non-timeout exception and returns the runtime type as the error
  /// message (avoids leaking socket-level details such as remote IP, file
  /// descriptors, or partial request payloads).
  @protected
  String handleException(Exception e, String operationName, String logName) {
    appErrorLog(name: logName, message: 'Error in $operationName', error: e);
    return e.runtimeType.toString();
  }

  /// Closes the underlying [HttpClient].
  void dispose() {
    httpClient.close();
  }

  /// Defensive check: reject values containing CR (0x0D), LF (0x0A), or NUL
  /// (0x00) which could otherwise split the `Cookie` / `X-Niconico-Session`
  /// headers and inject arbitrary request headers.
  ///
  /// Scope is intentionally limited to the three ASCII control characters
  /// that classic CRLF-injection advisories cite: `HttpHeaders.set` does not
  /// sanitise the value, but niconico's `user_session` is URL-safe in
  /// practice, so stricter filtering (e.g. U+0085 / U+2028 / U+2029 or all
  /// C0 controls) would risk rejecting otherwise valid sessions for no
  /// additional protection in a niconico-only context.
  ///
  /// Other C0 controls (VT `0x0B`, FF `0x0C`) are **not** filtered: Dart's
  /// `HttpHeaders.set` treats the header value as an opaque string and does
  /// not interpret VT / FF as line separators when emitting bytes on the
  /// wire, so they do not enable header injection in this code path.
  /// Filtering them would only add opportunity for false-positive rejection
  /// of unusual-but-legitimate session tokens.
  ///
  /// Contract: never throws. Returns `false` for any value containing a
  /// filtered character; `true` (including for empty string — emptiness is
  /// the caller's concern via the entry-guard) otherwise.
  ///
  /// Shared by [BroadcastControlRepository] and [LiveCommentRepository] via
  /// the shared [validateCallInputs] entry-guard.
  static bool isValidAuthHeaderValue(String value) {
    for (int i = 0; i < value.length; i++) {
      final int c = value.codeUnitAt(i);
      if (c == 0x00 || c == 0x0A || c == 0x0D) {
        return false;
      }
    }
    return true;
  }

  /// niconico live program IDs are of the form `lv` + decimal digits. Reject
  /// anything else so a malformed program id cannot inject extra URL path
  /// segments (e.g. `lv123/../admin`), query strings (`lv123?foo=bar`) or
  /// fragments (`lv123#frag`) when interpolated into a request URL.
  ///
  /// Only ASCII `0`–`9` are accepted — full-width (`１２３`), Arabic-Indic
  /// digits and other Unicode decimal numerals are rejected because the
  /// niconico API normalises ids as ASCII decimals.
  ///
  /// Contract: never throws. Returns `false` for any structurally invalid
  /// value; `true` only when the input is exactly `lv` + one or more ASCII
  /// decimal digits.
  ///
  /// Shared by [BroadcastControlRepository] and [LiveCommentRepository] via
  /// the shared [validateCallInputs] entry-guard.
  static bool isValidLv(String lv) {
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

  /// Shared entry-guard for repository call inputs.
  ///
  /// Centralises the previously duplicated empty / malformed-value checks
  /// so `BroadcastControlRepository` and `LiveCommentRepository` apply
  /// identical CRLF / NUL / lv path-injection filtering and emit a single
  /// audit-log entry per rejection.
  ///
  /// Returns:
  /// - [NiconicoInputValidationStatus.ok] when the call may proceed.
  /// - [NiconicoInputValidationStatus.empty] when either field is empty
  ///   (`userSession` is checked after `trim()` to reject whitespace-only
  ///   sessions).
  /// - [NiconicoInputValidationStatus.malformed] when either field contains
  ///   characters that would violate [isValidAuthHeaderValue] /
  ///   [isValidLv]. A debug log line is emitted in this case, tagged with
  ///   [logName], so audit trails survive even though callers map both
  ///   rejection causes to domain-specific failure results.
  ///
  /// Contract: never throws. The emptiness check runs before the malformed
  /// check so callers can report the more specific "required" message.
  @protected
  NiconicoInputValidationStatus validateCallInputs({
    required String programId,
    required String userSession,
    required String logName,
  }) {
    appDebugLogLazy(
      () =>
          '[$logName] validateCallInputs: '
          'programId=$programId '
          'session=${debugMaskSession(userSession)} (${userSession.length} chars, '
          'trimmed=${userSession.trim().length} chars)',
    );
    if (programId.isEmpty || userSession.trim().isEmpty) {
      appDebugLogLazy(
        () =>
            '[$logName] validateCallInputs REJECTED: '
            'programId.isEmpty=${programId.isEmpty} '
            'userSession.trim().isEmpty=${userSession.trim().isEmpty}',
      );
      return NiconicoInputValidationStatus.empty;
    }
    final bool sessionOk = isValidAuthHeaderValue(userSession);
    final bool lvOk = isValidLv(programId);
    if (!sessionOk || !lvOk) {
      appDebugLogLazy(
        () =>
            '[$logName] input rejected: '
            'session=${sessionOk ? 'ok' : 'bad'} lv=${lvOk ? 'ok' : 'bad'}',
      );
      return NiconicoInputValidationStatus.malformed;
    }
    appDebugLogLazy(() => '[$logName] validateCallInputs: OK');
    return NiconicoInputValidationStatus.ok;
  }
}

/// Outcome of [NiconicoAuthedHttpClient.validateCallInputs].
///
/// Each repository maps these cases to its own domain-specific failure
/// result (e.g. `BroadcastControlResult`, `CommentPostResult`) rather than
/// the base class doing the mapping, so the base stays free of
/// presentation-layer error-code vocabulary.
enum NiconicoInputValidationStatus {
  /// Inputs pass all checks; the caller may proceed with the HTTP request.
  ok,

  /// `programId` or `userSession` was empty / whitespace-only.
  empty,

  /// `programId` or `userSession` contained characters that could be used
  /// for CRLF header injection or lv path injection.
  malformed,
}
