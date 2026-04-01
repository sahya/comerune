import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

const int kAppErrorLogLevel = 900;

void appDebugLog(String message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint(message);
}

void appDebugLogLazy(String Function() messageBuilder) {
  if (!kDebugMode) {
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

  final Object? safeError = error == null ? null : error.runtimeType;
  developer.log(
    message,
    name: name,
    error: safeError,
    level: kAppErrorLogLevel,
  );
}
