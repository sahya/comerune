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

    testWidgets('shows validation error and does not save invalid queue limit',
        (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), 'abc');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      expect(find.text('数値を入力してください', skipOffstage: false), findsOneWidget);
      AppSettings loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), '0');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false), findsOneWidget);
      loaded = await settingsStore.load();
      expect(loaded.queueLimit, AppSettings.defaults.queueLimit);

      await enterTextByKey(
          tester, _listKey, const Key('queue-limit-field'), '35');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      loaded = await settingsStore.load();
      expect(loaded.queueLimit, 35);
      expect(
          find.text('1〜100 の範囲で入力してください', skipOffstage: false), findsNothing);
    });

    testWidgets('shows validation error and does not save invalid max delay', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await enterTextByKey(
          tester, _listKey, const Key('max-delay-field'), 'abc');
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
          tester, _listKey, const Key('queue-limit-field'), '50');
      await focusFieldByKey(tester, _listKey, const Key('max-delay-field'));

      await enterTextByKey(
          tester, _listKey, const Key('ng-words-field'), '^w+\$');
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
          tester, _listKey, const Key('ng-words-field'), '^8+\$');
      await focusFieldByKey(tester, _listKey, const Key('queue-limit-field'));

      // Re-open the screen to verify values are reloaded from store
      await tester.pumpWidget(_buildScreen(settingsStore));
      await tester.pumpAndSettle();

      await scrollToKeyInList(tester, _listKey, const Key('ng-words-field'));
      final TextFormField ngWordsField = tester
          .widget(find.byKey(const Key('ng-words-field'), skipOffstage: false));
      expect(ngWordsField.controller?.text, '^8+\$');
    });

    testWidgets('auto-read toggle persists value', (
      WidgetTester tester,
    ) async {
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
          tester, _listKey, const Key('slash-prefix-skip-switch'));

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
          tester, _listKey, const Key('star-prefix-hiding-switch'));

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
          tester, _listKey, const Key('read-user-name-switch'));

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
          tester, _listKey, const Key('voicevox-speed-slider'));

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
          tester, _listKey, const Key('voicevox-pitch-slider'));

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
          tester, _listKey, const Key('voicevox-intonation-slider'));

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
          tester, _listKey, const Key('voicevox-volume-slider'));

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

    testWidgets(
        'slider change pushes updated SpeechSettings to platform engine', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();

      await tester
          .pumpWidget(_buildScreenWithPlatform(settingsStore, fakePlatform));
      await tester.pumpAndSettle();

      // Initially no updateSettings call has been made (beyond _loadSettings).
      fakePlatform.lastUpdatedSettings = null;

      // Change speed slider
      await scrollToKeyInList(
          tester, _listKey, const Key('voicevox-speed-slider'));
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
          tester, _listKey, const Key('voicevox-pitch-slider'));
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
    });

    testWidgets(
        'auto-read toggle pushes updated SpeechSettings to platform engine', (
      WidgetTester tester,
    ) async {
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final FakeCommentSpeechPlatform fakePlatform =
          FakeCommentSpeechPlatform();

      await tester
          .pumpWidget(_buildScreenWithPlatform(settingsStore, fakePlatform));
      await tester.pumpAndSettle();

      fakePlatform.lastUpdatedSettings = null;

      await toggleSwitchByKey(tester, _listKey, const Key('auto-read-switch'));

      expect(fakePlatform.lastUpdatedSettings, isNotNull);
      expect(fakePlatform.lastUpdatedSettings!.enabled, isTrue);
    });

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
          tester, _listKey, const Key('voicevox-speed-slider'));
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

    testWidgets(
        'speaker change awaits loadModel and pushes settings after completion',
        (WidgetTester tester) async {
      final settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final fakePlatform = FakeCommentSpeechPlatform();
      final loadCompleter = Completer<void>();
      fakePlatform.loadModelCompleter = loadCompleter;
      fakePlatform.availableModelsToReturn = _twoModelsList;

      await tester
          .pumpWidget(_buildScreenWithPlatform(settingsStore, fakePlatform));
      await tester.pumpAndSettle();

      fakePlatform.lastUpdatedSettings = null;

      // Select speaker 2 from dropdown
      await scrollToKeyInList(
          tester, _listKey, const Key('voicevox-speaker-dropdown'));
      await tester.tap(find.byKey(const Key('voicevox-speaker-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('モデルB (ID:2)').last);
      await tester.pump();

      // Loading indicator should be visible
      expect(
        find.byKey(const Key('speaker-loading-indicator'), skipOffstage: false),
        findsOneWidget,
      );
      // Settings should NOT have been pushed yet (model still loading)
      expect(fakePlatform.lastUpdatedSettings, isNull);

      // Complete the model load
      loadCompleter.complete();
      await tester.pumpAndSettle();

      // Now settings should be pushed with the new speaker
      expect(fakePlatform.lastUpdatedSettings, isNotNull);
      expect(fakePlatform.lastUpdatedSettings!.speakerId, 2);

      // Loading indicator should be gone
      expect(
        find.byKey(const Key('speaker-loading-indicator'), skipOffstage: false),
        findsNothing,
      );
    });

    testWidgets(
        'speaker change reverts to previous speaker on loadModel failure',
        (WidgetTester tester) async {
      final settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final fakePlatform = FakeCommentSpeechPlatform();
      fakePlatform.loadModelError = Exception('load failed');
      fakePlatform.availableModelsToReturn = _twoModelsList;

      await tester
          .pumpWidget(_buildScreenWithPlatform(settingsStore, fakePlatform));
      await tester.pumpAndSettle();

      fakePlatform.lastUpdatedSettings = null;

      // Select speaker 2 from dropdown
      await scrollToKeyInList(
          tester, _listKey, const Key('voicevox-speaker-dropdown'));
      await tester.tap(find.byKey(const Key('voicevox-speaker-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('モデルB (ID:2)').last);
      await tester.pumpAndSettle();

      // Settings should NOT have been pushed (model load failed)
      expect(fakePlatform.lastUpdatedSettings, isNull);

      // Should show snackbar error
      expect(find.text('話者の読み込みに失敗しました'), findsOneWidget);

      // Speaker should be reverted to original (0)
      final loaded = await settingsStore.load();
      expect(loaded.voicevoxSpeaker, 0);
    });

    testWidgets(
        'rapid speaker changes only apply the last selection (race condition)',
        (WidgetTester tester) async {
      final settingsStore =
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());
      final fakePlatform = FakeCommentSpeechPlatform();
      final firstCompleter = Completer<void>();
      fakePlatform.loadModelCompleter = firstCompleter;
      fakePlatform.availableModelsToReturn = _threeModelsList;

      await tester
          .pumpWidget(_buildScreenWithPlatform(settingsStore, fakePlatform));
      await tester.pumpAndSettle();

      fakePlatform.lastUpdatedSettings = null;

      // Select speaker 2
      await scrollToKeyInList(
          tester, _listKey, const Key('voicevox-speaker-dropdown'));
      await tester.tap(find.byKey(const Key('voicevox-speaker-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('モデルB (ID:2)').last);
      await tester.pump();

      // While first load is in progress, select speaker 3
      final secondCompleter = Completer<void>();
      fakePlatform.loadModelCompleter = secondCompleter;

      await tester.tap(find.byKey(const Key('voicevox-speaker-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('モデルC (ID:3)').last);
      await tester.pump();

      // Complete first load (should be discarded as stale)
      firstCompleter.complete();
      await tester.pump();

      // Settings should NOT have been pushed from stale first load
      expect(fakePlatform.lastUpdatedSettings, isNull);

      // Complete second load
      secondCompleter.complete();
      await tester.pumpAndSettle();

      // Settings should be pushed with speaker 3 (the latest selection)
      expect(fakePlatform.lastUpdatedSettings, isNotNull);
      expect(fakePlatform.lastUpdatedSettings!.speakerId, 3);
    });
  });
}

/// Two-model fixture for speaker-change tests.
final List<Map<String, dynamic>> _twoModelsList = [
  {
    'modelId': 'model-a',
    'displayName': 'モデルA',
    'speakerIds': [0],
    'vvmFileName': 'a.vvm',
    'fileSizeBytes': 1000,
    'isBundled': true,
    'downloadState': 'DOWNLOADED',
  },
  {
    'modelId': 'model-b',
    'displayName': 'モデルB',
    'speakerIds': [2],
    'vvmFileName': 'b.vvm',
    'fileSizeBytes': 1000,
    'isBundled': false,
    'downloadState': 'DOWNLOADED',
  },
];

/// Three-model fixture for race-condition tests.
final List<Map<String, dynamic>> _threeModelsList = [
  ..._twoModelsList,
  {
    'modelId': 'model-c',
    'displayName': 'モデルC',
    'speakerIds': [3],
    'vvmFileName': 'c.vvm',
    'fileSizeBytes': 1000,
    'isBundled': false,
    'downloadState': 'DOWNLOADED',
  },
];

Widget _buildScreen(SettingsStore settingsStore) {
  return MaterialApp(
    home: TtsSettingsScreen(
      settingsStore: settingsStore,
    ),
  );
}

Widget _buildScreenWithPlatform(
  SettingsStore settingsStore,
  CommentSpeechPlatform platform,
) {
  return MaterialApp(
    home: TtsSettingsScreen(
      settingsStore: settingsStore,
      platform: platform,
    ),
  );
}
