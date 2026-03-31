import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
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

  testWidgets('shows delete button for downloaded non-bundled model',
      (tester) async {
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
    fakePlatform.emitEvent(const SpeechEvent(
      type: SpeechEventType.modelDownloadStarted,
      payload: {'modelId': '1'},
    ));
    await tester.pump();

    // Emit download progress event: 50%
    fakePlatform.emitEvent(const SpeechEvent(
      type: SpeechEventType.modelDownloadProgress,
      payload: {
        'modelId': '1',
        'bytesDownloaded': 26000000,
        'totalBytes': 52000000,
      },
    ));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });
}
