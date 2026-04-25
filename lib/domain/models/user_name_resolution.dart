import 'package:flutter/foundation.dart';

/// Bundles the user-name resolution callbacks that are passed through
/// the widget tree.
class UserNameResolution {
  const UserNameResolution({
    required this.resolve,
    required this.requestResolve,
    required this.listenable,
    this.seedCache,
  });

  /// Returns the cached resolved name for [userId], or null.
  final String? Function(String userId) resolve;

  /// Requests asynchronous resolution of [userId].
  final void Function(String userId) requestResolve;

  /// Notifies listeners when resolved names change.
  final Listenable listenable;

  /// Pre-populates the cache with a known name (e.g. extracted from the
  /// niconico watch-page embedded data). Optional so callers that only
  /// need read access can omit it.
  final void Function(String userId, String name)? seedCache;
}
