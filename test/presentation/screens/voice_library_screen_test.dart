import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/voice_library_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';

final _bundledModel = <String, dynamic>{
  'modelId': '0',
  'displayName': '四国めたん',
  'speakerIds': [0, 1, 2, 3],
  'vvmFileName': '0.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': true,
  'downloadState': 'DOWNLOADED',
};

final _notDownloadedModel = <String, dynamic>{
  'modelId': '1',
  'displayName': 'ずんだもん',
  'speakerIds': [4, 5, 6, 7],
  'vvmFileName': '1.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': false,
  'downloadState': 'NOT_DOWNLOADED',
};

final _downloadedModel = <String, dynamic>{
  'modelId': '2',
  'displayName': '春日部つむぎ',
  'speakerIds': [8],
  'vvmFileName': '2.vvm',
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

  testWidgets('shows bundled badge for bundled model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.text('内蔵'), findsOneWidget);
  });

  testWidgets('shows download button for not-downloaded model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('download-btn-1')), findsOneWidget);
  });

  testWidgets('shows delete button for downloaded non-bundled model', (
    tester,
  ) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-btn-2')), findsOneWidget);
  });

  testWidgets('does not show delete button for bundled model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-btn-0')), findsNothing);
  });

  testWidgets('shows delete confirmation dialog', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-btn-2')));
    await tester.pumpAndSettle();

    expect(find.text('春日部つむぎ を削除しますか？'), findsOneWidget);
  });

  testWidgets('shows progress bar during download', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    // Emit download started event for model 1
    fakePlatform.emitEvent(
      const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '1'},
      ),
    );
    await tester.pump();

    // Emit download progress event: 50%
    fakePlatform.emitEvent(
      const SpeechEvent(
        type: SpeechEventType.modelDownloadProgress,
        payload: {
          'modelId': '1',
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

    await tester.tap(find.byKey(const Key('download-btn-1')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isTrue);
    expect(fakePlatform.loadedModelIds, contains('1'));
  });

  testWidgets('download skips initialize when engine is READY', (tester) async {
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

    await tester.tap(find.byKey(const Key('download-btn-1')));
    await _agreeVoicevoxTermsDialog(tester);

    expect(fakePlatform.initializeCalled, isFalse);
    expect(fakePlatform.loadedModelIds, contains('1'));
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

    await tester.tap(find.byKey(const Key('download-btn-1')));
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
      await tester.tap(find.byKey(const Key('download-btn-1')));
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

      await tester.tap(find.byKey(const Key('download-btn-1')));
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

      await tester.tap(find.byKey(const Key('download-btn-1')));
      await tester.pump();
      await tester.pump();

      // Dialog should appear on every download.
      expect(find.text('VOICEVOX 利用規約'), findsOneWidget);
    });
  });
}
