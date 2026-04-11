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
  'modelId': '0',
  'displayName': '春日部つむぎ',
  'speakerIds': [0, 1, 2, 3, 4, 5, 6, 7, 8, 10],
  'vvmFileName': '0.vvm',
  'fileSizeBytes': 58214379,
  'isBundled': false,
  'downloadState': 'NOT_DOWNLOADED',
};

final _downloadedModel = <String, dynamic>{
  'modelId': '3',
  'displayName': '波音リツ',
  'speakerIds': [9, 65],
  'vvmFileName': '3.vvm',
  'fileSizeBytes': 61730024,
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
      settingsStore:
          settingsStore ??
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

    expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
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
        payload: {'modelId': '0'},
      ),
    );
    await tester.pump();

    // Emit download progress event: 50%
    fakePlatform.emitEvent(
      const SpeechEvent(
        type: SpeechEventType.modelDownloadProgress,
        payload: {
          'modelId': '0',
          'bytesDownloaded': 29107189,
          'totalBytes': 58214379,
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

    await tester.tap(find.byKey(const Key('download-btn-0')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isTrue);
    expect(fakePlatform.loadedModelIds, contains('0'));
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

    await tester.tap(find.byKey(const Key('download-btn-0')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isFalse);
    expect(fakePlatform.loadedModelIds, contains('0'));
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

    await tester.tap(find.byKey(const Key('download-btn-0')));
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
      await tester.tap(find.byKey(const Key('download-btn-0')));
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

      await tester.tap(find.byKey(const Key('download-btn-0')));
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

      await tester.tap(find.byKey(const Key('download-btn-0')));
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

  group('download cancel', () {
    testWidgets('shows cancel button during download', (tester) async {
      fakePlatform.availableModelsToReturn = [_notDownloadedModel];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Initially, download button is shown.
      expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
      expect(find.byKey(const Key('cancel-btn-0')), findsNothing);

      // Simulate download started.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Cancel button should now be visible, download button should be gone.
      expect(find.byKey(const Key('cancel-btn-0')), findsOneWidget);
      expect(find.byKey(const Key('download-btn-0')), findsNothing);
    });

    testWidgets('tapping cancel button calls cancelDownload on platform', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [_notDownloadedModel];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start download.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Tap cancel button.
      await tester.tap(find.byKey(const Key('cancel-btn-0')));
      await tester.pump();

      expect(fakePlatform.cancelledModelIds, contains('0'));
    });

    testWidgets(
      'UI resets after cancel: download button restored, progress bar removed',
      (tester) async {
        fakePlatform.availableModelsToReturn = [_notDownloadedModel];
        await tester.pumpWidget(_buildScreen(fakePlatform));
        await tester.pumpAndSettle();

        // Start download and show progress.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDownloadStarted,
            payload: {'modelId': '0'},
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDownloadProgress,
            payload: {
              'modelId': '0',
              'bytesDownloaded': 29107189,
              'totalBytes': 58214379,
            },
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        // Verify downloading state is visible.
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
        expect(find.byKey(const Key('cancel-btn-0')), findsOneWidget);

        // Simulate cancel: platform emits modelDownloadFailed (or resets to
        // notDownloaded). The native platform resets the model state via a
        // modelDeleted event when cancel succeeds.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDeleted,
            payload: {'modelId': '0'},
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        // After cancel, download button should reappear.
        expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
        expect(find.byKey(const Key('cancel-btn-0')), findsNothing);
        // Progress bar and percentage should be gone.
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('50%'), findsNothing);
      },
    );

    testWidgets('shows snackbar when cancel fails', (tester) async {
      fakePlatform.availableModelsToReturn = [_notDownloadedModel];
      fakePlatform.cancelDownloadError = Exception('cancel failed');
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start download.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Tap cancel button (will throw).
      await tester.tap(find.byKey(const Key('cancel-btn-0')));
      await tester.pump();

      expect(find.textContaining('キャンセルに失敗しました'), findsOneWidget);
    });
  });

  group('download error', () {
    testWidgets(
      'shows error text and error badge when modelDownloadFailed is received',
      (tester) async {
        fakePlatform.availableModelsToReturn = [_notDownloadedModel];
        await tester.pumpWidget(_buildScreen(fakePlatform));
        await tester.pumpAndSettle();

        // Start download.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDownloadStarted,
            payload: {'modelId': '0'},
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        // Add some progress.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDownloadProgress,
            payload: {
              'modelId': '0',
              'bytesDownloaded': 10000000,
              'totalBytes': 58214379,
            },
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        // Simulate download failure.
        fakePlatform.emitEvent(
          const SpeechEvent(
            type: SpeechEventType.modelDownloadFailed,
            payload: {'modelId': '0'},
          ),
        );
        await tester.pump(); // deliver stream event
        await tester.pump(); // rebuild widget tree

        // Error text should appear.
        expect(find.text('ダウンロードに失敗しました'), findsOneWidget);
        // Error badge should appear.
        expect(find.text('エラー'), findsOneWidget);
        // Progress bar should be gone.
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets('shows download button for retry after download failure', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [_notDownloadedModel];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start and fail download.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadFailed,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Download button should reappear for retry (error state shows download
      // button per _buildAction).
      expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
      // Cancel button should not be present.
      expect(find.byKey(const Key('cancel-btn-0')), findsNothing);
    });

    testWidgets('cancel button disappears when download fails mid-progress', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [_notDownloadedModel];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start download.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Verify cancel button is present during download.
      expect(find.byKey(const Key('cancel-btn-0')), findsOneWidget);

      // Download fails.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadFailed,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Cancel button should be gone, download (retry) button should appear.
      expect(find.byKey(const Key('cancel-btn-0')), findsNothing);
      expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
    });
  });

  group('multiple concurrent downloads', () {
    /// A second not-downloaded model (modelId '3' set to NOT_DOWNLOADED).
    final notDownloadedModel3 = <String, dynamic>{
      'modelId': '3',
      'displayName': '波音リツ',
      'speakerIds': [9, 65],
      'vvmFileName': '3.vvm',
      'fileSizeBytes': 61730024,
      'isBundled': false,
      'downloadState': 'NOT_DOWNLOADED',
    };

    testWidgets('shows progress for two models downloading simultaneously', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [
        _notDownloadedModel,
        notDownloadedModel3,
      ];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start download for both models.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '3'},
        ),
      );
      await tester.pump(); // deliver stream events
      await tester.pump(); // rebuild widget tree

      // Emit progress for both.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadProgress,
          payload: {
            'modelId': '0',
            'bytesDownloaded': 29107189,
            'totalBytes': 58214379,
          },
        ),
      );
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadProgress,
          payload: {
            'modelId': '3',
            'bytesDownloaded': 18519007,
            'totalBytes': 61730024,
          },
        ),
      );
      await tester.pump(); // deliver stream events
      await tester.pump(); // rebuild widget tree

      // Both should show progress bars.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      // Both should show cancel buttons.
      expect(find.byKey(const Key('cancel-btn-0')), findsOneWidget);
      expect(find.byKey(const Key('cancel-btn-3')), findsOneWidget);
      // Both should show downloading badge.
      expect(find.text('ダウンロード中'), findsNWidgets(2));
      // Progress percentages.
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
    });

    testWidgets('one model completes while another continues downloading', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [
        _notDownloadedModel,
        notDownloadedModel3,
      ];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start both downloads.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '3'},
        ),
      );
      await tester.pump(); // deliver stream events
      await tester.pump(); // rebuild widget tree

      // Complete model '0'.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadCompleted,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Model '0' should show downloaded state (delete button, badge).
      expect(find.byKey(const Key('delete-btn-0')), findsOneWidget);
      expect(find.byKey(const Key('cancel-btn-0')), findsNothing);
      // Model '3' should still be downloading.
      expect(find.byKey(const Key('cancel-btn-3')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('one model fails while another continues downloading', (
      tester,
    ) async {
      fakePlatform.availableModelsToReturn = [
        _notDownloadedModel,
        notDownloadedModel3,
      ];
      await tester.pumpWidget(_buildScreen(fakePlatform));
      await tester.pumpAndSettle();

      // Start both downloads.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '0'},
        ),
      );
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadStarted,
          payload: {'modelId': '3'},
        ),
      );
      await tester.pump(); // deliver stream events
      await tester.pump(); // rebuild widget tree

      // Add progress for model '3'.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadProgress,
          payload: {
            'modelId': '3',
            'bytesDownloaded': 30865012,
            'totalBytes': 61730024,
          },
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Fail model '0'.
      fakePlatform.emitEvent(
        const SpeechEvent(
          type: SpeechEventType.modelDownloadFailed,
          payload: {'modelId': '0'},
        ),
      );
      await tester.pump(); // deliver stream event
      await tester.pump(); // rebuild widget tree

      // Model '0' should show error state.
      expect(find.text('エラー'), findsOneWidget);
      expect(find.byKey(const Key('download-btn-0')), findsOneWidget);
      // Model '3' should still be downloading.
      expect(find.byKey(const Key('cancel-btn-3')), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });
}
