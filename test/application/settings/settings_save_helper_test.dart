import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_save_helper.dart';
import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

void main() {
  group('saveSettings', () {
    test('awaits store.save and returns when persistence succeeds', () async {
      final _RecordingSettingsStore store = _RecordingSettingsStore();
      const AppSettings settings = AppSettings.defaults;

      await saveSettings(store, settings);

      expect(store.saveCallCount, 1);
      expect(identical(store.lastSavedSettings, settings), isTrue);
    });

    test('rethrows after logging when store.save throws', () async {
      final _RecordingSettingsStore store = _RecordingSettingsStore(
        saveError: StateError('boom'),
      );
      const AppSettings settings = AppSettings.defaults;

      final List<String> printed = <String>[];
      await _withCapturedDebugPrint(printed, () async {
        await expectLater(
          saveSettings(store, settings),
          throwsA(isA<StateError>()),
        );
      });

      expect(store.saveCallCount, 1);
      // The failure surface must mention the helper, but never the
      // AppSettings payload itself (PII / user-authored content).
      final String joined = printed.join('\n');
      expect(joined, contains('saveSettings'));
      expect(joined, contains('FAILED'));
      expect(joined, isNot(contains('AppSettings(')));
    });
  });

  group('saveSettingsUnawaited', () {
    test('forwards the latest settings value to store.save', () async {
      final _RecordingSettingsStore store = _RecordingSettingsStore();
      const AppSettings settings = AppSettings.defaults;

      saveSettingsUnawaited(store, settings);
      // Allow the unawaited future to run.
      await Future<void>.delayed(Duration.zero);

      expect(store.saveCallCount, 1);
      expect(identical(store.lastSavedSettings, settings), isTrue);
    });

    test('swallows the failure and logs instead of escaping', () async {
      final _RecordingSettingsStore store = _RecordingSettingsStore(
        saveError: StateError('boom'),
      );
      const AppSettings settings = AppSettings.defaults;

      final List<String> printed = <String>[];
      // Use runZonedGuarded so an unhandled future error in the helper
      // would explicitly fail the test rather than silently leaking.
      final List<Object> unhandled = <Object>[];
      await _withCapturedDebugPrint(printed, () async {
        await runZonedGuarded(() async {
          saveSettingsUnawaited(store, settings);
          await Future<void>.delayed(Duration.zero);
        }, (Object e, StackTrace _) => unhandled.add(e));
      });

      expect(store.saveCallCount, 1);
      expect(
        unhandled,
        isEmpty,
        reason:
            'saveSettingsUnawaited must catch errors so they do not surface '
            'as unhandled future errors.',
      );
      final String joined = printed.join('\n');
      expect(joined, contains('saveSettingsUnawaited'));
      expect(joined, contains('FAILED'));
      expect(joined, isNot(contains('AppSettings(')));
    });
  });
}

/// Runs [body] with [debugPrint] redirected into [sink] and restored
/// afterwards.  Used to capture the debug-build error log written by
/// [appErrorLog] without coupling to its private formatting.
Future<void> _withCapturedDebugPrint(
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

/// Minimal [SettingsStore] fake that records [save] invocations and can
/// be configured to throw on [save].  Other [SettingsStore] members are
/// not exercised by [saveSettings] / [saveSettingsUnawaited] and throw
/// [UnimplementedError] to surface accidental coupling in tests.
class _RecordingSettingsStore implements SettingsStore {
  _RecordingSettingsStore({this.saveError});

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
