import 'dart:developer';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../data/auth/oauth_bff/oauth_bff_auth_service.dart';
import '../../data/auth/oauth_bff/oauth_bff_models.dart';

/// Application-layer wrapper around [OAuthBffAuthService] that owns the
/// app-lifetime listener for App Links callbacks and exposes the latest
/// outcome to the UI as a [ValueListenable].
///
/// The service itself is reusable as a pure function-oriented data-layer
/// component; this controller adds the long-lived state (current outcome)
/// and the bootstrap / teardown calls that need to run once per app
/// process. UI screens listen to [outcome] for success / failure
/// notifications regardless of which screen is foregrounded when the
/// callback URL arrives.
class OAuthAuthController {
  OAuthAuthController({required OAuthBffAuthService service})
    : _service = service;

  final OAuthBffAuthService _service;
  final ValueNotifier<OAuthCallbackOutcome?> _outcome =
      ValueNotifier<OAuthCallbackOutcome?>(null);

  bool _attached = false;

  /// Whether the underlying BFF / authorize / client_id triple is configured
  /// at build time. UI uses this to decide whether to expose a login entry
  /// point at all (a release build without the dart-defines should not show
  /// a button that can only fail).
  bool get isFullyConfigured => _service.config.isFullyConfigured;

  /// Latest validated callback outcome, or `null` until the first one
  /// arrives. UI listens via [ValueListenableBuilder] for snackbar-style
  /// notifications.
  ValueListenable<OAuthCallbackOutcome?> get outcome => _outcome;

  /// Subscribe to App Links so callbacks delivered after returning from the
  /// browser are routed to [_outcome]. Idempotent; safe to call multiple
  /// times. Pass [appLinks] for tests; production should let the controller
  /// create the default `AppLinks()` instance.
  ///
  /// Failures (e.g. platform channel missing in unit tests) are caught and
  /// logged rather than rethrown — a missing App Links binding must not
  /// crash app startup. The OAuth login entry point will still gate on
  /// [isFullyConfigured] for visibility.
  Future<void> attach({AppLinks? appLinks}) async {
    if (_attached) return;
    _attached = true;
    try {
      await _service.attachAppLinks(
        appLinks: appLinks,
        onOutcome: (OAuthCallbackOutcome o) => _outcome.value = o,
      );
    } catch (e) {
      log(
        'Failed to attach App Links listener '
        '(error type: ${e.runtimeType})',
        name: 'OAuthAuthController',
      );
    }
  }

  /// Begin the authorization flow. Generates a fresh state, persists it,
  /// and returns the upstream authorize URL for the caller to open
  /// externally (typically with `url_launcher` in
  /// [LaunchMode.externalApplication] so the OS browser owns the flow,
  /// not an in-app WebView).
  ///
  /// Returns `null` if the build is not fully configured, so callers can
  /// no-op without throwing. On other failures (state persist error, etc.)
  /// the failure is surfaced through [outcome] so the same UI listener
  /// handles every error path.
  Future<Uri?> startLogin() async {
    if (!isFullyConfigured) {
      log(
        'Refusing to start OAuth login: build is not fully configured',
        name: 'OAuthAuthController',
      );
      return null;
    }
    try {
      return await _service.startAuthorization();
    } on OAuthFailure catch (failure) {
      _outcome.value = OAuthCallbackFailure(failure);
      return null;
    }
  }

  /// Detach the App Links listener and release the underlying HTTP client.
  /// Call once at app shutdown.
  Future<void> dispose() async {
    await _service.dispose();
    _outcome.dispose();
  }

  /// Mark the latest outcome as consumed (sets it back to `null`). UI
  /// screens that show the outcome via snackbar / dialog should call this
  /// after rendering so the same outcome does not re-fire when the user
  /// re-visits the screen and re-subscribes to [outcome].
  void clearOutcome() {
    _outcome.value = null;
  }
}
