import 'package:flutter/widgets.dart';

import 'oauth_auth_controller.dart';

/// Inherited widget that exposes the app-lifetime [OAuthAuthController] to
/// any descendant in the tree. Wrap [MaterialApp] (or its parent) with this
/// at app startup so screens like the login screen can reach the
/// controller via `OAuthAuthScope.maybeOf(context)` without each parent
/// widget having to thread it through as a constructor argument.
///
/// Use [maybeOf] (returns `null` when the scope is absent) rather than
/// [of] in screens that should still build on a fork that does not wire
/// this up. This matches the project's "optional integration" pattern:
/// missing the scope must not break the build, only hide the OAuth login
/// entry point.
class OAuthAuthScope extends InheritedWidget {
  const OAuthAuthScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final OAuthAuthController controller;

  /// Look up the controller in the nearest enclosing scope. Returns
  /// `null` when no scope is present so callers can render a fallback
  /// (e.g. simply not show the OAuth login entry point).
  static OAuthAuthController? maybeOf(BuildContext context) {
    final OAuthAuthScope? scope = context
        .dependOnInheritedWidgetOfExactType<OAuthAuthScope>();
    return scope?.controller;
  }

  @override
  bool updateShouldNotify(covariant OAuthAuthScope oldWidget) {
    return controller != oldWidget.controller;
  }
}
