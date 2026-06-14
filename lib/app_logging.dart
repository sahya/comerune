import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const int kAppErrorLogLevel = 900;
const bool kAppDebugLogEnabled = kDebugMode;

void appDebugLog(String message) {
  if (!kAppDebugLogEnabled) {
    return;
  }
  debugPrint(message);
}

void appDebugLogLazy(String Function() messageBuilder) {
  if (!kAppDebugLogEnabled) {
    return;
  }
  debugPrint(messageBuilder());
}

/// Masks a session string for safe debug logging.
///
/// Returns:
/// - `'(empty)'` for an empty string
/// - `'***'` for strings of 8 characters or fewer
/// - `'abcd...wxyz'` (first 4 + last 4 characters) for longer strings
String debugMaskSession(String session) {
  if (session.isEmpty) return '(empty)';
  if (session.length <= 8) return '***';
  return '${session.substring(0, 4)}...${session.substring(session.length - 4)}';
}

void appErrorLog({
  required String name,
  required String message,
  Object? error,
  StackTrace? stackTrace,
}) {
  if (kDebugMode) {
    final String suffix = error != null ? ': $error' : '';
    debugPrint('$message$suffix');
    if (stackTrace != null) {
      debugPrint('$stackTrace');
    }
    return;
  }

  final Object? safeError = error?.runtimeType;
  developer.log(
    message,
    name: name,
    error: safeError,
    level: kAppErrorLogLevel,
  );
}
