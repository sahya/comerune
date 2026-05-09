import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/widgets/settings_widgets.dart';

import '../../helpers/recording_settings_store.dart';

void main() {
  group('saveSettingsToStore', () {
    test('forwards settings to store.save and completes on success', () async {
      final RecordingSettingsStore store = RecordingSettingsStore();
      const AppSettings settings = AppSettings.defaults;

      await saveSettingsToStore(store, settings);

      expect(store.saveCallCount, 1);
      expect(identical(store.lastSavedSettings, settings), isTrue);
    });

    test(
      'swallows store.save failures and logs through SettingsSaveHelper',
      () async {
        final RecordingSettingsStore store = RecordingSettingsStore(
          saveError: StateError('boom'),
        );
        const AppSettings settings = AppSettings.defaults;

        final List<String> printed = <String>[];
        final List<Object> unhandled = <Object>[];

        await withCapturedDebugPrint(printed, () async {
          await runZonedGuarded(() async {
            // The wrapper must NOT rethrow even though the underlying
            // helper rethrows; the legacy
            // unawaited(saveSettingsToStore(...)) caller would otherwise
            // surface as an unhandled future error.
            await saveSettingsToStore(store, settings);
          }, (Object e, StackTrace _) => unhandled.add(e));
        });

        expect(store.saveCallCount, 1);
        expect(
          unhandled,
          isEmpty,
          reason:
              'saveSettingsToStore must swallow errors so legacy unawaited '
              'callers do not surface them as unhandled future errors.',
        );

        final String joined = printed.join('\n');
        // The wrapper must route persistence failures through
        // SettingsSaveHelper so every settings flow surfaces under the
        // same single logging path (Issue #781). The helper-emitted
        // message format is the observable contract here.
        expect(joined, contains('saveSettings: SettingsStore.save FAILED'));
        // Exactly one helper-emitted message — guards against double
        // logging if the wrapper ever stops swallowing and a future
        // outer layer logs a second time.
        final int messageHits = printed
            .where(
              (String line) =>
                  line.contains('saveSettings: SettingsStore.save FAILED'),
            )
            .length;
        expect(messageHits, 1);
        // PII protection regression guard: the AppSettings payload itself
        // must never appear in the captured log output.
        expect(joined, isNot(contains('AppSettings(')));
      },
    );
  });
}
