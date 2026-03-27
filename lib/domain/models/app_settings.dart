enum SpeechEngine {
  bouyomi,
  voicevox,
}

enum PastCommentFetchCount {
  count100,
  count500,
  count1000,
  all,
}

extension PastCommentFetchCountValue on PastCommentFetchCount {
  String get storageValue {
    switch (this) {
      case PastCommentFetchCount.count100:
        return '100';
      case PastCommentFetchCount.count500:
        return '500';
      case PastCommentFetchCount.count1000:
        return '1000';
      case PastCommentFetchCount.all:
        return 'all';
    }
  }

  String get label {
    switch (this) {
      case PastCommentFetchCount.count100:
        return '100';
      case PastCommentFetchCount.count500:
        return '500';
      case PastCommentFetchCount.count1000:
        return '1000';
      case PastCommentFetchCount.all:
        return '全部（上限あり）';
    }
  }

  static PastCommentFetchCount fromStorageValue(String? raw) {
    switch (raw) {
      case '500':
        return PastCommentFetchCount.count500;
      case '1000':
        return PastCommentFetchCount.count1000;
      case 'all':
        return PastCommentFetchCount.all;
      case '100':
      case null:
      default:
        return PastCommentFetchCount.count100;
    }
  }
}

class AppSettings {
  const AppSettings({
    required this.autoReadEnabled,
    required this.speechEngine,
    required this.bouyomiHost,
    required this.bouyomiSpeed,
    required this.bouyomiTone,
    required this.bouyomiVolume,
    required this.bouyomiVoice,
    required this.voicevoxSpeaker,
    required this.voicevoxSpeed,
    required this.voicevoxPitch,
    required this.voicevoxIntonation,
    required this.voicevoxVolume,
    required this.queueLimit,
    required this.maxDelaySeconds,
    required this.omitUrl,
    required this.suppressDuplicate,
    required this.ngWords,
    required this.pastCommentFetchCount,
    required this.debugMode,
  });

  static const AppSettings defaults = AppSettings(
    autoReadEnabled: false,
    speechEngine: SpeechEngine.bouyomi,
    bouyomiHost: '',
    bouyomiSpeed: -1,
    bouyomiTone: -1,
    bouyomiVolume: -1,
    bouyomiVoice: 0,
    voicevoxSpeaker: 0,
    voicevoxSpeed: 1.0,
    voicevoxPitch: 0.0,
    voicevoxIntonation: 1.0,
    voicevoxVolume: 1.0,
    queueLimit: 20,
    maxDelaySeconds: 10,
    omitUrl: true,
    suppressDuplicate: true,
    ngWords: '',
    pastCommentFetchCount: PastCommentFetchCount.count100,
    debugMode: false,
  );

  final bool autoReadEnabled;
  final SpeechEngine speechEngine;
  final String bouyomiHost;
  final int bouyomiSpeed;
  final int bouyomiTone;
  final int bouyomiVolume;
  final int bouyomiVoice;
  final int voicevoxSpeaker;
  final double voicevoxSpeed;
  final double voicevoxPitch;
  final double voicevoxIntonation;
  final double voicevoxVolume;
  final int queueLimit;
  final int maxDelaySeconds;
  final bool omitUrl;
  final bool suppressDuplicate;
  final String ngWords;
  final PastCommentFetchCount pastCommentFetchCount;
  final bool debugMode;

  AppSettings copyWith({
    bool? autoReadEnabled,
    SpeechEngine? speechEngine,
    String? bouyomiHost,
    int? bouyomiSpeed,
    int? bouyomiTone,
    int? bouyomiVolume,
    int? bouyomiVoice,
    int? voicevoxSpeaker,
    double? voicevoxSpeed,
    double? voicevoxPitch,
    double? voicevoxIntonation,
    double? voicevoxVolume,
    int? queueLimit,
    int? maxDelaySeconds,
    bool? omitUrl,
    bool? suppressDuplicate,
    String? ngWords,
    PastCommentFetchCount? pastCommentFetchCount,
    bool? debugMode,
  }) {
    return AppSettings(
      autoReadEnabled: autoReadEnabled ?? this.autoReadEnabled,
      speechEngine: speechEngine ?? this.speechEngine,
      bouyomiHost: bouyomiHost ?? this.bouyomiHost,
      bouyomiSpeed: bouyomiSpeed ?? this.bouyomiSpeed,
      bouyomiTone: bouyomiTone ?? this.bouyomiTone,
      bouyomiVolume: bouyomiVolume ?? this.bouyomiVolume,
      bouyomiVoice: bouyomiVoice ?? this.bouyomiVoice,
      voicevoxSpeaker: voicevoxSpeaker ?? this.voicevoxSpeaker,
      voicevoxSpeed: voicevoxSpeed ?? this.voicevoxSpeed,
      voicevoxPitch: voicevoxPitch ?? this.voicevoxPitch,
      voicevoxIntonation: voicevoxIntonation ?? this.voicevoxIntonation,
      voicevoxVolume: voicevoxVolume ?? this.voicevoxVolume,
      queueLimit: queueLimit ?? this.queueLimit,
      maxDelaySeconds: maxDelaySeconds ?? this.maxDelaySeconds,
      omitUrl: omitUrl ?? this.omitUrl,
      suppressDuplicate: suppressDuplicate ?? this.suppressDuplicate,
      ngWords: ngWords ?? this.ngWords,
      pastCommentFetchCount:
          pastCommentFetchCount ?? this.pastCommentFetchCount,
      debugMode: debugMode ?? this.debugMode,
    );
  }
}
