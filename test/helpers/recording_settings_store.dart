import 'package:flutter/foundation.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

/// Minimal [SettingsStore] fake that records [save] invocations and can
/// be configured to throw on [save].
///
/// Members not exercised by the settings save helpers (or by direct
/// `saveSettingsToStore` callers) intentionally throw [UnimplementedError]
/// so accidental coupling surfaces in tests.
///
/// Shared across `settings_save_helper_test.dart` and
/// `settings_widgets_test.dart` so the same fake does not get duplicated
/// inline in multiple test files.
class RecordingSettingsStore implements SettingsStore {
  RecordingSettingsStore({this.saveError});

  final Object? saveError;
  int saveCallCount = 0;
  AppSettings? lastSavedSettings;

  @override
  Future<void> save(AppSettings settings) async {
    saveCallCount += 1;
    lastSavedSettings = settings;
    final Object? error = saveError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<AppSettings> load() async => throw UnimplementedError();

  @override
  double? loadPreMuteVolume() => throw UnimplementedError();

  @override
  Future<void> savePreMuteVolume(double? volume) async =>
      throw UnimplementedError();

  @override
  double? loadPreMuteAndroidTtsVolume() => throw UnimplementedError();

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) async =>
      throw UnimplementedError();

  @override
  Future<String> exportAsJson() async => throw UnimplementedError();

  @override
  Future<String> writeExportToTempFile() async => throw UnimplementedError();

  @override
  Future<AppSettings> importFromJson(String jsonString) async =>
      throw UnimplementedError();
}

/// Runs [body] with [debugPrint] redirected into [sink] and restored
/// afterwards.
///
/// Used to capture the debug-build error log written by [appErrorLog]
/// without coupling to its private formatting.
Future<void> withCapturedDebugPrint(
  List<String> sink,
  Future<void> Function() body,
) async {
  final DebugPrintCallback original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      sink.add(message);
    }
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
}
