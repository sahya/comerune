import 'dart:async';

import '../../app_logging.dart';
import '../../domain/models/app_settings.dart';
import 'settings_store.dart';

/// Logger name used by [saveSettings] / [saveSettingsUnawaited] when a
/// [SettingsStore.save] call fails. Exposed as a top-level constant so
/// tests and grep-based audits can find every settings-persistence error
/// log line without depending on a private string.
const String settingsSaveHelperLoggerName = 'SettingsSaveHelper';

/// Persists [settings] through [store] and rethrows on failure after
/// logging the error via [appErrorLog].
///
/// Use this variant when the caller is already in an `async` flow and
/// wants to react to (or surface) a persistence failure — for example
/// an "OK" button handler that should not pretend the save succeeded.
///
/// The helper deliberately does NOT include the [AppSettings] payload in
/// the log message: settings can carry user-authored content (NG word
/// list, favorite user IDs, dictionary rules, etc.) which must not be
/// written to logs. Only the failing operation name and the error type
/// (via [appErrorLog]) are recorded.
Future<void> saveSettings(SettingsStore store, AppSettings settings) async {
  try {
    await store.save(settings);
  } on Object catch (error, stackTrace) {
    appErrorLog(
      name: settingsSaveHelperLoggerName,
      message: 'saveSettings: SettingsStore.save FAILED',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

/// Fire-and-forget variant of [saveSettings] for callers that cannot
/// `await` (synchronous UI handlers, optimistic in-memory updates).
///
/// Failures are routed through [appErrorLog] instead of escaping as an
/// unhandled future error or being silently dropped by `unawaited(...)`.
/// The future is intentionally swallowed after logging because the call
/// site has no place to surface the failure; the next user action that
/// triggers another save will retry persistence with the freshest value.
///
/// As with [saveSettings], the [AppSettings] value itself is never
/// included in the log message.
void saveSettingsUnawaited(SettingsStore store, AppSettings settings) {
  unawaited(
    store.save(settings).catchError((Object error, StackTrace stackTrace) {
      appErrorLog(
        name: settingsSaveHelperLoggerName,
        message: 'saveSettingsUnawaited: SettingsStore.save FAILED',
        error: error,
        stackTrace: stackTrace,
      );
    }),
  );
}
