import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/comment_speech/comment_speech.dart';
import 'package:comerune/domain/models/voicevox_model_info.dart';

import 'fake_comment_speech_platform.dart';

void main() {
  late FakeCommentSpeechPlatform fakePlatform;
  late VoicevoxModelManager manager;

  final sampleModelMap = <String, dynamic>{
    'modelId': '1',
    'displayName': 'ずんだもん',
    'speakerIds': <dynamic>[4, 5, 6, 7],
    'vvmFileName': '1.vvm',
    'fileSizeBytes': 52000000,
    'isBundled': false,
    'downloadState': 'NOT_DOWNLOADED',
  };

  setUp(() {
    fakePlatform = FakeCommentSpeechPlatform();
    manager = VoicevoxModelManager(fakePlatform);
    manager.startListening();
  });

  tearDown(() {
    manager.dispose();
    fakePlatform.dispose();
  });

  group('VoicevoxModelManager', () {
    test('refreshModels populates models from platform', () async {
      fakePlatform.availableModelsToReturn = [sampleModelMap];

      await manager.refreshModels();

      expect(manager.models.value.length, 1);
      final model = manager.models.value.first;
      expect(model.modelId, '1');
      expect(model.displayName, 'ずんだもん');
      expect(model.speakerIds, [4, 5, 6, 7]);
      expect(model.vvmFileName, '1.vvm');
      expect(model.fileSizeBytes, 52000000);
      expect(model.isBundled, false);
      expect(model.downloadState, ModelDownloadState.notDownloaded);
    });

    test(
        'model_download_started updates model state to downloading '
        'and sets progress to 0.0', () async {
      fakePlatform.availableModelsToReturn = [sampleModelMap];
      await manager.refreshModels();

      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '1'},
      ));

      // Allow the stream event to be processed.
      await Future<void>.delayed(Duration.zero);

      expect(manager.models.value.first.downloadState,
          ModelDownloadState.downloading);
      expect(manager.downloadProgress.value['1'], 0.0);
    });

    test('model_download_progress updates download progress', () async {
      fakePlatform.availableModelsToReturn = [sampleModelMap];
      await manager.refreshModels();

      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);

      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadProgress,
        payload: {
          'modelId': '1',
          'bytesDownloaded': 26000000,
          'totalBytes': 52000000,
        },
      ));
      await Future<void>.delayed(Duration.zero);

      expect(manager.downloadProgress.value['1'], 0.5);
    });

    test(
        'model_download_completed updates model state to downloaded '
        'and removes progress', () async {
      fakePlatform.availableModelsToReturn = [sampleModelMap];
      await manager.refreshModels();

      // Start download first.
      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);
      expect(manager.downloadProgress.value.containsKey('1'), true);

      // Complete download.
      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadCompleted,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(manager.models.value.first.downloadState,
          ModelDownloadState.downloaded);
      expect(manager.downloadProgress.value.containsKey('1'), false);
    });

    test(
        'model_download_failed updates model state to error '
        'and removes progress', () async {
      fakePlatform.availableModelsToReturn = [sampleModelMap];
      await manager.refreshModels();

      // Start download first.
      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadStarted,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);
      expect(manager.downloadProgress.value.containsKey('1'), true);

      // Fail download.
      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDownloadFailed,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(
          manager.models.value.first.downloadState, ModelDownloadState.error);
      expect(manager.downloadProgress.value.containsKey('1'), false);
    });

    test('model_deleted updates model state to notDownloaded', () async {
      // Start with a downloaded model.
      final downloadedModelMap = {
        ...sampleModelMap,
        'downloadState': 'DOWNLOADED',
      };
      fakePlatform.availableModelsToReturn = [downloadedModelMap];
      await manager.refreshModels();
      expect(manager.models.value.first.downloadState,
          ModelDownloadState.downloaded);

      fakePlatform.emitEvent(const SpeechEvent(
        type: SpeechEventType.modelDeleted,
        payload: {'modelId': '1'},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(manager.models.value.first.downloadState,
          ModelDownloadState.notDownloaded);
    });
  });
}
