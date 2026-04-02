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
