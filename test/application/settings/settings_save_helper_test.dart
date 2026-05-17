import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_save_helper.dart';
import 'package:comerune/domain/models/app_settings.dart';

import '../../helpers/recording_settings_store.dart';

void main() {
  group('saveSettings', () {
    test('awaits store.save and returns when persistence succeeds', () async {
      final RecordingSettingsStore store = RecordingSettingsStore();
      const AppSettings settings = AppSettings.defaults;

      await saveSettings(store, settings);

      expect(store.saveCallCount, 1);
      expect(identical(store.lastSavedSettings, settings), isTrue);
    });

    test('rethrows after logging when store.save throws', () async {
      final RecordingSettingsStore store = RecordingSettingsStore(
        saveError: StateError('boom'),
      );
      const AppSettings settings = AppSettings.defaults;

      final List<String> printed = <String>[];
      await withCapturedDebugPrint(printed, () async {
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
      final RecordingSettingsStore store = RecordingSettingsStore();
      const AppSettings settings = AppSettings.defaults;

      saveSettingsUnawaited(store, settings);
      // Allow the unawaited future to run.
      await Future<void>.delayed(Duration.zero);

      expect(store.saveCallCount, 1);
      expect(identical(store.lastSavedSettings, settings), isTrue);
    });

    test('swallows the failure and logs instead of escaping', () async {
      final RecordingSettingsStore store = RecordingSettingsStore(
        saveError: StateError('boom'),
      );
      const AppSettings settings = AppSettings.defaults;

      final List<String> printed = <String>[];
      // Use runZonedGuarded so an unhandled future error in the helper
      // would explicitly fail the test rather than silently leaking.
      final List<Object> unhandled = <Object>[];
      await withCapturedDebugPrint(printed, () async {
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
