import 'package:flutter/foundation.dart';

/// Bundles the three user-name resolution callbacks that are passed through
/// the widget tree.
class UserNameResolution {
  const UserNameResolution({
    required this.resolve,
    required this.requestResolve,
    required this.listenable,
  });

  /// Returns the cached resolved name for [userId], or null.
  final String? Function(String userId) resolve;

  /// Requests asynchronous resolution of [userId].
  final void Function(String userId) requestResolve;

  /// Notifies listeners when resolved names change.
  final Listenable listenable;
}
