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

    errorCode ??= httpStatusToErrorCode(statusCode);

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
}
