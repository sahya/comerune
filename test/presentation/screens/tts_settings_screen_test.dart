import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/tts_settings_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

const Key _listKey = Key('tts-settings-list');

Future<void> _selectNemoStyle(WidgetTester tester, String styleLabel) async {
  final Finder dropdownFinder = find.byKey(
    const Key('voicevox-style-dropdown'),
    skipOffstage: false,
  );
  await tester.tap(dropdownFinder);
  await tester.pumpAndSettle();
  await tester.tap(find.text(styleLabel).last);
  await tester.pumpAndSettle();
}

Future<List<String>> _captureDebugLogs(Future<void> Function() action) async {
  final List<String> logs = <String>[];
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      logs.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
  }
  return logs;
}

void main() {
  group('TtsSettingsScreen', () {
    testWidgets('shows VOICEVOX section without engine selection', (
      WidgetTester tester,
    ) async {
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('voicevox-section'));
      expect(
        find.byKey(const Key('voicevox-section'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('engine-bouyomi-radio'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('engine-voicevox-radio'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('bouyomi-section'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      'shows validation error and does not save invalid queue limit',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await enterTextByKey(
          tester,
          _listKey,
          const Key('queue-limit-field'),
          'abc',
        );
        await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

        expect(find.text('数値を入力してください', skipOffstage: false), findsOneWidget);
        AppSettings loaded = await settingsStore.load();
        expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

        await enterTextByKey(
          tester,
          _listKey,
          const Key('queue-limit-field'),
          '0',
        );
        await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

        expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false),
          findsOneWidget,
        );
        loaded = await settingsStore.load();
        expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

        await enterTextByKey(
          tester,
          _listKey,
          const Key('queue-limit-field'),
          '35',
        );
        await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

        loaded = await settingsStore.load();
        expect(loaded.queueLimit, 35);
        expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets('shows validation error and does not save invalid max delay', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await enterTextByKey(
        tester,
        _listKey,
        const Key('max-delay-field'),
        'abc',
      );
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      AppSettings loaded = await settingsStore.load();
      expect(loaded.maxDelaySeconds, AppSettings.defaults.maxDelaySeconds);

      await enterTextByKey(tester, _listKey, const Key('max-delay-field'), '0');
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      loaded = await settingsStore.load();
      expect(loaded.maxDelaySeconds, AppSettings.defaults.maxDelaySeconds);
    });

    testWidgets('saves text fields when focus is lost', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await enterTextByKey(
        tester,
        _listKey,
        const Key('queue-limit-field'),
        '50',
      );
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      await enterTextByKey(
        tester,
        _listKey,
        const Key('ng-words-field'),
        '^w+\$',
      );
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, 50);
      expect(loaded.ngWords, '^w+\$');
    });

    testWidgets('persists values and reloads on reopened screen', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await toggleSwitchByKey(tester, _listKey, const Key('auto-read-switch'));
      await enterTextByKey(
        tester,
        _listKey,
        const Key('ng-words-field'),
        '^8+\$',
      );
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      // Re-open the screen to verify values are reloaded from store
      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('ng-words-field'));
      final TextFormField ngWordsField = tester.widget(
        find.byKey(const Key('ng-words-field'), skipOffstage: false),
      );
      expect(ngWordsField.controller?.text, '^8+\$');
    });

    testWidgets('rejects invalid regex in NG words and shows error', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Enter invalid regex pattern.
      await enterTextByKey(
        tester,
        _listKey,
        const Key('ng-words-field'),
        '[invalid',
      );

      // Unfocus explicitly by tapping outside the text field.
      // FocusManager ensures _onNgWordsFocusChanged fires.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Scroll to the ng-words field to make error text visible.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('ng-words-field'),
      );

      // Error message should be visible.
      expect(
        find.textContaining('無効な正規表現', skipOffstage: false),
        findsOneWidget,
      );

      // Value should NOT be persisted.
      final AppSettings loaded = await settingsStore.load();
      expect(loaded.ngWords, isEmpty);
    });

    testWidgets('auto-read toggle persists value', (WidgetTester tester) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.autoReadEnabled, isFalse);

      await toggleSwitchByKey(tester, _listKey, const Key('auto-read-switch'));

      loaded = await settingsStore.load();
      expect(loaded.autoReadEnabled, isTrue);
    });

    testWidgets('slash prefix skip toggle persists value (default ON)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be ON
      AppSettings loaded = await settingsStore.load();
      expect(loaded.slashPrefixSkipEnabled, isTrue);

      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('slash-prefix-skip-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.slashPrefixSkipEnabled, isFalse);
    });

    testWidgets('star prefix hiding toggle persists value (default OFF)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be OFF
      AppSettings loaded = await settingsStore.load();
      expect(loaded.starPrefixHidingEnabled, isFalse);

      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('star-prefix-hiding-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.starPrefixHidingEnabled, isTrue);
    });

    testWidgets('read user name toggle persists value (default OFF)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Default should be OFF
      AppSettings loaded = await settingsStore.load();
      expect(loaded.readUserName, isFalse);

      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('read-user-name-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.readUserName, isTrue);
    });

    testWidgets('VOICEVOX speed slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-speed-slider'),
      );

      // Simulate slider onChanged by finding the SettingsDoubleSliderField
      // and invoking its onChanged callback with a new value.
      final Finder sliderFinder = find.byKey(
        const Key('voicevox-speed-slider'),
        skipOffstage: false,
      );
      expect(sliderFinder, findsOneWidget);

      // Find the Slider widget inside the SettingsDoubleSliderField
      final Finder innerSlider = find.descendant(
        of: sliderFinder,
        matching: find.byType(Slider),
      );
      expect(innerSlider, findsOneWidget);

      final Slider slider = tester.widget<Slider>(innerSlider);
      // Invoke onChanged with a new value (1.5)
      slider.onChanged!(1.5);
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeed, 1.5);
    });

    testWidgets('VOICEVOX pitch slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-pitch-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('voicevox-pitch-slider'),
        skipOffstage: false,
      );
      final Finder innerSlider = find.descendant(
        of: sliderFinder,
        matching: find.byType(Slider),
      );
      expect(innerSlider, findsOneWidget);

      final Slider slider = tester.widget<Slider>(innerSlider);
      slider.onChanged!(0.05);
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxPitch, 0.05);
    });

    testWidgets('VOICEVOX intonation slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-intonation-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('voicevox-intonation-slider'),
        skipOffstage: false,
      );
      final Finder innerSlider = find.descendant(
        of: sliderFinder,
        matching: find.byType(Slider),
      );
      expect(innerSlider, findsOneWidget);

      final Slider slider = tester.widget<Slider>(innerSlider);
      slider.onChanged!(1.5);
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxIntonation, 1.5);
    });

    testWidgets('VOICEVOX volume slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-volume-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('voicevox-volume-slider'),
        skipOffstage: false,
      );
      final Finder innerSlider = find.descendant(
        of: sliderFinder,
        matching: find.byType(Slider),
      );
      expect(innerSlider, findsOneWidget);

      final Slider slider = tester.widget<Slider>(innerSlider);
      slider.onChanged!(0.8);
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxVolume, 0.8);
    });

    testWidgets('VOICEVOX style dropdown energetic persists values', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-style-dropdown'),
      );
      await _selectNemoStyle(tester, '元気');

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeed, closeTo(1.3, 0.0001));
      expect(loaded.voicevoxPitch, closeTo(0.08, 0.0001));
      expect(loaded.voicevoxIntonation, closeTo(1.3, 0.0001));
      expect(loaded.voicevoxVolume, closeTo(1.0, 0.0001));
    });

    testWidgets('VOICEVOX style dropdown calm pushes settings to platform', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, fakePlatform),
      );
      await tester.pumpAndSettle();

      fakePlatform.lastUpdatedSettings = null;

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-style-dropdown'),
      );
      await _selectNemoStyle(tester, '落ち着き');

      expect(fakePlatform.lastUpdatedSettings, isNotNull);
      expect(
        fakePlatform.lastUpdatedSettings!.speedScale,
        closeTo(1.0, 0.0001),
      );
      expect(
        fakePlatform.lastUpdatedSettings!.pitchScale,
        closeTo(-0.02, 0.0001),
      );
      expect(
        fakePlatform.lastUpdatedSettings!.intonationScale,
        closeTo(0.9, 0.0001),
      );
      expect(
        fakePlatform.lastUpdatedSettings!.volumeScale,
        closeTo(1.0, 0.0001),
      );
    });

    testWidgets('VOICEVOX style dropdown standard resets values to defaults', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(
          voicevoxSpeed: 1.4,
          voicevoxPitch: 0.08,
          voicevoxIntonation: 1.4,
          voicevoxVolume: 1.2,
        ),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-style-dropdown'),
      );
      await _selectNemoStyle(tester, '標準');

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeed, closeTo(1.0, 0.0001));
      expect(loaded.voicevoxPitch, closeTo(0.0, 0.0001));
      expect(loaded.voicevoxIntonation, closeTo(1.0, 0.0001));
      expect(loaded.voicevoxVolume, closeTo(1.0, 0.0001));
    });

    testWidgets('hides style dropdown when selected speaker is non-Nemo', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(voicevoxSpeaker: 0),
      );
      final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
      platform.availableModelsToReturn = <Map<String, dynamic>>[
        <String, dynamic>{
          'modelId': '0',
          'displayName': 'VOICEVOX 四国めたん・ずんだもん',
          'speakerIds': <int>[0, 2, 3],
          'vvmFileName': '0.vvm',
          'fileSizeBytes': 100,
          'isBundled': true,
          'downloadState': 'DOWNLOADED',
        },
      ];

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, platform),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      'hides style dropdown when synthesis mode is oneShot for Nemo speaker',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(
            voicevoxSpeaker: 10000,
            voicevoxSynthesisMode: SynthesisMode.oneShot,
          ),
        );

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const Key('voicevox-style-dropdown'),
            skipOffstage: false,
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'does not reset speaker when models are still loading',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        // Save a non-Nemo speaker (Kasukabe Tsumugi)
        await settingsStore.save(
          AppSettings.defaults.copyWith(voicevoxSpeaker: 8),
        );
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        // Return models including the non-Nemo speaker
        platform.availableModelsToReturn = <Map<String, dynamic>>[
          <String, dynamic>{
            'modelId': 'n0',
            'displayName': 'VOICEVOX Nemo',
            'speakerIds': <int>[
              10000,
              10001,
              10002,
              10003,
              10004,
              10005,
              10006,
              10007,
              10008
            ],
            'vvmFileName': 'n0.vvm',
            'fileSizeBytes': 100,
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
          <String, dynamic>{
            'modelId': '2',
            'displayName': 'VOICEVOX 春日部つむぎ',
            'speakerIds': <int>[8],
            'vvmFileName': '2.vvm',
            'fileSizeBytes': 100,
            'isBundled': false,
            'downloadState': 'DOWNLOADED',
          },
        ];

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        // Verify the speaker was NOT reset to 10000
        final AppSettings loaded = await settingsStore.load();
        expect(loaded.voicevoxSpeaker, 8);
      },
    );

    testWidgets(
      'shows fallback dropdown when model loading fails',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        // Simulate getAvailableModels throwing an error
        platform.availableModelsToReturn = <Map<String, dynamic>>[];

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        // Dropdown should be present (not stuck in loading)
        expect(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'performance hint does not contain recommended label',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Verify "推奨" is not in any visible text
        expect(find.textContaining('推奨', skipOffstage: false), findsNothing);
      },
    );

    testWidgets(
      'slider change pushes updated SpeechSettings to platform engine',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        // Initially no updateSettings call has been made (beyond _loadSettings).
        fakePlatform.lastUpdatedSettings = null;

        // Change speed slider
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speed-slider'),
        );
        final Finder speedSliderFinder = find.byKey(
          const Key('voicevox-speed-slider'),
          skipOffstage: false,
        );
        final Finder speedInnerSlider = find.descendant(
          of: speedSliderFinder,
          matching: find.byType(Slider),
        );
        final Slider speedSlider = tester.widget<Slider>(speedInnerSlider);
        speedSlider.onChanged!(1.5);
        await tester.pumpAndSettle();

        // Verify updateSettings was called with the new speed value
        expect(fakePlatform.lastUpdatedSettings, isNotNull);
        expect(fakePlatform.lastUpdatedSettings!.speedScale, 1.5);

        // Change pitch slider
        fakePlatform.lastUpdatedSettings = null;
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-pitch-slider'),
        );
        final Finder pitchSliderFinder = find.byKey(
          const Key('voicevox-pitch-slider'),
          skipOffstage: false,
        );
        final Finder pitchInnerSlider = find.descendant(
          of: pitchSliderFinder,
          matching: find.byType(Slider),
        );
        final Slider pitchSlider = tester.widget<Slider>(pitchInnerSlider);
        pitchSlider.onChanged!(0.1);
        await tester.pumpAndSettle();

        expect(fakePlatform.lastUpdatedSettings, isNotNull);
        expect(fakePlatform.lastUpdatedSettings!.pitchScale, 0.1);
        // Previous speed change should also be reflected
        expect(fakePlatform.lastUpdatedSettings!.speedScale, 1.5);
      },
    );

    testWidgets(
      'auto-read toggle pushes updated SpeechSettings to platform engine',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        fakePlatform.lastUpdatedSettings = null;

        await toggleSwitchByKey(
          tester,
          _listKey,
          const Key('auto-read-switch'),
        );

        expect(fakePlatform.lastUpdatedSettings, isNotNull);
        expect(fakePlatform.lastUpdatedSettings!.enabled, isTrue);
      },
    );

    testWidgets('does not call updateSettings when platform is null', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      // Build without platform (platform is null)
      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // Change speed slider - should not throw
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-speed-slider'),
      );
      final Finder speedSliderFinder = find.byKey(
        const Key('voicevox-speed-slider'),
        skipOffstage: false,
      );
      final Finder speedInnerSlider = find.descendant(
        of: speedSliderFinder,
        matching: find.byType(Slider),
      );
      final Slider speedSlider = tester.widget<Slider>(speedInnerSlider);
      speedSlider.onChanged!(1.5);
      await tester.pumpAndSettle();

      // Verify value was saved to store (existing behavior still works)
      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeed, 1.5);
    });

    testWidgets('platform null fallback normalizes unavailable speaker ID', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(voicevoxSpeaker: 10005),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeaker, 10004);
      expect(
        find.text('Nemo | 女声3 (ID:10004)', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('shows Nemo speaker name with speaker ID in menu label', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
      platform.availableModelsToReturn = <Map<String, dynamic>>[
        <String, dynamic>{
          'modelId': 'n0',
          'displayName': 'VOICEVOX Nemo',
          'speakerIds': <int>[
            10000,
            10001,
            10002,
            10003,
            10004,
            10005,
            10006,
            10007,
            10008,
          ],
          'vvmFileName': 'n0.vvm',
          'fileSizeBytes': 100,
          'isBundled': false,
          'downloadState': 'DOWNLOADED',
        },
      ];

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, platform),
      );
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-speaker-dropdown'),
      );

      expect(
        find.text('Nemo | 女声3 (ID:10004)', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('ID:10004', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets(
      'orders Nemo speakers by number and picks 女声1 as first option',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(voicevoxSpeaker: 99999),
        );

        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        platform.availableModelsToReturn = <Map<String, dynamic>>[
          <String, dynamic>{
            'modelId': 'n0',
            'displayName': 'VOICEVOX Nemo',
            'speakerIds': <int>[
              10000,
              10001,
              10002,
              10003,
              10004,
              10005,
              10006,
              10007,
              10008,
            ],
            'vvmFileName': 'n0.vvm',
            'fileSizeBytes': 100,
            'isBundled': false,
            'downloadState': 'DOWNLOADED',
          },
        ];

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        final AppSettings loaded = await settingsStore.load();
        expect(loaded.voicevoxSpeaker, 10005);
      },
    );

    group('speaker change', () {
      /// Helper to create a fake platform pre-configured with two models.
      FakeCommentSpeechPlatform createPlatformWithModels() {
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        platform.availableModelsToReturn = <Map<String, dynamic>>[
          <String, dynamic>{
            'modelId': 'model-a',
            'displayName': 'Speaker A',
            'speakerIds': <int>[0],
            'vvmFileName': 'a.vvm',
            'fileSizeBytes': 100,
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
          <String, dynamic>{
            'modelId': 'model-b',
            'displayName': 'Speaker B',
            'speakerIds': <int>[1],
            'vvmFileName': 'b.vvm',
            'fileSizeBytes': 200,
            'isBundled': false,
            'downloadState': 'DOWNLOADED',
          },
        ];
        return platform;
      }

      testWidgets(
        'successful speaker change loads model then pushes settings',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          // Clear tracking state after initial load.
          platform.lastUpdatedSettings = null;
          platform.loadedModelIds.clear();

          // Trigger speaker change via the dropdown's onChanged.
          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          // The onChanged is not null because _isLoadingModel is false.
          dropdown.onChanged!(1);
          await tester.pumpAndSettle();

          // Model was loaded for the new speaker.
          expect(platform.loadedModelIds, contains('model-b'));

          // updateSettings was pushed with the new speaker ID.
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 1);

          // Persisted value matches.
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 1);
        },
      );

      testWidgets('speaker unchanged is treated as no-op', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = createPlatformWithModels();

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        platform.loadedModelIds.clear();
        platform.lastUpdatedSettings = null;

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown =
            tester.widget<DropdownButtonFormField<int>>(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
        );
        // Initial speaker is 0 in this test setup.
        final List<String> logs = await _captureDebugLogs(() async {
          dropdown.onChanged!(0);
          await tester.pumpAndSettle();
        });

        expect(platform.loadedModelIds, isEmpty);
        expect(platform.lastUpdatedSettings, isNull);
        expect(
          logs.any(
            (line) =>
                line.contains('decision=no_op_same_speaker') &&
                line.contains('fromSpeaker=0 toSpeaker=0'),
          ),
          isTrue,
        );
      });

      testWidgets(
        'speaker change initializes engine before model loading when needed',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          platform.statusToReturn = const SpeechRuntimeStatus(
            enabled: false,
            engineState: 'UNINITIALIZED',
            playerState: 'UNKNOWN',
            queueSize: 0,
            currentSpeakerId: 0,
          );

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          dropdown.onChanged!(1);
          await tester.pumpAndSettle();

          expect(platform.initializeCalled, isTrue);
          expect(platform.loadedModelIds, contains('model-b'));
        },
      );

      testWidgets('speaker change skips initialize when engine is READY', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = createPlatformWithModels();
        platform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'READY',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 0,
        );

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown =
            tester.widget<DropdownButtonFormField<int>>(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
        );
        dropdown.onChanged!(1);
        await tester.pumpAndSettle();

        expect(platform.initializeCalled, isFalse);
        expect(platform.loadedModelIds, contains('model-b'));
      });

      testWidgets('speaker change in same model skips redundant model load', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = createPlatformWithModels();
        // Put speaker 2 in the same model as speaker 1.
        platform.availableModelsToReturn[1]['speakerIds'] = <int>[1, 2];
        platform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'READY',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 1,
        );

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        platform.lastUpdatedSettings = null;
        platform.loadedModelIds.clear();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown =
            tester.widget<DropdownButtonFormField<int>>(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
        );
        dropdown.onChanged!(2);
        await tester.pumpAndSettle();

        expect(platform.loadedModelIds, isEmpty);
        expect(platform.lastUpdatedSettings, isNotNull);
        expect(platform.lastUpdatedSettings!.speakerId, 2);
      });

      testWidgets(
        'speaker change continues model load when status refresh fails',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          platform.statusToReturn = const SpeechRuntimeStatus(
            enabled: true,
            engineState: 'READY',
            playerState: 'IDLE',
            queueSize: 0,
            currentSpeakerId: 0,
          );
          platform.getStatusError = Exception('status failed');
          platform.getStatusErrorAtCall = 2;

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          platform.loadedModelIds.clear();
          platform.lastUpdatedSettings = null;

          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          dropdown.onChanged!(1);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, contains('model-b'));
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 1);
        },
      );

      testWidgets(
        'speaker change skips redundant model load when status refresh fails and settings speaker is same model',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          await settingsStore.save(
            AppSettings.defaults.copyWith(voicevoxSpeaker: 1),
          );

          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          // Put speaker 2 in the same model as speaker 1.
          platform.availableModelsToReturn[1]['speakerIds'] = <int>[1, 2];
          platform.statusToReturn = const SpeechRuntimeStatus(
            enabled: true,
            engineState: 'READY',
            playerState: 'IDLE',
            queueSize: 0,
            currentSpeakerId: 1,
          );
          platform.getStatusError = Exception('status failed');
          platform.getStatusErrorAtCall = 2;

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          platform.loadedModelIds.clear();
          platform.lastUpdatedSettings = null;

          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          dropdown.onChanged!(2);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, isEmpty);
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 2);
        },
      );

      testWidgets(
        'speaker change loads model when currentSpeakerId is unknown',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          platform.statusToReturn = const SpeechRuntimeStatus(
            enabled: true,
            engineState: 'READY',
            playerState: 'IDLE',
            queueSize: 0,
            currentSpeakerId: 999999,
          );

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          platform.loadedModelIds.clear();
          platform.lastUpdatedSettings = null;

          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          dropdown.onChanged!(1);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, contains('model-b'));
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 1);
        },
      );

      testWidgets(
        'failed model load reverts speaker and shows error snackbar',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          platform.loadModelError = Exception('disk full');

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          // Clear tracking after initial load.
          platform.lastUpdatedSettings = null;

          // Trigger speaker change to speaker 1 (will fail).
          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          dropdown.onChanged!(1);
          await tester.pumpAndSettle();

          // updateSettings should NOT have been called because the load failed.
          expect(platform.lastUpdatedSettings, isNull);

          // Error snackbar is shown.
          expect(
            find.byKey(const Key('speaker-load-error-snackbar')),
            findsOneWidget,
          );

          // Speaker was reverted to the original (0).
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 0);
        },
      );

      testWidgets('shows loading indicator while model is loading', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = createPlatformWithModels();
        final Completer<void> loadCompleter = Completer<void>();
        platform.loadModelCompleter = loadCompleter;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        // Trigger speaker change — loadModel will hang on the completer.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown =
            tester.widget<DropdownButtonFormField<int>>(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
        );
        dropdown.onChanged!(1);
        await tester.pump(); // Process the setState for _isLoadingModel = true.

        // Loading indicator should be visible.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsOneWidget,
        );

        // Dropdown should be disabled (onChanged is null).
        final DropdownButtonFormField<int> disabledDropdown =
            tester.widget<DropdownButtonFormField<int>>(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
        );
        expect(disabledDropdown.onChanged, isNull);

        // Complete the load.
        loadCompleter.complete();
        await tester.pumpAndSettle();

        // Loading indicator should be gone.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsNothing,
        );
      });

      testWidgets(
        'rapid speaker changes discard stale results (race condition)',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();

          // Add a third model for the second change target.
          platform.availableModelsToReturn.add(<String, dynamic>{
            'modelId': 'model-c',
            'displayName': 'Speaker C',
            'speakerIds': <int>[2],
            'vvmFileName': 'c.vvm',
            'fileSizeBytes': 300,
            'isBundled': false,
            'downloadState': 'DOWNLOADED',
          });

          // First load will be slow; second will be instant.
          final Completer<void> firstLoadCompleter = Completer<void>();
          platform.loadModelCompleter = firstLoadCompleter;

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          platform.lastUpdatedSettings = null;
          platform.loadedModelIds.clear();

          // First change: speaker 0 → 1 (slow).
          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown1 =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );
          final List<String> logs = await _captureDebugLogs(() async {
            // First change: speaker 0 -> 1 (slow).
            dropdown1.onChanged!(1);
            await tester.pump();

            // Trigger a second change while the first load is still in-flight.
            platform.loadModelCompleter =
                null; // Second load returns immediately.
            dropdown1.onChanged!(2);
            await tester.pumpAndSettle();

            // Complete the stale first load.
            firstLoadCompleter.complete();
            await tester.pumpAndSettle();
          });

          // The final speaker should be the second request target (2).
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 2);
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 2);
          expect(
            platform.loadedModelIds,
            containsAll(<String>['model-b', 'model-c']),
          );
          expect(
            logs.any((line) => line.contains('reason=stale_generation')),
            isTrue,
          );
        },
      );

      testWidgets(
        'in-flight speaker change logs widget_unmounted reason when screen is disposed',
        (WidgetTester tester) async {
          final SharedPreferencesSettingsStore settingsStore =
              SharedPreferencesSettingsStore(
            prefs: InMemorySharedPreferences(),
          );
          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          final Completer<void> loadCompleter = Completer<void>();
          platform.loadModelCompleter = loadCompleter;

          await tester.pumpWidget(
            _buildScreenWithPlatform(settingsStore, platform),
          );
          await tester.pumpAndSettle();

          await scrollToKeyInList(
            tester,
            _listKey,
            const Key('voicevox-speaker-dropdown'),
          );
          final DropdownButtonFormField<int> dropdown =
              tester.widget<DropdownButtonFormField<int>>(
            find.byKey(
              const Key('voicevox-speaker-dropdown'),
              skipOffstage: false,
            ),
          );

          final List<String> logs = await _captureDebugLogs(() async {
            dropdown.onChanged!(1);
            await tester.pump();

            // Dispose the screen while model load is still in-flight.
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();

            loadCompleter.complete();
            await tester.pumpAndSettle();
          });

          expect(
            logs.any((line) => line.contains('reason=widget_unmounted')),
            isTrue,
          );
        },
      );
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(home: TtsSettingsScreen(settingsStore: settingsStore));
}

Widget _buildScreenWithPlatform(
  SettingsStore settingsStore,
  CommentSpeechPlatform platform,
) {
  return MaterialApp(
    home: TtsSettingsScreen(settingsStore: settingsStore, platform: platform),
  );
}
