import 'dart:async';

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
  static const String _userSessionCookieName = 'user_session';

  late final WebViewController _controller;
  bool _isLoading = true;
  bool _loginDetected = false;

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

  Future<void> _checkForUserSession(String url) async {
    if (_loginDetected) {
      return;
    }

    // After login, user is typically redirected away from the login page.
    // Check cookies on every page load to detect when user_session appears.
    final String? userSession = await _extractUserSessionCookie();
    if (userSession == null || userSession.isEmpty) {
      return;
    }

    // user_session_XXXXX is the real session cookie (not user_session_secure)
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
  }

  Future<String?> _extractUserSessionCookie() async {
    // Use JavaScript to read cookies since WebViewCookieManager
    // doesn't have a getCookies method in webview_flutter 4.x.
    // The user_session cookie may not be httpOnly on the login page.
    try {
      final Object result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      final String cookieString =
          result is String ? _unquote(result) : result.toString();
      return _parseCookieValue(cookieString, _userSessionCookieName);
    } catch (_) {
      return null;
    }
  }

  /// Remove surrounding quotes from JavaScript string result.
  String _unquote(String s) {
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  String? _parseCookieValue(String cookieString, String name) {
    // Cookie string format: "name1=value1; name2=value2; ..."
    final List<String> parts = cookieString.split(';');
    for (final String part in parts) {
      final String trimmed = part.trim();
      // Match user_session but not user_session_secure
      if (trimmed.startsWith('$name=') &&
          !trimmed.startsWith('${name}_secure=')) {
        final int eqIndex = trimmed.indexOf('=');
        if (eqIndex >= 0) {
          return trimmed.substring(eqIndex + 1);
        }
      }
    }
    return null;
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
