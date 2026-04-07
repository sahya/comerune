/// Model IDs for VOICEVOX speakers supported by this app.
///
/// - `n0`: VOICEVOX Nemo (bundled)
/// - `2`: 春日部つむぎ
/// - `3`: 波音リツ
const Set<String> supportedVoicevoxModelIds = <String>{'n0', '2', '3'};

/// Display names of supported speakers for terms filtering.
const Set<String> supportedVoicevoxSpeakerNames = <String>{
  'VOICEVOX Nemo',
  '春日部つむぎ',
  '波音リツ',
};

/// Download state of a VOICEVOX voice model.
enum ModelDownloadState { notDownloaded, downloading, downloaded, error }

/// Information about a VOICEVOX voice model.
class VoicevoxModelInfo {
  const VoicevoxModelInfo({
    required this.modelId,
    required this.displayName,
    required this.speakerIds,
    required this.vvmFileName,
    required this.fileSizeBytes,
    required this.isBundled,
    required this.downloadState,
  });

  final String modelId;
  final String displayName;
  final List<int> speakerIds;
  final String vvmFileName;
  final int fileSizeBytes;
  final bool isBundled;
  final ModelDownloadState downloadState;

  factory VoicevoxModelInfo.fromMap(Map<String, dynamic> map) {
    return VoicevoxModelInfo(
      modelId: map['modelId'] as String,
      displayName: map['displayName'] as String,
      speakerIds: (map['speakerIds'] as List<dynamic>).cast<int>(),
      vvmFileName: map['vvmFileName'] as String,
      fileSizeBytes: map['fileSizeBytes'] as int,
      isBundled: map['isBundled'] as bool,
      downloadState: _parseDownloadState(map['downloadState'] as String?),
    );
  }

  VoicevoxModelInfo copyWith({ModelDownloadState? downloadState}) {
    return VoicevoxModelInfo(
      modelId: modelId,
      displayName: displayName,
      speakerIds: speakerIds,
      vvmFileName: vvmFileName,
      fileSizeBytes: fileSizeBytes,
      isBundled: isBundled,
      downloadState: downloadState ?? this.downloadState,
    );
  }

  String get fileSizeDisplay {
    final double mb = fileSizeBytes / 1024 / 1024;
    return '${mb.toStringAsFixed(0)} MB';
  }

  static ModelDownloadState _parseDownloadState(String? raw) {
    switch (raw) {
      case 'DOWNLOADED':
        return ModelDownloadState.downloaded;
      case 'DOWNLOADING':
        return ModelDownloadState.downloading;
      case 'ERROR':
        return ModelDownloadState.error;
      case 'NOT_DOWNLOADED':
      default:
        return ModelDownloadState.notDownloaded;
    }
  }
}
