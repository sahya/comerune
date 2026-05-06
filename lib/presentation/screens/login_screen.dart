import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../application/auth/oauth_auth_controller.dart';
import '../../application/auth/oauth_auth_scope.dart';
import '../../data/auth/oauth_bff/oauth_bff_auth_service.dart';
import '../../data/auth/oauth_bff/oauth_bff_models.dart';
import '../../data/auth/user_session_store.dart';

/// Hosts allowed during the niconico login flow.
///
/// Includes niconico's own domains and the external OAuth provider domains
/// required for social login buttons on the niconico login page.
const Set<String> _allowedLoginHosts = <String>{
  // niconico domains
  'account.nicovideo.jp',
  'nicovideo.jp',
  'www.nicovideo.jp',
  'live.nicovideo.jp',
  'oauth.nicovideo.jp',
  'secure.nicovideo.jp',

  // Google OAuth
  'accounts.google.com',

  // X/Twitter OAuth
  'api.x.com',
  'x.com',
  'twitter.com',

  // Apple Sign-In
  'appleid.apple.com',

  // Nintendo Account
  'accounts.nintendo.com',

  // LINE Login
  'access.line.me',
  'liff.line.me',

  // Yahoo! JAPAN Login
  'login.yahoo.co.jp',
  'auth.login.yahoo.co.jp',
};

/// Login screen that opens niconico login page in a WebView.
///
/// After the user logs in, the user_session cookie is extracted
/// and saved to the [UserSessionStore].
/// This follows the same approach as N Air (official niconico streaming tool).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.userSessionStore});

  final UserSessionStore userSessionStore;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _loginUrl = 'https://account.nicovideo.jp/login';
  static const MethodChannel _cookieChannel = MethodChannel(
    'com.example.comerune/cookies',
  );

  // Domain allowlist is defined in the top-level [_allowedLoginHosts]
  // constant and exposed via [isAllowedLoginDomain] for testability.

  /// URLs that indicate the user has likely completed login.
  static const List<String> _postLoginUrlPrefixes = <String>[
    'https://www.nicovideo.jp',
    'https://nicovideo.jp',
    'https://live.nicovideo.jp',
    'https://account.nicovideo.jp/my',
  ];

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loginDetected = false;
  bool _hasError = false;
  int _postLoginPageCount = 0;

  /// Optional OAuth + App Links + BFF login orchestrator. Read from the
  /// inherited [OAuthAuthScope]. May be `null` when the scope is not wired
  /// up (e.g. in widget tests that pump a bare LoginScreen) — in that
  /// case the OAuth login entry point is simply not exposed.
  OAuthAuthController? _oauthController;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _checkForUserSession(url);
          },
          onWebResourceError: (WebResourceError error) {
            log(
              'WebView error: ${error.description} (${error.errorCode})',
              name: 'LoginScreen',
            );
            if (mounted && error.isForMainFrame == true) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      );
    _clearCacheAndLoad();
  }

  /// Clear WebView cookies and cache before loading the login page
  /// so that previous form data (email / password) does not persist.
  Future<void> _clearCacheAndLoad() async {
    try {
      await Future.wait(<Future<void>>[
        WebViewCookieManager().clearCookies(),
        _controller.clearCache(),
        _controller.clearLocalStorage(),
      ]);
    } catch (error) {
      log('Failed to clear WebView data: $error', name: 'LoginScreen');
    }
    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    return isAllowedLoginNavigation(Uri.tryParse(request.url))
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  bool _isPostLoginUrl(String url) {
    return _postLoginUrlPrefixes.any((String prefix) => url.startsWith(prefix));
  }

  bool _isCheckingSession = false;

  Future<void> _checkForUserSession(String url) async {
    if (_loginDetected || _isCheckingSession) {
      return;
    }
    _isCheckingSession = true;

    try {
      final String? userSession = await _extractUserSessionCookie();
      if (userSession == null || userSession.isEmpty) {
        // Not logged in yet — check if we're on a post-login page
        if (_isPostLoginUrl(url)) {
          _postLoginPageCount += 1;
          if (_postLoginPageCount == 1 && mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text(
                    'ログインが検出できませんでした。'
                    'Cookieの取得に失敗した可能性があります。',
                  ),
                  duration: Duration(seconds: 5),
                ),
              );
          }
        }
        return;
      }

      _loginDetected = true;
      await widget.userSessionStore.save(userSession);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('ログインしました')));
      Navigator.of(context).pop(true);
    } finally {
      _isCheckingSession = false;
    }
  }

  Future<String?> _extractUserSessionCookie() async {
    // Try platform channel first (can read httpOnly cookies via
    // Android's CookieManager), fall back to document.cookie.
    try {
      final String cookies =
          await _cookieChannel.invokeMethod<String>(
            'getCookies',
            <String, String>{'url': 'https://nicovideo.jp'},
          ) ??
          '';
      if (cookies.isNotEmpty) {
        final String? session = parseNicoUserSessionCookie(cookies);
        if (session != null) {
          return session;
        }
      }
    } catch (error) {
      log(
        'Platform cookie channel failed, trying document.cookie: $error',
        name: 'LoginScreen',
      );
    }

    // Fallback: try document.cookie (cannot read httpOnly cookies)
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final String cookieString = result is String
          ? _unquote(result)
          : result.toString();
      return parseNicoUserSessionCookie(cookieString);
    } catch (error) {
      log(
        'Failed to extract cookie via document.cookie: $error',
        name: 'LoginScreen',
      );
      return null;
    }
  }

  /// Remove surrounding quotes from JavaScript string result.
  static String _unquote(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  Future<void> _retry() async {
    setState(() {
      _hasError = false;
      _isLoading = true;
    });
    await _controller.loadRequest(Uri.parse(_loginUrl));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final OAuthAuthController? next = OAuthAuthScope.maybeOf(context);
    if (next != _oauthController) {
      _oauthController?.outcome.removeListener(_onOAuthOutcomeChanged);
      _oauthController = next;
      _oauthController?.outcome.addListener(_onOAuthOutcomeChanged);
    }
  }

  @override
  void dispose() {
    _oauthController?.outcome.removeListener(_onOAuthOutcomeChanged);
    super.dispose();
  }

  /// Listener attached to [OAuthAuthController.outcome]. When a non-null
  /// outcome arrives (after the user returns from the browser via App
  /// Links), surface a snackbar then mark the outcome consumed so the
  /// same value does not re-fire when the user navigates back to this
  /// screen.
  void _onOAuthOutcomeChanged() {
    final OAuthAuthController? controller = _oauthController;
    if (controller == null || !mounted) return;
    final OAuthCallbackOutcome? outcome = controller.outcome.value;
    if (outcome == null) return;
    final String message = switch (outcome) {
      OAuthCallbackSuccess() => 'OAuth ログインに成功しました',
      OAuthCallbackFailure(:final failure) => _humanReadableFailure(failure),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    controller.clearOutcome();
  }

  /// Map an [OAuthFailureReason] to a Japanese, user-facing message.
  ///
  /// The wording deliberately avoids OAuth-protocol jargon (`state`,
  /// `callback`, `token exchange`) because end users do not know what
  /// those terms mean. Internal details are still available via
  /// developer logs (controller / service log entries) for debugging.
  String _humanReadableFailure(OAuthFailure failure) {
    switch (failure.reason) {
      case OAuthFailureReason.upstreamAuthorizationError:
        return 'ログインがキャンセル / 拒否されました';
      case OAuthFailureReason.malformedCallback:
        return 'ログインの応答が不正でした';
      case OAuthFailureReason.stateMismatch:
        return 'ログインの整合性チェックに失敗しました。もう一度お試しください。';
      case OAuthFailureReason.tokenExchangeFailed:
        return 'ログイン処理中にエラーが発生しました';
      case OAuthFailureReason.networkFailure:
        return 'ネットワークエラーが発生しました。接続を確認してもう一度お試しください。';
      case OAuthFailureReason.persistenceFailed:
        return 'ログイン情報の保存に失敗しました';
    }
  }

  /// Trigger the OAuth + BFF login flow: ask the controller for the
  /// authorize URI then hand it off to the OS browser. The result
  /// (success / failure) is delivered asynchronously via
  /// [_onOAuthOutcomeChanged] when Android delivers the App Links
  /// callback.
  Future<void> _startOAuthLogin() async {
    final OAuthAuthController? controller = _oauthController;
    if (controller == null) return;
    final Uri? uri = await controller.startLogin();
    if (uri == null) {
      // startLogin() either no-ops (not configured) or pushes the
      // failure outcome itself; nothing more to do here.
      return;
    }
    bool launched;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // url_launcher can throw PlatformException on devices without a
      // suitable browser, on missing-activity errors, etc. Treat it as
      // a launch failure and surface the same snackbar so the user is
      // not left wondering why nothing happened.
      log('launchUrl threw: $e', name: 'LoginScreen');
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('ブラウザを起動できませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // OAuth ログイン入口は debug ビルドの開発者向け検証用としてのみ
    // 表示する。release ではボタン自体を出さないことで、フローを通しても
    // 機能差が生まれないボタンをユーザーに見せない (取得した access_token を
    // アプリ内 API 呼び出しに反映する配線は #795 で対応予定。完了時に
    // 本 `kDebugMode &&` ガードと tooltip の "(debug 限定)" を併せて外す)。
    final bool oauthAvailable =
        kDebugMode && (_oauthController?.isFullyConfigured ?? false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ニコニコログイン'),
        actions: <Widget>[
          if (oauthAvailable)
            IconButton(
              tooltip: 'OAuth でログイン (debug 限定)',
              icon: const Icon(Icons.vpn_key),
              onPressed: _startOAuthLogin,
            ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_isLoading) const LinearProgressIndicator(),
          if (_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('ページの読み込みに失敗しました'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('再試行'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Returns whether [host] is allowed during the niconico login flow.
///
/// Allows niconico domains (including any subdomain of `nicovideo.jp`)
/// and the external OAuth provider domains needed for Google, X/Twitter,
/// and Apple sign-in.
bool isAllowedLoginDomain(String host) {
  return _allowedLoginHosts.contains(host) || host.endsWith('.nicovideo.jp');
}

/// Returns whether [scheme] is allowed during the niconico login flow.
///
/// Only `https` is permitted for real navigation so that credentials
/// (OAuth provider login forms, niconico login form) are never sent over
/// plaintext HTTP. `about` is also permitted because the WebView issues
/// `about:blank` internally during initialization / blank pages.
///
/// All other schemes (`http`, `javascript`, `data`, `file`, custom app
/// schemes, etc.) are rejected.
bool isAllowedLoginScheme(String scheme) {
  return scheme == 'https' || scheme == 'about';
}

/// Returns whether the WebView should navigate to [uri] during the niconico
/// login flow. This is the single source of truth for the navigation gate
/// applied by the login WebView.
///
/// Returns `false` for `null` (unparseable URLs), disallowed schemes
/// (anything other than `https` / `about`), and disallowed hosts.
/// `about:` URIs bypass the host allowlist because they are issued by the
/// WebView itself during initialization and have no meaningful host.
bool isAllowedLoginNavigation(Uri? uri) {
  if (uri == null) {
    return false;
  }
  if (!isAllowedLoginScheme(uri.scheme)) {
    return false;
  }
  if (uri.scheme == 'about') {
    return true;
  }
  return isAllowedLoginDomain(uri.host);
}

/// Parses the user_session cookie value from a cookie string.
///
/// Niconico uses cookie names like `user_session` or `user_session_XXXXX`.
/// This matches any cookie starting with `user_session` but excludes
/// `user_session_secure` variants.
String? parseNicoUserSessionCookie(String cookieString) {
  const String prefix = 'user_session';
  // Cookie string format: "name1=value1; name2=value2; ..."
  final List<String> parts = cookieString.split(';');
  for (final String part in parts) {
    final String trimmed = part.trim();
    final int eqIndex = trimmed.indexOf('=');
    if (eqIndex < 0) {
      continue;
    }
    final String name = trimmed.substring(0, eqIndex);
    // Match user_session or user_session_XXXXX, but not user_session_secure*
    if (name == prefix ||
        (name.startsWith('${prefix}_') &&
            !name.startsWith('${prefix}_secure'))) {
      final String value = trimmed.substring(eqIndex + 1);
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}
