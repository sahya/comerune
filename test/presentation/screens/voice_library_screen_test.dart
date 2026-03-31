import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/presentation/screens/voice_library_screen.dart';

import '../../comment_speech/fake_comment_speech_platform.dart';

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

Widget _buildScreen(FakeCommentSpeechPlatform platform) {
  return MaterialApp(
    home: VoiceLibraryScreen(platform: platform),
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
}
