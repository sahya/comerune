import 'package:flutter/foundation.dart';

/// Groups the three callbacks required for asynchronous user-name resolution.
///
/// Many widgets accept these three parameters together:
///   - [resolve]: returns the cached name for a user ID, or null.
///   - [requestResolve]: triggers async resolution for a user ID.
///   - [listenable]: fires when the name cache changes so the UI can rebuild.
class UserNameResolution {
  const UserNameResolution({
    required this.resolve,
    required this.requestResolve,
    required this.listenable,
  });

  final String? Function(String userId) resolve;
  final void Function(String userId) requestResolve;
  final Listenable listenable;
}
