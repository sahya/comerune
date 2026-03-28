import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/auth/user_session_store.dart';

/// Login screen that opens niconico login page in a WebView.
///
/// After the user logs in, the user_session cookie is extracted
/// and saved to the [UserSessionStore].
/// This follows the same approach as N Air (official niconico streaming tool).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.userSessionStore,
  });

  final UserSessionStore userSessionStore;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const String _loginUrl = 'https://account.nicovideo.jp/login';

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
  int _postLoginPageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
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
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl));
  }

  bool _isPostLoginUrl(String url) {
    return _postLoginUrlPrefixes.any(
      (String prefix) => url.startsWith(prefix),
    );
  }

  Future<void> _checkForUserSession(String url) async {
    if (_loginDetected) {
      return;
    }

    final String? userSession = await _extractUserSessionCookie();
    if (userSession != null && userSession.isNotEmpty) {
      _loginDetected = true;
      await widget.userSessionStore.save(userSession);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('ログインしました')),
        );
      Navigator.of(context).pop(true);
      return;
    }

    // If the user navigated to a post-login page but cookie was not
    // detected (e.g., httpOnly cookie), show a warning.
    if (_isPostLoginUrl(url)) {
      _postLoginPageCount += 1;
      // Show warning after visiting a post-login page without cookie
      if (_postLoginPageCount >= 1 && mounted) {
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
  }

  Future<String?> _extractUserSessionCookie() async {
    // Use JavaScript to read cookies since WebViewCookieManager
    // doesn't have a getCookies method in webview_flutter 4.x.
    // Note: This cannot read httpOnly cookies. Niconico's user_session
    // cookie is not httpOnly on the login page based on observed behavior.
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final String cookieString =
          result is String ? _unquote(result) : result.toString();
      return parseNicoUserSessionCookie(cookieString);
    } catch (error) {
      log(
        'Failed to extract cookie: $error',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ニコニコログイン'),
      ),
      body: Stack(
        children: <Widget>[
          WebViewWidget(controller: _controller),
          if (_isLoading) const LinearProgressIndicator(),
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
