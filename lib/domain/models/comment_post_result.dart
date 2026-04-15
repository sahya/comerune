/// Result of a comment post operation (normal or operator comment).
class CommentPostResult {
  const CommentPostResult({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });

  /// Whether the operation completed successfully.
  final bool success;

  /// Error code from the API (e.g. "FORBIDDEN", "BAD_REQUEST") or a mapped
  /// HTTP status code (e.g. "HTTP_500") when no error code is present.
  /// See [CommentPostErrorCode] for the canonical set of known codes.
  final String? errorCode;

  /// Human-readable error description, if provided by the server.
  final String? errorMessage;
}

/// Canonical error-code strings used by [CommentPostResult.errorCode].
///
/// Centralizing these avoids drift between the data layer (which produces
/// them) and the presentation layer (which maps them to user-facing
/// messages). The values are the wire strings we return to callers; they
/// are stable and safe to depend on.
class CommentPostErrorCode {
  const CommentPostErrorCode._();

  /// Client-side rejection: `programId` or `userSession` was empty.
  static const String invalidParams = 'INVALID_PARAMS';

  /// HTTP 400 — malformed request (e.g. text too long on the server side).
  static const String badRequest = 'BAD_REQUEST';

  /// HTTP 401 — session missing or expired.
  static const String unauthorized = 'UNAUTHORIZED';

  /// HTTP 403 — caller does not have permission (e.g. posting operator
  /// comment while not the broadcaster).
  static const String forbidden = 'FORBIDDEN';

  /// HTTP 404 — program not found (ended / private / typo).
  static const String notFound = 'NOT_FOUND';

  /// HTTP 409 — state conflict (e.g. program already ended).
  static const String conflict = 'CONFLICT';

  /// HTTP 429 — too many requests; user must back off.
  static const String rateLimited = 'RATE_LIMITED';

  /// Transport-level exception (socket / timeout / TLS).
  static const String networkError = 'NETWORK_ERROR';
}
