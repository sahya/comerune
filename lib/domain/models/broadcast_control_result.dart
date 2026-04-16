/// Result of a broadcast control operation (start, stop, or extend).
class BroadcastControlResult {
  const BroadcastControlResult({
    required this.success,
    this.startTime,
    this.endTime,
    this.errorCode,
    this.errorMessage,
  });

  /// Whether the operation completed successfully.
  final bool success;

  /// Unix timestamp (seconds) when the broadcast started.
  final int? startTime;

  /// Unix timestamp (seconds) when the broadcast ends (or ended).
  final int? endTime;

  /// Error code from the API or a client-side rejection.
  ///
  /// See [BroadcastControlErrorCode] for the canonical set of known codes.
  final String? errorCode;

  /// Human-readable error description.
  ///
  /// Used for logging / debugging. The presentation layer maps user-visible
  /// messages from [errorCode] via `userFacingBroadcastError`, so the raw
  /// `errorMessage` does not need to be localised.
  final String? errorMessage;

  /// Whether the error indicates the program already ended (HTTP 409).
  bool get isAlreadyEnded => errorCode == BroadcastControlErrorCode.conflict;
}

/// Canonical error-code strings used by [BroadcastControlResult.errorCode].
///
/// Centralizing these avoids drift between the data layer (which produces
/// them) and the presentation layer (which maps them to user-facing
/// messages). The values are the wire strings we return to callers; they
/// are stable and safe to depend on.
///
/// Mirrors `CommentPostErrorCode` for symmetry between the two niconico
/// repositories.
class BroadcastControlErrorCode {
  const BroadcastControlErrorCode._();

  /// Client-side rejection: `programId` or `userSession` was empty.
  ///
  /// Distinguished from [malformedInput] so the UI can surface a
  /// sign-in prompt only in the truly-empty case.
  static const String invalidParams = 'INVALID_PARAMS';

  /// Client-side rejection: `programId` or `userSession` contained
  /// characters that could be used for CRLF header injection or lv path
  /// injection (see
  /// `NiconicoAuthedHttpClient.isValidAuthHeaderValue` /
  /// `NiconicoAuthedHttpClient.isValidLv`).
  ///
  /// Distinguished from [invalidParams] so the UI can surface a
  /// "malformed input" message instead of a misleading sign-in prompt
  /// when the fields are non-empty but structurally bad.
  static const String malformedInput = 'MALFORMED_INPUT';

  /// HTTP 400 — malformed request from the server's perspective.
  static const String badRequest = 'BAD_REQUEST';

  /// HTTP 401 — session missing or expired.
  static const String unauthorized = 'UNAUTHORIZED';

  /// HTTP 403 — caller does not have permission to control this program.
  static const String forbidden = 'FORBIDDEN';

  /// HTTP 404 — program not found (ended / private / typo).
  static const String notFound = 'NOT_FOUND';

  /// HTTP 409 — state conflict (e.g. program already ended).
  static const String conflict = 'CONFLICT';

  /// Transport-level exception (socket / timeout / TLS).
  static const String networkError = 'NETWORK_ERROR';
}
