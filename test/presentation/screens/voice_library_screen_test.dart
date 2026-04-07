import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/voice_library_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';

final _bundledModel = <String, dynamic>{
  'modelId': 'n0',
  'displayName': 'VOICEVOX Nemo',
  'speakerIds': [10000, 10001, 10002],
  'vvmFileName': 'n0.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': true,
  'downloadState': 'DOWNLOADED',
};

final _notDownloadedModel = <String, dynamic>{
  'modelId': '2',
  'displayName': '春日部つむぎ',
  'speakerIds': [4, 5, 6, 7],
  'vvmFileName': '2.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': false,
  'downloadState': 'NOT_DOWNLOADED',
};

final _downloadedModel = <String, dynamic>{
  'modelId': '3',
  'displayName': '波音リツ',
  'speakerIds': [8],
  'vvmFileName': '3.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': false,
  'downloadState': 'DOWNLOADED',
};

Widget _buildScreen(
  FakeCommentSpeechPlatform platform, {
  SettingsStore? settingsStore,
}) {
  return MaterialApp(
    home: VoiceLibraryScreen(
      platform: platform,
      settingsStore: settingsStore ??
          SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences()),
    ),
  );
}

Future<void> _agreeVoicevoxTermsDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();

  final dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);
  final context = tester.element(dialog);
  Navigator.of(context).pop(true);
  await tester.pumpAndSettle();
}

void main() {
  late FakeCommentSpeechPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeCommentSpeechPlatform();
    fakePlatform.availableModelsToReturn = [
      _bundledModel,
      _notDownloadedModel,
      _downloadedModel,
    ];
  });

  tearDown(() {
    fakePlatform.dispose();
  });

  testWidgets('shows model cards after loading', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-model-card-0')), findsOneWidget);
    expect(find.byKey(const Key('voice-model-card-1')), findsOneWidget);
    expect(find.byKey(const Key('voice-model-card-2')), findsOneWidget);
  });

  testWidgets('filters out unsupported models', (tester) async {
    final unsupportedModel = <String, dynamic>{
      'modelId': '99',
      'displayName': 'Unsupported Model',
      'speakerIds': [9999],
      'vvmFileName': '99.vvm',
      'fileSizeBytes': 10000000,
      'isBundled': false,
      'downloadState': 'NOT_DOWNLOADED',
    };
    fakePlatform.availableModelsToReturn = [
      _bundledModel,
      _notDownloadedModel,
      unsupportedModel,
    ];

    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    // Supported models are shown.
    expect(find.text('VOICEVOX Nemo'), findsOneWidget);
    expect(find.text('春日部つむぎ'), findsOneWidget);
    // Unsupported model is filtered out.
    expect(find.text('Unsupported Model'), findsNothing);
    // Only 2 cards (not 3).
    expect(find.byKey(const Key('voice-model-card-0')), findsOneWidget);
    expect(find.byKey(const Key('voice-model-card-1')), findsOneWidget);
    expect(find.byKey(const Key('voice-model-card-2')), findsNothing);
  });

  testWidgets('shows bundled badge for bundled model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.text('内蔵'), findsOneWidget);
  });

  testWidgets('shows download button for not-downloaded model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('download-btn-2')), findsOneWidget);
  });

  testWidgets('shows delete button for downloaded non-bundled model', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-btn-3')), findsOneWidget);
  });

  testWidgets('does not show delete button for bundled model', (tester) async {
    // Use only a bundled model to verify no delete button appears.
    fakePlatform.availableModelsToReturn = [_bundledModel];
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-btn-3')), findsNothing);
  });

  testWidgets('shows delete confirmation dialog', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-btn-3')));
    await tester.pumpAndSettle();

    expect(find.text('波音リツ を削除しますか？'), findsOneWidget);
  });

  testWidgets('shows progress bar during download', (tester) async {
    // Use only the not-downloaded model to avoid ambiguous state updates.
    fakePlatform.availableModelsToReturn = [_notDownloadedModel];
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    // Emit download started event
    fakePlatform.emitEvent(
      const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '2'},
      ),
    );
    await tester.pump();

    // Emit download progress event: 50%
    fakePlatform.emitEvent(
      const SpeechEvent(
        type: SpeechEventType.modelDownloadProgress,
        payload: {
          'modelId': '2',
          'bytesDownloaded': 26000000,
          'totalBytes': 52000000,
        },
      ),
    );
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('download initializes engine before loading model', (
    tester,
  ) async {
    // Use only the not-downloaded model to avoid ambiguous state updates.
    fakePlatform.availableModelsToReturn = [_notDownloadedModel];
    final prefs = InMemorySharedPreferences();
    final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);
    await settingsStore.save(
      AppSettings.defaults.copyWith(voicevoxTermsAccepted: true),
    );
    fakePlatform.statusToReturn = const SpeechRuntimeStatus(
      enabled: false,
      engineState: 'UNINITIALIZED',
      playerState: 'UNKNOWN',
      queueSize: 0,
      currentSpeakerId: 0,
    );

    await tester.pumpWidget(
      _buildScreen(fakePlatform, settingsStore: settingsStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('download-btn-2')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isTrue);
    expect(fakePlatform.loadedModelIds, contains('2'));
  });

  testWidgets('download skips initialize when engine is READY', (tester) async {
    // Use only the not-downloaded model to avoid ambiguous state updates.
    fakePlatform.availableModelsToReturn = [_notDownloadedModel];
    final prefs = InMemorySharedPreferences();
    final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);
    await settingsStore.save(
      AppSettings.defaults.copyWith(voicevoxTermsAccepted: true),
    );
    fakePlatform.statusToReturn = const SpeechRuntimeStatus(
      enabled: true,
      engineState: 'READY',
      playerState: 'IDLE',
      queueSize: 0,
      currentSpeakerId: 0,
    );

    await tester.pumpWidget(
      _buildScreen(fakePlatform, settingsStore: settingsStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('download-btn-2')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isFalse);
    expect(fakePlatform.loadedModelIds, contains('2'));
  });

  testWidgets('shows model-load error message when load fails', (tester) async {
    final prefs = InMemorySharedPreferences();
    final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);
    await settingsStore.save(
      AppSettings.defaults.copyWith(voicevoxTermsAccepted: true),
    );
    fakePlatform.statusToReturn = const SpeechRuntimeStatus(
      enabled: true,
      engineState: 'READY',
      playerState: 'IDLE',
      queueSize: 0,
      currentSpeakerId: 0,
    );
    fakePlatform.loadModelError = Exception('load failed');

    await tester.pumpWidget(
      _buildScreen(fakePlatform, settingsStore: settingsStore),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('download-btn-2')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(find.textContaining('モデルの読み込みに失敗しました'), findsOneWidget);
  });

  group('VOICEVOX terms dialog', () {
    testWidgets('shows terms dialog when terms not accepted', (tester) async {
      final prefs = InMemorySharedPreferences();
      final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(
        _buildScreen(fakePlatform, settingsStore: settingsStore),
      );
      await tester.pumpAndSettle();

      // Tap download button for not-downloaded model.
      await tester.tap(find.byKey(const Key('download-btn-2')));
      // Pump once to allow settingsStore.load() and showDialog to execute,
      // but don't settle (asset loading and cooldown timer are pending).
      await tester.pump();
      await tester.pump();

      // Terms dialog should appear (content may still be loading).
      expect(find.text('VOICEVOX 利用規約'), findsOneWidget);
      expect(find.text('以下の利用規約をご確認ください'), findsOneWidget);
      // Agree button should exist but be disabled initially.
      expect(find.text('同意する'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
    });

    testWidgets('cancel button closes dialog without download', (tester) async {
      final prefs = InMemorySharedPreferences();
      final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(
        _buildScreen(fakePlatform, settingsStore: settingsStore),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('download-btn-2')));
      await tester.pump();
      await tester.pump();

      // Dialog should be visible.
      expect(find.text('VOICEVOX 利用規約'), findsOneWidget);

      // Tap cancel.
      await tester.tap(find.text('キャンセル'));
      await tester.pump();
      await tester.pump();

      // Dialog should be closed, terms should remain not accepted.
      expect(find.text('VOICEVOX 利用規約'), findsNothing);
      final loaded = await settingsStore.load();
      expect(loaded.voicevoxTermsAccepted, isFalse);
    });

    testWidgets('shows dialog even when terms already accepted', (
      tester,
    ) async {
      final prefs = InMemorySharedPreferences();
      final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);
      // Pre-accept terms.
      await settingsStore.save(
        AppSettings.defaults.copyWith(voicevoxTermsAccepted: true),
      );

      await tester.pumpWidget(
        _buildScreen(fakePlatform, settingsStore: settingsStore),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('download-btn-2')));
      await tester.pump();
      await tester.pump();

      // Dialog should appear on every download.
      expect(find.text('VOICEVOX 利用規約'), findsOneWidget);
    });
  });

  group('filterTermsForSupportedSpeakers', () {
    const String fullTerms = '''# VOICEVOX 音声モデル 利用規約

## 許諾内容
利用可能です

## 禁止事項
禁止事項です

# 音声ライブラリ利用規約

## 四国めたん
四国めたんの規約です

## 春日部つむぎ
春日部つむぎの規約です

## 波音リツ
波音リツの規約です

## 玄野武宏
玄野武宏の規約です

## VOICEVOX Nemo
Nemoの規約です''';

    const Set<String> supported = {'春日部つむぎ', '波音リツ', 'VOICEVOX Nemo'};

    test('keeps common header sections', () {
      final result = filterTermsForSupportedSpeakers(fullTerms, supported);
      expect(result, contains('# VOICEVOX 音声モデル 利用規約'));
      expect(result, contains('## 許諾内容'));
      expect(result, contains('## 禁止事項'));
      expect(result, contains('# 音声ライブラリ利用規約'));
    });

    test('keeps supported speaker sections', () {
      final result = filterTermsForSupportedSpeakers(fullTerms, supported);
      expect(result, contains('## 春日部つむぎ'));
      expect(result, contains('春日部つむぎの規約です'));
      expect(result, contains('## 波音リツ'));
      expect(result, contains('波音リツの規約です'));
      expect(result, contains('## VOICEVOX Nemo'));
      expect(result, contains('Nemoの規約です'));
    });

    test('removes unsupported speaker sections', () {
      final result = filterTermsForSupportedSpeakers(fullTerms, supported);
      expect(result, isNot(contains('## 四国めたん')));
      expect(result, isNot(contains('四国めたんの規約です')));
      expect(result, isNot(contains('## 玄野武宏')));
      expect(result, isNot(contains('玄野武宏の規約です')));
    });

    test('handles empty supported set', () {
      final result = filterTermsForSupportedSpeakers(
        fullTerms,
        const <String>{},
      );
      expect(result, contains('# VOICEVOX 音声モデル 利用規約'));
      expect(result, isNot(contains('## 春日部つむぎ')));
      expect(result, isNot(contains('## VOICEVOX Nemo')));
    });

    test('handles text without speaker sections', () {
      const headerOnly = '# VOICEVOX 音声モデル 利用規約\n\n許諾内容';
      final result = filterTermsForSupportedSpeakers(headerOnly, supported);
      expect(result, contains('# VOICEVOX 音声モデル 利用規約'));
      expect(result, contains('許諾内容'));
    });
  });
}
