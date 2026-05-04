import 'package:flutter/foundation.dart';

import '../app_logging.dart';

/// Logger name used by every diagnostic emitted from the extension
/// subsystem.
///
/// In debug builds the name carries the subsystem suffix
/// (`comerune.extension`) so platform logs are easy to grep. In
/// release builds the subsystem is intentionally hidden behind a
/// generic `comerune` name so logcat / Console output does not
/// advertise the presence of optional integrations to anyone watching
/// device logs.
const String extensionLogName = kDebugMode ? 'comerune.extension' : 'comerune';

/// Emit a defensive diagnostic from the extension subsystem.
///
/// In debug builds the [error] and [stackTrace] are printed via
/// `appErrorLog` (which uses `debugPrint`). In release builds both
/// are dropped so that:
/// - integration-specific exception class names do not leak into
///   platform logs;
/// - `developer.log` records only the generic [message] together with
///   `extensionLogName`.
///
/// Callers should use this for **defensive** logging only. Detailed
/// errors that the host genuinely needs to surface to the user
/// (e.g. host bugs in fallback code) must NOT be funnelled through
/// here — they should be allowed to throw.
void logExtensionDiagnostic({
  required String message,
  Object? error,
  StackTrace? stackTrace,
}) {
  appErrorLog(
    name: extensionLogName,
    message: message,
    error: kDebugMode ? error : null,
    stackTrace: kDebugMode ? stackTrace : null,
  );
}
