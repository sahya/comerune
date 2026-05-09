import 'package:flutter/foundation.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

/// Minimal [SettingsStore] fake that records [save] / [load] invocations
/// and can be configured to throw on either operation.
///
/// Members not explicitly modelled (pre-mute volumes, export/import)
/// intentionally throw [UnimplementedError] so accidental coupling
/// surfaces in tests. Use [DelegatingSettingsStore] instead when a test
/// needs a realistic round-trip through a real [SettingsStore].
///
/// Shared across multiple test files so the same fake does not get
/// duplicated inline. New test files that need a similar fake should
/// import this helper rather than re-defining it locally.
class RecordingSettingsStore implements SettingsStore {
  RecordingSettingsStore({this.saveError, this.loadError});

  /// Error to throw from [save]. When `null`, [save] succeeds and records
  /// the invocation in [saveCallCount] / [lastSavedSettings].
  final Object? saveError;

  /// Error to throw from [load]. When `null`, [load] throws
  /// [UnimplementedError] (the historical default) — set this to drive
  /// load-failure regression tests without introducing a separate fake.
  final Object? loadError;

  int saveCallCount = 0;
  int loadCallCount = 0;
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
  Future<AppSettings> load() async {
    loadCallCount += 1;
    final Object? error = loadError;
    if (error != null) {
      throw error;
    }
    throw UnimplementedError(
      'RecordingSettingsStore.load() requires loadError to be set; '
      'use DelegatingSettingsStore for tests that need a realistic load.',
    );
  }

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

/// [SettingsStore] wrapper that delegates every method to [inner] by
/// default, but can be configured to throw on [load] and/or [save] to
/// simulate persistence failures while preserving a realistic round-trip
/// for the unfailed operation.
///
/// Typical use: pair with a `SharedPreferencesSettingsStore` backed by
/// [InMemorySharedPreferences] so [load] returns a realistic
/// [AppSettings], then drive a [save] failure scenario with `saveError`.
class DelegatingSettingsStore implements SettingsStore {
  DelegatingSettingsStore({
    required this.inner,
    this.saveError,
    this.loadError,
  });

  /// The underlying store that handles real load/save when the matching
  /// `*Error` field is `null`.
  final SettingsStore inner;

  /// Error to throw from [save] instead of delegating to [inner]. When
  /// `null`, [save] is fully delegated.
  final Object? saveError;

  /// Error to throw from [load] instead of delegating to [inner]. When
  /// `null`, [load] is fully delegated.
  final Object? loadError;

  int saveAttempts = 0;
  int loadAttempts = 0;

  @override
  Future<AppSettings> load() async {
    loadAttempts += 1;
    final Object? error = loadError;
    if (error != null) {
      throw error;
    }
    return inner.load();
  }

  @override
  Future<void> save(AppSettings settings) async {
    saveAttempts += 1;
    final Object? error = saveError;
    if (error != null) {
      throw error;
    }
    return inner.save(settings);
  }

  @override
  double? loadPreMuteVolume() => inner.loadPreMuteVolume();

  @override
  Future<void> savePreMuteVolume(double? volume) =>
      inner.savePreMuteVolume(volume);

  @override
  double? loadPreMuteAndroidTtsVolume() => inner.loadPreMuteAndroidTtsVolume();

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) =>
      inner.savePreMuteAndroidTtsVolume(volume);

  @override
  Future<String> exportAsJson() => inner.exportAsJson();

  @override
  Future<String> writeExportToTempFile() => inner.writeExportToTempFile();

  @override
  Future<AppSettings> importFromJson(String jsonString) =>
      inner.importFromJson(jsonString);
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
