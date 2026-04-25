import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/application/speech/speech_availability_notifier.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/tts_settings_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';
import '../../helpers/settings_test_helpers.dart';

const Key _listKey = Key('tts-settings-list');

Future<void> _selectNemoStyle(WidgetTester tester, String styleLabel) async {
  // Make sure the dropdown is fully within the tappable region of the
  // viewport. Without this extra ensureVisible, the dropdown can end up
  // partially clipped after prior scrolls (e.g. when the TTS section has
  // grown with additional toggles), and the tap is silently dropped.
  final Finder dropdownFinder = find.byKey(
    const Key('voicevox-style-dropdown'),
    skipOffstage: false,
  );
  await tester.ensureVisible(dropdownFinder);
  await tester.pumpAndSettle();
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
        find.byKey(const Key('engine-voicevox-radio'), skipOffstage: false),
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

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, 50);
    });

    testWidgets('shows NG word list tile with count', (
      WidgetTester tester,
    ) async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      await prefs.setString(
        'settings.filter.ngWordRules',
        '[{"pattern":"test","enabled":true},{"pattern":"foo","enabled":false}]',
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('ng-word-list-tile'));

      expect(find.text('NGワード管理', skipOffstage: false), findsOneWidget);
      expect(find.text('2件登録中', skipOffstage: false), findsOneWidget);
    });

    testWidgets('shows empty subtitle when no NG word rules exist', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('ng-word-list-tile'));

      expect(find.text('未登録', skipOffstage: false), findsOneWidget);
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

    testWidgets('read gift comment toggle persists value (default OFF)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.readGiftComment, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('read-gift-comment-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('read-gift-comment-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.readGiftComment, isTrue);
    });

    testWidgets('read nicoad comment toggle persists value (default OFF)', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      AppSettings loaded = await settingsStore.load();
      expect(loaded.readNicoadComment, isFalse);

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('read-nicoad-comment-switch'),
      );
      await toggleSwitchByKey(
        tester,
        _listKey,
        const Key('read-nicoad-comment-switch'),
      );

      loaded = await settingsStore.load();
      expect(loaded.readNicoadComment, isTrue);
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
          find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets('does not reset speaker when models are still loading', (
      WidgetTester tester,
    ) async {
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
            10008,
          ],
          'vvmFileName': 'n0.vvm',
          'fileSizeBytes': 100,
          'isBundled': true,
          'downloadState': 'DOWNLOADED',
        },
        <String, dynamic>{
          'modelId': '0',
          'displayName': 'VOICEVOX 春日部つむぎ',
          'speakerIds': <int>[8],
          'vvmFileName': '0.vvm',
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
    });

    testWidgets('shows fallback dropdown when model loading fails', (
      WidgetTester tester,
    ) async {
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
        find.byKey(const Key('voicevox-speaker-dropdown'), skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('performance hint does not contain recommended label', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      // The performance hint text should not contain "推奨".
      // Note: the player type dropdown label still says "低遅延モード（推奨）"
      // which is intentional, so we check the hint text specifically.
      expect(
        find.text('応答が速く、声の調整も可能な構成です', skipOffstage: false),
        findsOneWidget,
      );
    });

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

    testWidgets(
      'switching from audioQuery to oneShot hides style dropdown and sliders',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        // Start with a Nemo speaker in audioQuery mode (default).
        await settingsStore.save(
          AppSettings.defaults.copyWith(
            voicevoxSpeaker: 10000,
            voicevoxSynthesisMode: SynthesisMode.audioQuery,
          ),
        );

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Style dropdown should be visible initially (Nemo + audioQuery).
        expect(
          find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
          findsOneWidget,
        );
        // Speed slider should be visible initially.
        expect(
          find.byKey(const Key('voicevox-speed-slider'), skipOffstage: false),
          findsOneWidget,
        );

        // Switch to oneShot mode via the segmented button callback.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('synthesis-mode-selector'),
        );
        final SegmentedButton<SynthesisMode> segmented = tester
            .widget<SegmentedButton<SynthesisMode>>(
              find.byKey(
                const Key('synthesis-mode-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SynthesisMode>{SynthesisMode.oneShot});
        await tester.pumpAndSettle();

        // Style dropdown should now be hidden.
        expect(
          find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
          findsNothing,
        );
        // Speed slider should be hidden in oneShot mode.
        expect(
          find.byKey(const Key('voicevox-speed-slider'), skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets(
      'switching from oneShot to audioQuery shows style dropdown and sliders for Nemo speaker',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        // Start with a Nemo speaker in oneShot mode.
        await settingsStore.save(
          AppSettings.defaults.copyWith(
            voicevoxSpeaker: 10000,
            voicevoxSynthesisMode: SynthesisMode.oneShot,
          ),
        );

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Style dropdown should be hidden initially (oneShot).
        expect(
          find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
          findsNothing,
        );

        // Switch to audioQuery mode.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('synthesis-mode-selector'),
        );
        final SegmentedButton<SynthesisMode> segmented = tester
            .widget<SegmentedButton<SynthesisMode>>(
              find.byKey(
                const Key('synthesis-mode-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SynthesisMode>{
          SynthesisMode.audioQuery,
        });
        await tester.pumpAndSettle();

        // Style dropdown should now be visible.
        expect(
          find.byKey(const Key('voicevox-style-dropdown'), skipOffstage: false),
          findsOneWidget,
        );
        // Speed slider should now be visible.
        expect(
          find.byKey(const Key('voicevox-speed-slider'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'initialSettings preserves speaker when platform loads models',
      (WidgetTester tester) async {
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
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
          <String, dynamic>{
            'modelId': '0',
            'displayName': 'VOICEVOX 春日部つむぎ',
            'speakerIds': <int>[8],
            'vvmFileName': '0.vvm',
            'fileSizeBytes': 100,
            'isBundled': false,
            'downloadState': 'DOWNLOADED',
          },
        ];

        // Pre-loaded settings with a non-default speaker.
        final AppSettings preLoaded = AppSettings.defaults.copyWith(
          voicevoxSpeaker: 8,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TtsSettingsScreen(
              settingsStore: settingsStore,
              platform: platform,
              initialSettings: preLoaded,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The speaker from initialSettings should NOT have been reset.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        expect(dropdown.initialValue, 8);
      },
    );

    testWidgets(
      'shows loading placeholder before models arrive with initialSettings',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        // Simulate empty models (failure/no-models case).
        // Instead, we just check first pump before models arrive.
        platform.availableModelsToReturn = <Map<String, dynamic>>[];

        final AppSettings preLoaded = AppSettings.defaults.copyWith(
          voicevoxSpeaker: 8,
        );

        // To test the loading state, we need models to be null initially.
        // Since FakeCommentSpeechPlatform returns immediately, we test
        // that the dropdown shows the saved speaker value rather than
        // resetting it, even when models list is empty (failure case).
        await tester.pumpWidget(
          MaterialApp(
            home: TtsSettingsScreen(
              settingsStore: settingsStore,
              platform: platform,
              initialSettings: preLoaded,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The speaker dropdown should be present (not stuck in loading).
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
      'shows loading placeholder with LinearProgressIndicator while models are loading',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        final Completer<void> modelsCompleter = Completer<void>();
        platform.getAvailableModelsCompleter = modelsCompleter;
        platform.availableModelsToReturn = <Map<String, dynamic>>[
          <String, dynamic>{
            'modelId': 'n0',
            'displayName': 'VOICEVOX Nemo',
            'speakerIds': <int>[10000],
            'vvmFileName': 'n0.vvm',
            'fileSizeBytes': 100,
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
        ];

        final AppSettings preLoaded = AppSettings.defaults.copyWith(
          voicevoxSpeaker: 10000,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TtsSettingsScreen(
              settingsStore: settingsStore,
              platform: platform,
              initialSettings: preLoaded,
            ),
          ),
        );
        // Pump once to build — models are still loading.
        await tester.pump();

        // Loading indicator should be visible while models are null.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsOneWidget,
        );
        // Dropdown should show "読み込み中…" text.
        expect(find.text('読み込み中…', skipOffstage: false), findsOneWidget);

        // Complete the model loading.
        modelsCompleter.complete();
        await tester.pumpAndSettle();

        // Loading indicator should be gone.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'getAvailableModels throwing sets empty list and shows fallback dropdown',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        platform.getAvailableModelsError = Exception('network error');

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        // Dropdown should be present (not stuck in loading).
        expect(
          find.byKey(
            const Key('voicevox-speaker-dropdown'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        // Loading indicator should NOT be visible.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'loadSettings path (no initialSettings) preserves non-default speaker',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        // Save a non-default speaker before opening the screen.
        await settingsStore.save(
          AppSettings.defaults.copyWith(voicevoxSpeaker: 10005),
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
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
        ];

        // Open WITHOUT initialSettings — triggers loadSettings() path.
        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, platform),
        );
        await tester.pumpAndSettle();

        // Speaker should NOT have been reset.
        final AppSettings loaded = await settingsStore.load();
        expect(loaded.voicevoxSpeaker, 10005);

        // Dropdown should show the preserved speaker.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('voicevox-speaker-dropdown'),
        );
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        expect(dropdown.initialValue, 10005);
      },
    );

    group('speaker change', () {
      /// Helper to create a fake platform pre-configured with two models.
      FakeCommentSpeechPlatform createPlatformWithModels() {
        final FakeCommentSpeechPlatform platform = FakeCommentSpeechPlatform();
        platform.availableModelsToReturn = <Map<String, dynamic>>[
          <String, dynamic>{
            'modelId': 'n0',
            'displayName': 'VOICEVOX Nemo',
            'speakerIds': <int>[10004],
            'vvmFileName': 'n0.vvm',
            'fileSizeBytes': 100,
            'isBundled': true,
            'downloadState': 'DOWNLOADED',
          },
          <String, dynamic>{
            'modelId': '0',
            'displayName': '春日部つむぎ',
            'speakerIds': <int>[8],
            'vvmFileName': '0.vvm',
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          // The onChanged is not null because _isLoadingModel is false.
          dropdown.onChanged!(8);
          await tester.pumpAndSettle();

          // Model was loaded for the new speaker.
          expect(platform.loadedModelIds, contains('0'));

          // updateSettings was pushed with the new speaker ID.
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 8);

          // Persisted value matches.
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 8);
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
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        // Initial speaker is 10004 (Nemo default) in this test setup.
        final List<String> logs = await _captureDebugLogs(() async {
          dropdown.onChanged!(10004);
          await tester.pumpAndSettle();
        });

        expect(platform.loadedModelIds, isEmpty);
        expect(platform.lastUpdatedSettings, isNull);
        expect(
          logs.any(
            (line) =>
                line.contains('decision=no_op_same_speaker') &&
                line.contains('fromSpeaker=10004 toSpeaker=10004'),
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          dropdown.onChanged!(8);
          await tester.pumpAndSettle();

          expect(platform.initializeCalled, isTrue);
          expect(platform.loadedModelIds, contains('0'));
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
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        dropdown.onChanged!(8);
        await tester.pumpAndSettle();

        expect(platform.initializeCalled, isFalse);
        expect(platform.loadedModelIds, contains('0'));
      });

      testWidgets('speaker change in same model skips redundant model load', (
        WidgetTester tester,
      ) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform platform = createPlatformWithModels();
        // Put speaker 9 in the same model as speaker 8.
        platform.availableModelsToReturn[1]['speakerIds'] = <int>[8, 9];
        platform.statusToReturn = const SpeechRuntimeStatus(
          enabled: true,
          engineState: 'READY',
          playerState: 'IDLE',
          queueSize: 0,
          currentSpeakerId: 8,
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
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        dropdown.onChanged!(9);
        await tester.pumpAndSettle();

        expect(platform.loadedModelIds, isEmpty);
        expect(platform.lastUpdatedSettings, isNotNull);
        expect(platform.lastUpdatedSettings!.speakerId, 9);
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          dropdown.onChanged!(8);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, contains('0'));
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 8);
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
            AppSettings.defaults.copyWith(voicevoxSpeaker: 8),
          );

          final FakeCommentSpeechPlatform platform = createPlatformWithModels();
          // Put speaker 9 in the same model as speaker 8.
          platform.availableModelsToReturn[1]['speakerIds'] = <int>[8, 9];
          platform.statusToReturn = const SpeechRuntimeStatus(
            enabled: true,
            engineState: 'READY',
            playerState: 'IDLE',
            queueSize: 0,
            currentSpeakerId: 8,
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          dropdown.onChanged!(9);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, isEmpty);
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 9);
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          dropdown.onChanged!(8);
          await tester.pumpAndSettle();

          expect(platform.loadedModelIds, contains('0'));
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 8);
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          dropdown.onChanged!(8);
          await tester.pumpAndSettle();

          // updateSettings should NOT have been called because the load failed.
          expect(platform.lastUpdatedSettings, isNull);

          // Error snackbar is shown.
          expect(
            find.byKey(const Key('speaker-load-error-snackbar')),
            findsOneWidget,
          );

          // Speaker was reverted to the original (10004).
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 10004);
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
        final DropdownButtonFormField<int> dropdown = tester
            .widget<DropdownButtonFormField<int>>(
              find.byKey(
                const Key('voicevox-speaker-dropdown'),
                skipOffstage: false,
              ),
            );
        dropdown.onChanged!(8);
        await tester.pump(); // Process the setState for _isLoadingModel = true.

        // Loading indicator should be visible.
        expect(
          find.byKey(const Key('speaker-loading-indicator')),
          findsOneWidget,
        );

        // Dropdown should be disabled (onChanged is null).
        final DropdownButtonFormField<int> disabledDropdown = tester
            .widget<DropdownButtonFormField<int>>(
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
            'modelId': '3',
            'displayName': '波音リツ',
            'speakerIds': <int>[9],
            'vvmFileName': '3.vvm',
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
          final DropdownButtonFormField<int> dropdown1 = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );
          final List<String> logs = await _captureDebugLogs(() async {
            // First change: speaker 10004 -> 8 (slow).
            dropdown1.onChanged!(8);
            await tester.pump();

            // Trigger a second change while the first load is still in-flight.
            platform.loadModelCompleter =
                null; // Second load returns immediately.
            dropdown1.onChanged!(9);
            await tester.pumpAndSettle();

            // Complete the stale first load.
            firstLoadCompleter.complete();
            await tester.pumpAndSettle();
          });

          // The final speaker should be the second request target (9).
          final AppSettings loaded = await settingsStore.load();
          expect(loaded.voicevoxSpeaker, 9);
          expect(platform.lastUpdatedSettings, isNotNull);
          expect(platform.lastUpdatedSettings!.speakerId, 9);
          expect(platform.loadedModelIds, containsAll(<String>['0', '3']));
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
          final DropdownButtonFormField<int> dropdown = tester
              .widget<DropdownButtonFormField<int>>(
                find.byKey(
                  const Key('voicevox-speaker-dropdown'),
                  skipOffstage: false,
                ),
              );

          final List<String> logs = await _captureDebugLogs(() async {
            dropdown.onChanged!(8);
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

  group('engine selector', () {
    testWidgets('shows SegmentedButton with VOICEVOX and Android TTS options', (
      WidgetTester tester,
    ) async {
      final SettingsStore settingsStore = SharedPreferencesSettingsStore(
        prefs: InMemorySharedPreferences(),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('speech-engine-selector'),
      );
      expect(
        find.byKey(const Key('speech-engine-selector'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('VOICEVOX', skipOffstage: false), findsAtLeast(1));
      expect(find.text('Android標準', skipOffstage: false), findsOneWidget);
    });

    testWidgets(
      'switching to androidTts hides VOICEVOX section and shows Android TTS section',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Initially VOICEVOX section should be visible.
        expect(
          find.byKey(const Key('voicevox-section'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('android-tts-section'), skipOffstage: false),
          findsNothing,
        );

        // Switch to Android TTS.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pumpAndSettle();

        // VOICEVOX section should be hidden.
        expect(
          find.byKey(const Key('voicevox-section'), skipOffstage: false),
          findsNothing,
        );
        // Android TTS section should be visible.
        expect(
          find.byKey(const Key('android-tts-section'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('switching to androidTts persists speechEngine value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('speech-engine-selector'),
      );
      final SegmentedButton<SpeechEngine> segmented = tester
          .widget<SegmentedButton<SpeechEngine>>(
            find.byKey(
              const Key('speech-engine-selector'),
              skipOffstage: false,
            ),
          );
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.speechEngine, SpeechEngine.androidTts);
    });

    testWidgets(
      'switching back to voicevox hides Android TTS section and shows VOICEVOX section',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        // Start with Android TTS selected.
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Android TTS section should be visible.
        expect(
          find.byKey(const Key('android-tts-section'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voicevox-section'), skipOffstage: false),
          findsNothing,
        );

        // Switch back to VOICEVOX.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.voicevox});
        await tester.pumpAndSettle();

        // VOICEVOX section should be visible again.
        expect(
          find.byKey(const Key('voicevox-section'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('android-tts-section'), skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets('engine selector pushes updated SpeechSettings to platform', (
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
        const Key('speech-engine-selector'),
      );
      final SegmentedButton<SpeechEngine> segmented = tester
          .widget<SegmentedButton<SpeechEngine>>(
            find.byKey(
              const Key('speech-engine-selector'),
              skipOffstage: false,
            ),
          );
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
      await tester.pumpAndSettle();

      expect(fakePlatform.lastUpdatedSettings, isNotNull);
      expect(
        fakePlatform.lastUpdatedSettings!.engineType,
        SpeechEngineType.androidTts,
      );
    });
  });

  group('Android TTS sliders', () {
    testWidgets('Android TTS speed slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('android-tts-speed-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('android-tts-speed-slider'),
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
      expect(loaded.androidTtsSpeed, 1.5);
    });

    testWidgets('Android TTS pitch slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('android-tts-pitch-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('android-tts-pitch-slider'),
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
      expect(loaded.androidTtsPitch, 0.8);
    });

    testWidgets('Android TTS volume slider change persists value', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
      );

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('android-tts-volume-slider'),
      );

      final Finder sliderFinder = find.byKey(
        const Key('android-tts-volume-slider'),
        skipOffstage: false,
      );
      final Finder innerSlider = find.descendant(
        of: sliderFinder,
        matching: find.byType(Slider),
      );
      expect(innerSlider, findsOneWidget);

      final Slider slider = tester.widget<Slider>(innerSlider);
      slider.onChanged!(0.4);
      await tester.pumpAndSettle();

      final AppSettings loaded = await settingsStore.load();
      expect(loaded.androidTtsVolume, 0.4);
    });

    testWidgets(
      'Android TTS slider pushes updated SpeechSettings to platform',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
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
          const Key('android-tts-speed-slider'),
        );

        final Finder sliderFinder = find.byKey(
          const Key('android-tts-speed-slider'),
          skipOffstage: false,
        );
        final Finder innerSlider = find.descendant(
          of: sliderFinder,
          matching: find.byType(Slider),
        );
        final Slider slider = tester.widget<Slider>(innerSlider);
        slider.onChanged!(1.8);
        await tester.pumpAndSettle();

        expect(fakePlatform.lastUpdatedSettings, isNotNull);
        expect(fakePlatform.lastUpdatedSettings!.androidTtsSpeed, 1.8);
      },
    );

    testWidgets(
      'Android TTS volume slider clears the Android TTS pre-mute slot when value > 0',
      (WidgetTester tester) async {
        // Issue #697 review #2: VOICEVOX slider already does this; the
        // Android TTS slider was missing the parity behaviour, leaving
        // pre-mute set after the user manually restored a non-zero volume.
        // Without this clear, the next app launch would treat the user as
        // muted again.
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('android-tts-volume-slider'),
        );
        final Slider slider = tester.widget<Slider>(
          find.descendant(
            of: find.byKey(
              const Key('android-tts-volume-slider'),
              skipOffstage: false,
            ),
            matching: find.byType(Slider),
          ),
        );
        slider.onChanged!(0.5);
        await tester.pumpAndSettle();

        expect(
          settingsStore.loadPreMuteAndroidTtsVolume(),
          isNull,
          reason:
              'Manually moving the Android TTS volume slider above 0 must '
              'clear the Android-TTS pre-mute slot, mirroring the VOICEVOX '
              'slider behaviour (Issue #697 review).',
        );
      },
    );

    testWidgets(
      'Android TTS volume slider preserves the pre-mute slot when value stays at 0',
      (WidgetTester tester) async {
        // The clear is intentionally guarded on `value > 0` so the user
        // staying silent does not disturb the pre-mute history kept by the
        // AppBar mute toggle.
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('android-tts-volume-slider'),
        );
        final Slider slider = tester.widget<Slider>(
          find.descendant(
            of: find.byKey(
              const Key('android-tts-volume-slider'),
              skipOffstage: false,
            ),
            matching: find.byType(Slider),
          ),
        );
        slider.onChanged!(0.0);
        await tester.pumpAndSettle();

        expect(settingsStore.loadPreMuteAndroidTtsVolume(), 0.7);
      },
    );

    testWidgets(
      'Android TTS section shows mute indicator when pre-mute slot is set',
      (WidgetTester tester) async {
        // Issue #697 review #4: previously the "コメント画面でミュート中です"
        // badge only checked the VOICEVOX pre-mute slot, so Android-TTS-only
        // users had no on-screen indication of the mute state.
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('android-tts-mute-indicator'),
        );
        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Android TTS sliders not visible when VOICEVOX is selected', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('android-tts-speed-slider'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('android-tts-pitch-slider'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('android-tts-volume-slider'), skipOffstage: false),
        findsNothing,
      );
    });
  });

  group('mute indicator', () {
    testWidgets('shows volume_off icon and label when preMuteVolume is set', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.savePreMuteVolume(1.0);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('voicevox-volume-slider'),
      );

      expect(find.text('コメント画面でミュート中です', skipOffstage: false), findsOneWidget);

      final Finder volumeOffIcon = find.byIcon(
        Icons.volume_off,
        skipOffstage: false,
      );
      expect(volumeOffIcon, findsOneWidget);
    });

    testWidgets('does not show mute indicator when preMuteVolume is null', (
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

      expect(find.text('コメント画面でミュート中です', skipOffstage: false), findsNothing);
    });

    // Issue #714 (UX-3): the AppBar mute toggle introduced in PR #707
    // writes BOTH engines' pre-mute slots simultaneously. The previous
    // OR-gated indicator therefore rendered the same hint in both
    // sections at once. The hint must follow the active engine and
    // appear at most once on screen.
    testWidgets(
      'with both pre-mute slots set and VOICEVOX active, indicator appears '
      'only inside the VOICEVOX section (Issue #714)',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.voicevox),
        );
        // Both slots set, mirroring the AppBar mute contract.
        await settingsStore.savePreMuteVolume(1.0);
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Exactly one indicator on the screen, and it lives inside the
        // VOICEVOX section.
        expect(
          find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsNothing,
        );
        expect(
          find.text('コメント画面でミュート中です', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'with both pre-mute slots set and Android TTS active, indicator '
      'appears only inside the Android TTS section (Issue #714)',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        await settingsStore.savePreMuteVolume(1.0);
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.text('コメント画面でミュート中です', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('VOICEVOX active with only Android TTS pre-mute slot set hides '
        'the indicator (Issue #714)', (WidgetTester tester) async {
      // Even though AppBar mute would normally write both slots, this
      // covers the case where only the inactive engine's slot survives
      // (e.g. through a partial migration or a future code path) — the
      // active VOICEVOX section must NOT pretend to be muted.
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(speechEngine: SpeechEngine.voicevox),
      );
      await settingsStore.savePreMuteAndroidTtsVolume(0.7);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
        findsNothing,
      );
      expect(find.text('コメント画面でミュート中です', skipOffstage: false), findsNothing);
    });

    testWidgets('Android TTS active with only VOICEVOX pre-mute slot set hides '
        'the indicator (Issue #714 — symmetric)', (WidgetTester tester) async {
      // Symmetric case to the test above. Guards against asymmetric
      // gating that would silently leak the indicator only on the
      // VOICEVOX side.
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      await settingsStore.save(
        AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
      );
      await settingsStore.savePreMuteVolume(1.0);

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('android-tts-mute-indicator'),
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(find.text('コメント画面でミュート中です', skipOffstage: false), findsNothing);
    });

    testWidgets(
      'engine switch moves the mute indicator from VOICEVOX to Android TTS '
      'and back (Issue #714 — Acceptance Criterion #3)',
      (WidgetTester tester) async {
        // Issue #714 acceptance criterion #3: "エンジン切り替え時に表示
        // 位置が即座に追随する". This dynamic test guards against a
        // future regression where a stale-section condition would freeze
        // the indicator on the previous engine after switching.
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.voicevox),
        );
        // Both pre-mute slots set, mirroring the AppBar mute contract.
        await settingsStore.savePreMuteVolume(1.0);
        await settingsStore.savePreMuteAndroidTtsVolume(0.7);

        await tester.pumpWidget(_buildScreen(settingsStore));
        await tester.pumpAndSettle();

        // Initial: VOICEVOX side only.
        expect(
          find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsNothing,
        );

        // Switch to Android TTS via the SegmentedButton (programmatic
        // invocation, mirroring existing engine-switch tests in this
        // file).
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented1 = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented1.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
          findsNothing,
        );

        // And back to VOICEVOX — the indicator must follow.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented2 = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented2.onSelectionChanged!(<SpeechEngine>{SpeechEngine.voicevox});
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('voicevox-mute-indicator'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key('android-tts-mute-indicator'),
            skipOffstage: false,
          ),
          findsNothing,
        );
      },
    );
  });

  group('Android TTS availability warning', () {
    testWidgets(
      'shows warning card when Android TTS is unavailable on engine switch',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        // Switch to Android TTS.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pumpAndSettle();

        // Warning card should be visible.
        expect(
          find.byKey(const Key('android-tts-warning'), skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('日本語の音声データが利用できません', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('open-tts-settings-btn'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not show warning card when Android TTS is available', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();
      fakePlatform.androidTtsAvailableToReturn = true;

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, fakePlatform),
      );
      await tester.pumpAndSettle();

      // Switch to Android TTS.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('speech-engine-selector'),
      );
      final SegmentedButton<SpeechEngine> segmented = tester
          .widget<SegmentedButton<SpeechEngine>>(
            find.byKey(
              const Key('speech-engine-selector'),
              skipOffstage: false,
            ),
          );
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
      await tester.pumpAndSettle();

      // Warning card should NOT be visible.
      expect(
        find.byKey(const Key('android-tts-warning'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      'shows warning card when settings load with Android TTS engine and TTS unavailable',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        // Warning card should be visible because settings loaded with
        // Android TTS and the check returned false.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('android-tts-warning'),
        );
        expect(
          find.byKey(const Key('android-tts-warning'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    // -----------------------------------------------------------------
    // Issue #694 cycle-1 review additions: cross-screen notifier coverage.
    // -----------------------------------------------------------------
    testWidgets(
      'check publishes available to the notifier when platform returns true',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = true;
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreenWithPlatform(
            settingsStore,
            fakePlatform,
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.value,
          SpeechAvailability.available,
          reason:
              'Successful Android TTS availability check on the settings '
              'screen must publish to the cross-screen notifier so other '
              'screens see the same view (Issue #694).',
        );
      },
    );

    testWidgets(
      'check publishes unavailable to the notifier when platform returns false',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreenWithPlatform(
            settingsStore,
            fakePlatform,
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(notifier.value, SpeechAvailability.unavailable);
      },
    );

    testWidgets(
      'check publishes unavailable to the notifier when platform throws',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.checkAndroidTtsAvailabilityError = Exception(
          'simulated platform channel failure',
        );
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreenWithPlatform(
            settingsStore,
            fakePlatform,
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          notifier.value,
          SpeechAvailability.unavailable,
          reason:
              'A thrown availability check must be treated as unavailable '
              'for cross-screen consumers — same user-visible outcome '
              '(Issue #694).',
        );
      },
    );

    testWidgets(
      'switching engine to VOICEVOX resets the cross-screen notifier',
      (WidgetTester tester) async {
        // Without the reset, an `unavailable` value from the previous Android
        // TTS check would linger and make the comment-screen icon flicker
        // back to ERROR the moment the user switches back to Android TTS
        // (before the new check completes).
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreenWithPlatform(
            settingsStore,
            fakePlatform,
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();
        // Sanity: initial check pushed unavailable.
        expect(notifier.value, SpeechAvailability.unavailable);

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.voicevox});
        await tester.pumpAndSettle();

        expect(
          notifier.value,
          SpeechAvailability.unknown,
          reason:
              'Switching engine to VOICEVOX must reset the Android-TTS '
              'availability notifier so a stale unavailable value does not '
              'flicker the comment-screen icon when the user switches back '
              'later (Issue #694 review).',
        );
      },
    );

    testWidgets(
      'engine round-trip Android TTS → VOICEVOX → Android TTS re-publishes the result (cycle-3)',
      (WidgetTester tester) async {
        // Cycle-3 review #2 follow-up: confirm that after the reset on
        // engine switch, switching back triggers a fresh check that
        // re-publishes to the notifier. Without this round-trip test the
        // reset+republish contract had no end-to-end coverage.
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        await settingsStore.save(
          AppSettings.defaults.copyWith(speechEngine: SpeechEngine.androidTts),
        );
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;
        final SpeechAvailabilityNotifier notifier =
            SpeechAvailabilityNotifier();
        addTearDown(notifier.dispose);

        await tester.pumpWidget(
          _buildScreenWithPlatform(
            settingsStore,
            fakePlatform,
            androidTtsAvailability: notifier,
          ),
        );
        await tester.pumpAndSettle();
        // Initial check — Android TTS reports unavailable.
        expect(notifier.value, SpeechAvailability.unavailable);

        // Switch to VOICEVOX → reset to unknown.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.voicevox});
        await tester.pumpAndSettle();
        expect(notifier.value, SpeechAvailability.unknown);

        // Now Android-side recovers (e.g. user installed Japanese voice
        // data). Switch back — the screen runs a fresh check and the
        // notifier flips to available.
        fakePlatform.androidTtsAvailableToReturn = true;
        segmented = tester.widget<SegmentedButton<SpeechEngine>>(
          find.byKey(const Key('speech-engine-selector'), skipOffstage: false),
        );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pumpAndSettle();

        expect(
          notifier.value,
          SpeechAvailability.available,
          reason:
              'After reset + switch back, the new check must publish the '
              'fresh result to the cross-screen notifier '
              '(Issue #694 cycle-3 review).',
        );
      },
    );

    testWidgets('warning card disappears when switching back to VOICEVOX', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();
      fakePlatform.androidTtsAvailableToReturn = false;

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, fakePlatform),
      );
      await tester.pumpAndSettle();

      // Switch to Android TTS.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('speech-engine-selector'),
      );
      final SegmentedButton<SpeechEngine> segmented = tester
          .widget<SegmentedButton<SpeechEngine>>(
            find.byKey(
              const Key('speech-engine-selector'),
              skipOffstage: false,
            ),
          );
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
      await tester.pumpAndSettle();

      // Warning should be visible.
      expect(
        find.byKey(const Key('android-tts-warning'), skipOffstage: false),
        findsOneWidget,
      );

      // Switch back to VOICEVOX.
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.voicevox});
      await tester.pumpAndSettle();

      // Warning should be gone (Android TTS section is hidden).
      expect(
        find.byKey(const Key('android-tts-warning'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
      'open TTS settings button calls platform.openAndroidTtsSettings',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        // Switch to Android TTS.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pumpAndSettle();

        // Tap the open TTS settings button.
        final Finder btnFinder = find.byKey(
          const Key('open-tts-settings-btn'),
          skipOffstage: false,
        );
        await tester.ensureVisible(btnFinder);
        await tester.pumpAndSettle();
        await tester.tap(btnFinder);
        await tester.pumpAndSettle();

        expect(fakePlatform.openAndroidTtsSettingsCalled, isTrue);
      },
    );

    testWidgets(
      'shows checking indicator while Android TTS availability is pending',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        final Completer<void> gate = Completer<void>();
        fakePlatform.checkAndroidTtsAvailabilityGate = gate;
        fakePlatform.androidTtsAvailableToReturn = true;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        // Switch to Android TTS — availability check starts but is gated.
        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pump();

        // While the check is pending, the "確認中…" indicator is shown and
        // neither the warning card nor the ready description is visible.
        expect(
          find.byKey(const Key('android-tts-checking'), skipOffstage: false),
          findsOneWidget,
        );
        expect(find.text('音声データを確認中…', skipOffstage: false), findsOneWidget);
        expect(
          find.byKey(const Key('android-tts-warning'), skipOffstage: false),
          findsNothing,
        );

        // Resolve the gate — the indicator disappears and ready description
        // (available == true) replaces it.
        gate.complete();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('android-tts-checking'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(const Key('android-tts-warning'), skipOffstage: false),
          findsNothing,
        );
      },
    );

    testWidgets(
      'checking indicator is replaced by warning when availability resolves to false',
      (WidgetTester tester) async {
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
        final FakeCommentSpeechPlatform fakePlatform =
            FakeCommentSpeechPlatform();
        final Completer<void> gate = Completer<void>();
        fakePlatform.checkAndroidTtsAvailabilityGate = gate;
        fakePlatform.androidTtsAvailableToReturn = false;

        await tester.pumpWidget(
          _buildScreenWithPlatform(settingsStore, fakePlatform),
        );
        await tester.pumpAndSettle();

        await scrollToKeyInList(
          tester,
          _listKey,
          const Key('speech-engine-selector'),
        );
        final SegmentedButton<SpeechEngine> segmented = tester
            .widget<SegmentedButton<SpeechEngine>>(
              find.byKey(
                const Key('speech-engine-selector'),
                skipOffstage: false,
              ),
            );
        segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
        await tester.pump();

        expect(
          find.byKey(const Key('android-tts-checking'), skipOffstage: false),
          findsOneWidget,
        );

        gate.complete();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('android-tts-checking'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(const Key('android-tts-warning'), skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('shows warning when checkAndroidTtsAvailability throws', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();
      fakePlatform.checkAndroidTtsAvailabilityError = Exception(
        'platform error',
      );

      await tester.pumpWidget(
        _buildScreenWithPlatform(settingsStore, fakePlatform),
      );
      await tester.pumpAndSettle();

      // Switch to Android TTS.
      await scrollToKeyInList(
        tester,
        _listKey,
        const Key('speech-engine-selector'),
      );
      final SegmentedButton<SpeechEngine> segmented = tester
          .widget<SegmentedButton<SpeechEngine>>(
            find.byKey(
              const Key('speech-engine-selector'),
              skipOffstage: false,
            ),
          );
      segmented.onSelectionChanged!(<SpeechEngine>{SpeechEngine.androidTts});
      await tester.pumpAndSettle();

      // Warning should show (error treated as unavailable).
      expect(
        find.byKey(const Key('android-tts-warning'), skipOffstage: false),
        findsOneWidget,
      );
    });
  });
}

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(home: TtsSettingsScreen(settingsStore: settingsStore));
}

Widget _buildScreenWithPlatform(
  SettingsStore settingsStore,
  CommentSpeechPlatform platform, {
  SpeechAvailabilityNotifier? androidTtsAvailability,
}) {
  return MaterialApp(
    home: TtsSettingsScreen(
      settingsStore: settingsStore,
      platform: platform,
      androidTtsAvailability: androidTtsAvailability,
    ),
  );
}
