import 'dart:developer' as developer;

import '../../data/auth/user_session_store.dart';
import 'oauth_auth_controller.dart';

/// Logs the user out of every login the app keeps.
///
/// Clears, in order:
///
/// 1. the WebView login session (`user_session` cookie in [sessionStore]),
/// 2. the WebView's own cookies ([clearWebViewCookies]),
/// 3. the OAuth tokens, when OAuth is wired up ([oauth]; Issue #1053).
///
/// A failure to clear the OAuth tokens does not stop the logout: the
/// cookie session is already gone, and only the error type is logged.
Future<void> signOutEverywhere({
  required UserSessionStore sessionStore,
  required Future<void> Function() clearWebViewCookies,
  OAuthAuthController? oauth,
}) async {
  await sessionStore.clear();
  await clearWebViewCookies();
  if (oauth == null) {
    return;
  }
  try {
    await oauth.signOut();
  } on Object catch (error) {
    developer.log(
      'Failed to clear OAuth tokens on logout: ${error.runtimeType}',
      name: 'signOutEverywhere',
    );
  }
}
