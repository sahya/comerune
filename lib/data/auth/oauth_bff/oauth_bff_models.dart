import 'package:meta/meta.dart';

/// In-flight OIDC authorization state, generated when the user starts the
/// flow and validated when the App Links callback returns.
@immutable
class OAuthAuthorizationState {
  const OAuthAuthorizationState({
    required this.value,
    required this.createdAtMillisSinceEpoch,
  });

  /// The opaque `state` value sent on the authorize request and expected
  /// back unchanged on the callback.
  final String value;

  /// Wall-clock time (millis since epoch) the value was generated. Used to
  /// reject stale callbacks from abandoned flows.
  final int createdAtMillisSinceEpoch;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'createdAtMillisSinceEpoch': createdAtMillisSinceEpoch,
  };

  factory OAuthAuthorizationState.fromJson(Map<String, Object?> json) =>
      OAuthAuthorizationState(
        value: json['value']! as String,
        createdAtMillisSinceEpoch: json['createdAtMillisSinceEpoch']! as int,
      );
}

/// Tokens returned by the BFF after a successful exchange.
@immutable
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.tokenType,
    required this.expiresInSeconds,
    this.refreshToken,
    this.scope,
  });

  final String accessToken;
  final String tokenType;
  final int expiresInSeconds;
  final String? refreshToken;
  final String? scope;

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'tokenType': tokenType,
    'expiresInSeconds': expiresInSeconds,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (scope != null) 'scope': scope,
  };

  factory OAuthTokens.fromJson(Map<String, Object?> json) => OAuthTokens(
    accessToken: json['accessToken']! as String,
    tokenType: json['tokenType']! as String,
    expiresInSeconds: json['expiresInSeconds']! as int,
    refreshToken: json['refreshToken'] as String?,
    scope: json['scope'] as String?,
  );

  /// Parse an upstream RFC 6749 token endpoint response (snake_case keys)
  /// as forwarded by the BFF.
  factory OAuthTokens.fromUpstreamJson(Map<String, Object?> json) =>
      OAuthTokens(
        accessToken: json['access_token']! as String,
        tokenType: (json['token_type'] as String?) ?? 'Bearer',
        expiresInSeconds: (json['expires_in'] as num?)?.toInt() ?? 0,
        refreshToken: json['refresh_token'] as String?,
        scope: json['scope'] as String?,
      );
}

/// Error categories for the BFF token exchange and callback validation.
enum OAuthFailureReason {
  /// `error` parameter present on the callback URL (user cancelled or
  /// upstream rejected the authorization request).
  upstreamAuthorizationError,

  /// Callback URL missing `code` or `state`.
  malformedCallback,

  /// Callback `state` did not match the stored value, the stored state was
  /// missing entirely, or it was older than the configured max age.
  stateMismatch,

  /// BFF replied with a non-2xx, or the upstream token endpoint did and
  /// the BFF forwarded that response. Also used when the BFF JSON cannot
  /// be parsed into [OAuthTokens].
  tokenExchangeFailed,

  /// Network failure / timeout reaching the BFF.
  networkFailure,

  /// Persisting the in-flight state (before redirecting to the browser) or
  /// the freshly-exchanged tokens (after a successful BFF response) failed
  /// at the secure-storage layer. The flow cannot continue safely in this
  /// state because either the callback would not be validatable
  /// (state never persisted) or the user would have to re-authorize on
  /// the next app launch (tokens never persisted).
  persistenceFailed,
}

@immutable
class OAuthFailure implements Exception {
  const OAuthFailure({
    required this.reason,
    required this.message,
    this.upstreamError,
    this.upstreamErrorDescription,
    this.httpStatus,
  });

  final OAuthFailureReason reason;
  final String message;

  /// `error` field from a forwarded RFC 6749 error JSON, when available.
  final String? upstreamError;

  /// `error_description` from a forwarded RFC 6749 error JSON, when available.
  final String? upstreamErrorDescription;

  /// HTTP status of the BFF response, when available.
  final int? httpStatus;

  @override
  String toString() {
    final buffer = StringBuffer('OAuthFailure(${reason.name}): $message');
    if (httpStatus != null) buffer.write(' [HTTP $httpStatus]');
    if (upstreamError != null) buffer.write(' upstream=$upstreamError');
    return buffer.toString();
  }
}
