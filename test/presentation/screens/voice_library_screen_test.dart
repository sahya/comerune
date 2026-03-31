import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/presentation/screens/voice_library_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';
import '../../helpers/in_memory_shared_preferences.dart';

final _nemoModel = <String, dynamic>{
  'modelId': 'n0',
  'displayName': 'VOICEVOX Nemo',
  'speakerIds': [10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10008],
  'vvmFileName': 'n0.vvm',
  'fileSizeBytes': 52000000,
  'isBundled': false,
  'downloadState': 'NOT_DOWNLOADED',
};

final _nemoDownloadedModel = <String, dynamic>{
  'modelId': 'n0',
  'displayName': 'VOICEVOX Nemo',
  'speakerIds': [10000, 10001, 10002, 10003, 10004, 10005, 10006, 10007, 10008],
  'vvmFileName': 'n0.vvm',
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

void main() {
  late FakeCommentSpeechPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeCommentSpeechPlatform();
    fakePlatform.availableModelsToReturn = [
      _nemoModel,
    ];
  });

  tearDown(() {
    fakePlatform.dispose();
  });

  testWidgets('shows model cards after loading', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-model-card-n0')), findsOneWidget);
  });

  testWidgets('shows download button for not-downloaded model', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('download-btn-n0')), findsOneWidget);
  });

  testWidgets('shows delete button for downloaded model', (tester) async {
    fakePlatform.availableModelsToReturn = [_nemoDownloadedModel];
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-btn-n0')), findsOneWidget);
  });

  testWidgets('shows delete confirmation dialog', (tester) async {
    fakePlatform.availableModelsToReturn = [_nemoDownloadedModel];
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-btn-n0')));
    await tester.pumpAndSettle();

    expect(find.text('VOICEVOX Nemo を削除しますか？'), findsOneWidget);
  });

  testWidgets('does not show download button for downloaded model',
      (tester) async {
    fakePlatform.availableModelsToReturn = [_nemoDownloadedModel];
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('download-btn-n0')), findsNothing);
  });

  testWidgets('shows model name in card', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    expect(find.text('VOICEVOX Nemo'), findsOneWidget);
  });

  testWidgets('shows progress bar during download', (tester) async {
    await tester.pumpWidget(_buildScreen(fakePlatform));
    await tester.pumpAndSettle();

    // Emit download started event for Nemo model
    fakePlatform.emitEvent(const SpeechEvent(
      type: SpeechEventType.modelDownloadStarted,
      payload: {'modelId': 'n0'},
    ));
    await tester.pump();

    // Emit download progress event: 50%
    fakePlatform.emitEvent(const SpeechEvent(
      type: SpeechEventType.modelDownloadProgress,
      payload: {
        'modelId': 'n0',
        'bytesDownloaded': 26000000,
        'totalBytes': 52000000,
      },
    ));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  group('VOICEVOX terms dialog', () {
    testWidgets('shows terms dialog when terms not accepted', (tester) async {
      final prefs = InMemorySharedPreferences();
      final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);

      await tester.pumpWidget(_buildScreen(
        fakePlatform,
        settingsStore: settingsStore,
      ));
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

      await tester.pumpWidget(_buildScreen(
        fakePlatform,
        settingsStore: settingsStore,
      ));
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

    testWidgets('skips dialog when terms already accepted', (tester) async {
      final prefs = InMemorySharedPreferences();
      final settingsStore = SharedPreferencesSettingsStore(prefs: prefs);
      // Pre-accept terms.
      await settingsStore
          .save(AppSettings.defaults.copyWith(voicevoxTermsAccepted: true));

      await tester.pumpWidget(_buildScreen(
        fakePlatform,
        settingsStore: settingsStore,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('download-btn-1')));
      await tester.pump();
      await tester.pump();

      // Dialog should NOT appear — download proceeds directly.
      expect(find.text('VOICEVOX 利用規約'), findsNothing);
    });
  });
}
