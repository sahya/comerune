import 'package:comerune/application/auth/sign_out.dart';
import 'package:comerune/data/auth/oauth_bff/oauth_bff_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_user_session_store.dart';
import '../../helpers/test_oauth_auth_controller.dart';

const OAuthTokens _tokens = OAuthTokens(
  accessToken: 'access',
  tokenType: 'Bearer',
  expiresInSeconds: 3600,
  refreshToken: 'refresh',
);

void main() {
  group('signOutEverywhere', () {
    test('clears the cookie session, the WebView cookies and the OAuth '
        'tokens (#1053)', () async {
      final InMemoryUserSessionStore sessionStore = InMemoryUserSessionStore();
      await sessionStore.save('user_session_abc');
      final InMemoryOAuthTokenStore tokenStore = InMemoryOAuthTokenStore();
      await tokenStore.save(_tokens);
      int webViewCookieClears = 0;

      await signOutEverywhere(
        sessionStore: sessionStore,
        clearWebViewCookies: () async => webViewCookieClears += 1,
        oauth: buildTestOAuthAuthController(tokenStore: tokenStore),
      );

      expect(await sessionStore.load(), isEmpty);
      expect(webViewCookieClears, 1);
      expect(await tokenStore.read(), isNull);
    });

    test('still logs out of the cookie session when OAuth is not wired '
        'up', () async {
      final InMemoryUserSessionStore sessionStore = InMemoryUserSessionStore();
      await sessionStore.save('user_session_abc');
      int webViewCookieClears = 0;

      await signOutEverywhere(
        sessionStore: sessionStore,
        clearWebViewCookies: () async => webViewCookieClears += 1,
      );

      expect(await sessionStore.load(), isEmpty);
      expect(webViewCookieClears, 1);
    });

    test('still clears the OAuth tokens when clearing the WebView cookies '
        'throws, and rethrows that error', () async {
      final InMemoryUserSessionStore sessionStore = InMemoryUserSessionStore();
      await sessionStore.save('user_session_abc');
      final InMemoryOAuthTokenStore tokenStore = InMemoryOAuthTokenStore();
      await tokenStore.save(_tokens);

      await expectLater(
        signOutEverywhere(
          sessionStore: sessionStore,
          clearWebViewCookies: () async => throw StateError('webview'),
          oauth: buildTestOAuthAuthController(tokenStore: tokenStore),
        ),
        throwsA(isA<StateError>()),
      );

      expect(await sessionStore.load(), isEmpty);
      expect(await tokenStore.read(), isNull);
    });

    test(
      'completes the logout when the OAuth tokens cannot be deleted',
      () async {
        final InMemoryUserSessionStore sessionStore =
            InMemoryUserSessionStore();
        await sessionStore.save('user_session_abc');

        await signOutEverywhere(
          sessionStore: sessionStore,
          clearWebViewCookies: () async {},
          oauth: buildTestOAuthAuthController(
            tokenStore: ClearThrowingOAuthTokenStore(),
          ),
        );

        expect(await sessionStore.load(), isEmpty);
      },
    );
  });
}
