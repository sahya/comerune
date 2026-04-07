import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/auth/user_session_store.dart';

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

  /// Hosts allowed during the login flow.
  static const Set<String> _allowedHosts = <String>{
    'account.nicovideo.jp',
    'nicovideo.jp',
    'www.nicovideo.jp',
    'live.nicovideo.jp',
    'oauth.nicovideo.jp',
    'secure.nicovideo.jp',
  };

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
    final Uri? uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.prevent;
    }
    final String host = uri.host;
    if (_allowedHosts.contains(host) || host.endsWith('.nicovideo.jp')) {
      return NavigationDecision.navigate;
    }
    return NavigationDecision.prevent;
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ニコニコログイン')),
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
