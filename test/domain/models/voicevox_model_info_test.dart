import 'package:flutter_test/flutter_test.dart';
import 'package:comerune/domain/models/voicevox_model_info.dart';

void main() {
  final sampleMap = {
    'modelId': '1',
    'displayName': 'ずんだもん',
    'speakerIds': [4, 5, 6, 7],
    'vvmFileName': '1.vvm',
    'fileSizeBytes': 52000000,
    'isBundled': false,
    'downloadState': 'NOT_DOWNLOADED',
  };

  group('VoicevoxModelInfo.fromMap', () {
    test('parses all fields correctly with DOWNLOADED state', () {
      final map = {...sampleMap, 'downloadState': 'DOWNLOADED'};
      final info = VoicevoxModelInfo.fromMap(map);

      expect(info.modelId, '1');
      expect(info.displayName, 'ずんだもん');
      expect(info.speakerIds, [4, 5, 6, 7]);
      expect(info.vvmFileName, '1.vvm');
      expect(info.fileSizeBytes, 52000000);
      expect(info.isBundled, false);
      expect(info.downloadState, ModelDownloadState.downloaded);
    });

    test('parses NOT_DOWNLOADED state', () {
      final info = VoicevoxModelInfo.fromMap(sampleMap);

      expect(info.downloadState, ModelDownloadState.notDownloaded);
    });

    test('parses DOWNLOADING state', () {
      final map = {...sampleMap, 'downloadState': 'DOWNLOADING'};
      final info = VoicevoxModelInfo.fromMap(map);

      expect(info.downloadState, ModelDownloadState.downloading);
    });

    test('parses ERROR state', () {
      final map = {...sampleMap, 'downloadState': 'ERROR'};
      final info = VoicevoxModelInfo.fromMap(map);

      expect(info.downloadState, ModelDownloadState.error);
    });

    test('defaults to notDownloaded for unknown state string', () {
      final map = {...sampleMap, 'downloadState': 'SOME_UNKNOWN_STATE'};
      final info = VoicevoxModelInfo.fromMap(map);

      expect(info.downloadState, ModelDownloadState.notDownloaded);
    });
  });

  group('VoicevoxModelInfo.copyWith', () {
    test('creates a new instance with updated downloadState', () {
      final original = VoicevoxModelInfo.fromMap(sampleMap);
      final copied =
          original.copyWith(downloadState: ModelDownloadState.downloaded);

      expect(copied.downloadState, ModelDownloadState.downloaded);
      expect(copied.modelId, original.modelId);
      expect(copied.displayName, original.displayName);
      expect(copied.speakerIds, original.speakerIds);
      expect(copied.vvmFileName, original.vvmFileName);
      expect(copied.fileSizeBytes, original.fileSizeBytes);
      expect(copied.isBundled, original.isBundled);
      // Original remains unchanged.
      expect(original.downloadState, ModelDownloadState.notDownloaded);
    });
  });

  group('VoicevoxModelInfo.fileSizeDisplay', () {
    test('returns correct MB string', () {
      final info = VoicevoxModelInfo.fromMap(sampleMap);

      // 52000000 / 1024 / 1024 = ~49.59 => "50 MB"
      expect(info.fileSizeDisplay, '50 MB');
    });
  });
}
