import 'dart:async';
import 'dart:developer';

import 'package:app_links/app_links.dart';

import 'oauth_bff_client.dart';
import 'oauth_bff_config.dart';
import 'oauth_bff_models.dart';
import 'oauth_state_generator.dart';
import 'oauth_state_store.dart';
import 'oauth_token_store.dart';

/// Maximum age of a stored state value before it is treated as expired.
/// Upstream authorization codes are valid for ~10 minutes; a slightly
/// longer window here lets slow user flows succeed but still rejects stale
/// state from abandoned attempts.
const Duration kOAuthStateMaxAge = Duration(minutes: 15);

/// Result of a callback validation + token exchange attempt.
sealed class OAuthCallbackOutcome {
  const OAuthCallbackOutcome();
}

class OAuthCallbackSuccess extends OAuthCallbackOutcome {
  const OAuthCallbackSuccess(this.tokens);
  final OAuthTokens tokens;
}

class OAuthCallbackFailure extends OAuthCallbackOutcome {
  const OAuthCallbackFailure(this.failure);
  final OAuthFailure failure;
}

/// Top-level orchestrator for the OIDC + BFF flow.
///
/// Trigger a login by calling [startAuthorization] and opening the returned
/// URI externally (e.g. with `url_launcher`). When Android delivers the
/// callback URL via App Links, call [handleCallback] (or use
/// [attachAppLinks] to subscribe automatically). The service validates
/// state, calls the BFF, and updates the token store.
class OAuthBffAuthService {
  OAuthBffAuthService({
    required this.config,
    required this.stateGenerator,
    required this.stateStore,
    required this.tokenStore,
    required this.bffClient,
    Duration stateMaxAge = kOAuthStateMaxAge,
    DateTime Function() now = _defaultNow,
  }) : _stateMaxAge = stateMaxAge,
       _now = now;

  final OAuthBffConfig config;
  final OAuthStateGenerator stateGenerator;
  final OAuthStateStore stateStore;
  final OAuthTokenStore tokenStore;
  final OAuthBffClient bffClient;
  final Duration _stateMaxAge;
  final DateTime Function() _now;

  StreamSubscription<Uri>? _linkSubscription;

  /// Toggled once `dispose()` runs so any in-flight `handleCallback` whose
  /// async tail completes after teardown will not fire `onOutcome` against
  /// an already-disposed UI consumer.
  bool _disposed = false;

  /// Last App Links callback URI we have already routed through
  /// [handleCallback], used to deduplicate the case where the platform
  /// delivers the same cold-start URI both via [AppLinks.getInitialLink]
  /// and via the warm `uriLinkStream` shortly after subscription.
  String? _lastHandledCallbackUri;

  static DateTime _defaultNow() => DateTime.now();

  /// Generate a fresh state, persist it, and return the authorize URL.
  /// Throws [OAuthFailure] (`tokenExchangeFailed`) if the build was
  /// produced without `--dart-define=NICONICO_OAUTH_CLIENT_ID=...`.
  Future<Uri> startAuthorization() async {
    if (config.clientId.isEmpty) {
      throw const OAuthFailure(
        reason: OAuthFailureReason.tokenExchangeFailed,
        message:
            'OAuth client_id is not configured. '
            'Build with --dart-define=NICONICO_OAUTH_CLIENT_ID=...',
      );
    }
    final stateValue = stateGenerator.generate();
    final created = _now().millisecondsSinceEpoch;
    try {
      await stateStore.save(
        OAuthAuthorizationState(
          value: stateValue,
          createdAtMillisSinceEpoch: created,
        ),
      );
    } catch (e) {
      // Persisting state must not be silent: without it, the callback can't
      // be validated and an attacker-supplied state would slip through.
      log(
        'Failed to persist in-flight OAuth state '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
      throw const OAuthFailure(
        reason: OAuthFailureReason.persistenceFailed,
        message: 'Failed to persist in-flight authorization state',
      );
    }
    return Uri.parse(config.authorizeEndpoint).replace(
      queryParameters: <String, String>{
        'client_id': config.clientId,
        'response_type': 'code',
        'redirect_uri': config.redirectUri,
        'state': stateValue,
        'scope': config.scope,
      },
    );
  }

  /// Validate a callback URI and (on success) exchange the code for tokens.
  /// Always clears the persisted state at the end, regardless of outcome,
  /// so a single state value cannot be replayed.
  Future<OAuthCallbackOutcome> handleCallback(Uri callbackUri) async {
    final params = callbackUri.queryParameters;
    final upstreamError = params['error'];
    if (upstreamError != null && upstreamError.isNotEmpty) {
      await _safeClearState();
      return OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.upstreamAuthorizationError,
          message: 'Upstream authorization error: $upstreamError',
          upstreamError: upstreamError,
          upstreamErrorDescription: params['error_description'],
        ),
      );
    }

    final code = params['code'];
    final state = params['state'];
    if (code == null || code.isEmpty || state == null || state.isEmpty) {
      await _safeClearState();
      return const OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.malformedCallback,
          message: 'Callback missing code or state',
        ),
      );
    }

    final OAuthAuthorizationState? stored;
    try {
      stored = await stateStore.read();
    } catch (e) {
      // PlatformException from flutter_secure_storage (e.g. Keystore
      // unavailable / decryption failed) must not surface as a raw async
      // error inside the App Links stream listener — it would be silently
      // swallowed and the UI would never see an outcome.
      log(
        'Failed to read persisted OAuth state '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
      // Best-effort clear to avoid keeping a state we can't read.
      await _safeClearState();
      return const OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.persistenceFailed,
          message: 'Failed to read persisted authorization state',
        ),
      );
    }
    // Always clear the stored state once consumed so it cannot be replayed.
    await _safeClearState();

    if (stored == null) {
      return const OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.stateMismatch,
          message: 'No stored OAuth state to validate against',
        ),
      );
    }

    if (!_constantTimeEquals(stored.value, state)) {
      return const OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.stateMismatch,
          message: 'OAuth state mismatch',
        ),
      );
    }

    final ageMs =
        _now().millisecondsSinceEpoch - stored.createdAtMillisSinceEpoch;
    if (ageMs < 0 || ageMs > _stateMaxAge.inMilliseconds) {
      return OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.stateMismatch,
          message: 'Stored OAuth state expired (age ${ageMs}ms)',
        ),
      );
    }

    final OAuthTokens tokens;
    try {
      tokens = await bffClient.exchangeAuthorizationCode(
        code: code,
        redirectUri: config.redirectUri,
      );
    } on OAuthFailure catch (failure) {
      return OAuthCallbackFailure(failure);
    }

    try {
      await tokenStore.save(tokens);
    } catch (e) {
      // The exchange succeeded but secure-storage write failed. The user
      // received tokens we cannot persist; surfacing this as a failure is
      // safer than silently returning success — the next app launch would
      // not find the tokens and the user would re-authorize anyway.
      log(
        'Failed to persist tokens after successful exchange '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
      return const OAuthCallbackFailure(
        OAuthFailure(
          reason: OAuthFailureReason.persistenceFailed,
          message: 'Failed to persist freshly issued tokens',
        ),
      );
    }
    return OAuthCallbackSuccess(tokens);
  }

  /// Refresh the persisted access token using the persisted refresh token.
  /// Throws [OAuthFailure] on failure. Fresh tokens are persisted on success.
  Future<OAuthTokens> refresh() async {
    final OAuthTokens? stored;
    try {
      stored = await tokenStore.read();
    } catch (e) {
      log(
        'Failed to read persisted OAuth tokens during refresh '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
      throw const OAuthFailure(
        reason: OAuthFailureReason.persistenceFailed,
        message: 'Failed to read persisted tokens',
      );
    }
    final refreshToken = stored?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OAuthFailure(
        reason: OAuthFailureReason.tokenExchangeFailed,
        message: 'No refresh_token persisted',
      );
    }
    final fresh = await bffClient.exchangeRefreshToken(refreshToken);
    try {
      await tokenStore.save(fresh);
    } catch (e) {
      log(
        'Failed to persist tokens after successful refresh '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
      throw const OAuthFailure(
        reason: OAuthFailureReason.persistenceFailed,
        message: 'Failed to persist refreshed tokens',
      );
    }
    return fresh;
  }

  /// Subscribe to App Links and forward auth callbacks to [handleCallback].
  /// Idempotent. Pass an [appLinks] instance for testing; otherwise a real
  /// `AppLinks()` is used.
  ///
  /// Same-URI deduplication: some platform timings deliver the cold-start
  /// callback both via [AppLinks.getInitialLink] and via the warm
  /// `uriLinkStream` shortly after subscription. To avoid firing
  /// `onOutcome` twice (which would surface as a spurious stateMismatch
  /// after a successful exchange), the last-handled URI is tracked and
  /// duplicates are skipped.
  Future<void> attachAppLinks({
    required void Function(OAuthCallbackOutcome) onOutcome,
    AppLinks? appLinks,
  }) async {
    if (_linkSubscription != null) return;
    final links = appLinks ?? AppLinks();
    _linkSubscription = links.uriLinkStream.listen(
      (Uri uri) async {
        await _routeIfNew(uri, onOutcome);
      },
      onError: (Object e, StackTrace s) {
        log('App Links stream error: $e\n$s', name: 'OAuthBffAuthService');
      },
    );

    // Cold-start: the app may have been launched directly by the callback
    // intent. getInitialLink() returns it once (app_links v7 API).
    final initialUri = await links.getInitialLink();
    if (initialUri != null) {
      await _routeIfNew(initialUri, onOutcome);
    }
  }

  Future<void> _routeIfNew(
    Uri uri,
    void Function(OAuthCallbackOutcome) onOutcome,
  ) async {
    if (!_isAuthCallbackUri(uri)) return;
    final key = uri.toString();
    if (key == _lastHandledCallbackUri) return;
    _lastHandledCallbackUri = key;
    final outcome = await handleCallback(uri);
    if (_disposed) return;
    onOutcome(outcome);
  }

  /// Detach the App Links listener.
  Future<void> detachAppLinks() async {
    await _linkSubscription?.cancel();
    _linkSubscription = null;
  }

  /// Aggregate teardown: detach the App Links listener and close the
  /// underlying HTTP client. Call once at app shutdown to release the
  /// long-lived `http.Client` socket pool inside `OAuthBffClient`.
  ///
  /// Sets the `_disposed` flag first so any in-flight `handleCallback`
  /// whose async tail completes after this call will skip the
  /// `onOutcome` invocation — UI consumers that have torn down their
  /// state will not be reached by a stale outcome.
  Future<void> dispose() async {
    _disposed = true;
    await detachAppLinks();
    bffClient.close();
  }

  bool _isAuthCallbackUri(Uri uri) {
    final redirect = Uri.parse(config.redirectUri);
    return uri.scheme == redirect.scheme &&
        uri.host == redirect.host &&
        uri.path.startsWith(redirect.path);
  }

  /// Best-effort clear of the in-flight state. Wraps [OAuthStateStore.clear]
  /// in try/catch + log so a PlatformException from flutter_secure_storage
  /// (Keystore broken / decryption reset) never propagates as a raw async
  /// error through the App Links stream listener — that would be silently
  /// swallowed, leaving the UI without an outcome. The clear is for replay
  /// protection; on failure the next flow's state mismatch check still
  /// guards correctness.
  Future<void> _safeClearState() async {
    try {
      await stateStore.clear();
    } catch (e) {
      log(
        'Failed to clear persisted OAuth state '
        '(error type: ${e.runtimeType})',
        name: 'OAuthBffAuthService',
      );
    }
  }

  /// Compare two strings in length-constant time. Even though `state` is a
  /// public-ish anti-CSRF value (not a secret), constant-time comparison
  /// removes a side-channel category that static analyzers / reviewers
  /// often flag.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
