import 'dart:developer' as developer;

enum AppThemeMode {
  light,
  dark,
  protanopia,
  deuteranopia,
  tritanopia,
}

extension AppThemeModeValue on AppThemeMode {
  String get storageValue {
    switch (this) {
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
      case AppThemeMode.protanopia:
        return 'protanopia';
      case AppThemeMode.deuteranopia:
        return 'deuteranopia';
      case AppThemeMode.tritanopia:
        return 'tritanopia';
    }
  }

  String get label {
    switch (this) {
      case AppThemeMode.light:
        return 'ライト';
      case AppThemeMode.dark:
        return 'ダーク';
      case AppThemeMode.protanopia:
        return '赤が見えにくい方向け（P型）';
      case AppThemeMode.deuteranopia:
        return '緑が見えにくい方向け（D型）';
      case AppThemeMode.tritanopia:
        return '青黄の区別サポート（T型）';
    }
  }

  static AppThemeMode fromStorageValue(String? raw) {
    switch (raw) {
      case 'dark':
        return AppThemeMode.dark;
      case 'protanopia':
        return AppThemeMode.protanopia;
      case 'deuteranopia':
        return AppThemeMode.deuteranopia;
      case 'tritanopia':
        return AppThemeMode.tritanopia;
      case 'light':
      case null:
        return AppThemeMode.light;
      default:
        developer.log(
          'Unknown AppThemeMode storage value: "$raw", falling back to light',
          name: 'AppThemeMode',
        );
        return AppThemeMode.light;
    }
  }
}

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

  int get historyCount {
    switch (this) {
      case PastCommentFetchCount.count100:
        return 100;
      case PastCommentFetchCount.count500:
        return 500;
      case PastCommentFetchCount.count1000:
        return 1000;
      case PastCommentFetchCount.all:
        return 10000;
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
    required this.themeMode,
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
    required this.ngUserIds,
    required this.pastCommentFetchCount,
    required this.showUserName,
    required this.resolveUserName,
    required this.debugMode,
  });

  static const AppSettings defaults = AppSettings(
    themeMode: AppThemeMode.light,
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
    ngUserIds: '',
    pastCommentFetchCount: PastCommentFetchCount.count100,
    showUserName: true,
    resolveUserName: true,
    debugMode: false,
  );

  final AppThemeMode themeMode;
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

  /// Newline-separated user IDs to filter out from display.
  final String ngUserIds;
  final PastCommentFetchCount pastCommentFetchCount;
  final bool showUserName;
  final bool resolveUserName;
  final bool debugMode;

  Set<String> get ngUserIdSet {
    if (ngUserIds.trim().isEmpty) {
      return const <String>{};
    }
    return ngUserIds
        .split('\n')
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet();
  }

  bool isNgUser(String? userId) {
    if (userId == null || userId.isEmpty) {
      return false;
    }
    return ngUserIdSet.contains(userId);
  }

  AppSettings addNgUserId(String userId) {
    final Set<String> current = ngUserIdSet;
    if (current.contains(userId)) {
      return this;
    }
    final String updated = <String>[...current, userId].join('\n');
    return copyWith(ngUserIds: updated);
  }

  AppSettings removeNgUserId(String userId) {
    final Set<String> current = ngUserIdSet;
    if (!current.contains(userId)) {
      return this;
    }
    final Set<String> updated = Set<String>.from(current)..remove(userId);
    return copyWith(ngUserIds: updated.join('\n'));
  }

  AppSettings copyWith({
    AppThemeMode? themeMode,
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
    String? ngUserIds,
    PastCommentFetchCount? pastCommentFetchCount,
    bool? showUserName,
    bool? resolveUserName,
    bool? debugMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
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
      ngUserIds: ngUserIds ?? this.ngUserIds,
      pastCommentFetchCount:
          pastCommentFetchCount ?? this.pastCommentFetchCount,
      showUserName: showUserName ?? this.showUserName,
      resolveUserName: resolveUserName ?? this.resolveUserName,
      debugMode: debugMode ?? this.debugMode,
    );
  }
}
