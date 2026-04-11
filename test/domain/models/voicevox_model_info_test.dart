import 'dart:io';

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
      final copied = original.copyWith(
        downloadState: ModelDownloadState.downloaded,
      );

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

  group('Kotlin/Dart model consistency', () {
    // NOTE: The regex approach below is fragile and depends on Kotlin
    // formatting conventions (e.g. `modelId = "..."` on its own line).
    // If the regex breaks due to Kotlin code reformatting, update the
    // pattern to match the new style. This is a trade-off: file-parsing
    // test vs. no automated consistency check at all.

    // Path to VoicevoxModelManifest.kt relative to the project root.
    // The test resolves the project root from the test file location.
    late String kotlinSource;

    setUpAll(() {
      // Locate the project root by walking up from the test file.
      final testDir = Directory.current.path;
      final ktFile = File(
        '$testDir/android/app/src/main/kotlin/com/example/comerune/'
        'speech/domain/model/VoicevoxModelManifest.kt',
      );
      if (!ktFile.existsSync()) {
        fail(
          'VoicevoxModelManifest.kt not found at ${ktFile.path}. '
          'Run this test from the project root.',
        );
      }
      kotlinSource = ktFile.readAsStringSync();
    });

    test('supportedVoicevoxModelIds matches Kotlin manifest model IDs', () {
      // Remove block comments (/* ... */) and single-line comments (//).
      final withoutBlockComments = kotlinSource.replaceAll(
        RegExp(r'/\*[\s\S]*?\*/'),
        '',
      );
      final nonCommentLines = withoutBlockComments
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      // Extract modelId values from Kotlin source.
      // Pattern matches: modelId = "..." (with surrounding whitespace).
      final modelIdPattern = RegExp(r'modelId\s*=\s*"([^"]+)"');
      final kotlinModelIds = modelIdPattern
          .allMatches(nonCommentLines)
          .map((m) => m.group(1)!)
          .toSet();

      expect(
        kotlinModelIds,
        isNotEmpty,
        reason: 'Failed to parse any modelId from VoicevoxModelManifest.kt',
      );

      expect(
        supportedVoicevoxModelIds,
        equals(kotlinModelIds),
        reason:
            'supportedVoicevoxModelIds in voicevox_model_info.dart '
            'does not match VoicevoxModelManifest.kt.\n'
            '  Dart: $supportedVoicevoxModelIds\n'
            '  Kotlin: $kotlinModelIds\n'
            'Update both files when adding or removing models.',
      );
    });

    test(
      'supportedVoicevoxSpeakerNames matches Kotlin manifest display names',
      () {
        // Remove block comments (/* ... */) and single-line comments (//).
        final withoutBlockComments = kotlinSource.replaceAll(
          RegExp(r'/\*[\s\S]*?\*/'),
          '',
        );
        final nonCommentLines = withoutBlockComments
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');

        // Extract displayName values from Kotlin source.
        // Pattern matches: displayName = "..." (with surrounding whitespace).
        final displayNamePattern = RegExp(r'displayName\s*=\s*"([^"]+)"');
        final kotlinDisplayNames = displayNamePattern
            .allMatches(nonCommentLines)
            .map((m) => m.group(1)!)
            .toSet();

        expect(
          kotlinDisplayNames,
          isNotEmpty,
          reason:
              'Failed to parse any displayName from VoicevoxModelManifest.kt',
        );

        expect(
          supportedVoicevoxSpeakerNames,
          equals(kotlinDisplayNames),
          reason:
              'supportedVoicevoxSpeakerNames in voicevox_model_info.dart '
              'does not match VoicevoxModelManifest.kt.\n'
              '  Dart: $supportedVoicevoxSpeakerNames\n'
              '  Kotlin: $kotlinDisplayNames\n'
              'Update both files when adding or removing models.',
        );
      },
    );
  });
}
