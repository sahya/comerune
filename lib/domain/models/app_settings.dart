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

/// コメント文字サイズの最小値 (px)。
const double commentFontSizeMin = 10;

/// コメント文字サイズの最大値 (px)。
const double commentFontSizeMax = 48;

/// コメント文字サイズのデフォルト値 (px)。
const double commentFontSizeDefault = 14;

/// 旧 enum 形式の保存値を px 値に変換する。
///
/// 以前のバージョンでは `CommentFontSize` enum の `storageValue` (文字列)
/// で保存していたため、後方互換性のために変換をサポートする。
double commentFontSizeFromStorageValue(String? raw) {
  if (raw == null) {
    return commentFontSizeDefault;
  }

  // 数値として直接パースを試みる (新形式)。
  final double? parsed = double.tryParse(raw);
  if (parsed != null) {
    return parsed.clamp(commentFontSizeMin, commentFontSizeMax);
  }

  // 旧 enum 形式のフォールバック。
  switch (raw) {
    case 'xs':
      return 10;
    case 'small':
      return 12;
    case 'large':
      return 16;
    case 'xl':
      return 18;
    case 'xxl':
      return 20;
    case 'medium':
    default:
      return commentFontSizeDefault;
  }
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
    required this.favoriteUserIds,
    required this.pastCommentFetchCount,
    required this.showUserName,
    required this.resolveUserName,
    required this.commentFontSize,
    required this.autoSaveCommentLog,
    required this.statisticsEnabled,
    required this.statisticsViewerCommentEnabled,
    required this.statisticsActiveUserEnabled,
    required this.debugMode,
  }) : assert(
          commentFontSize >= commentFontSizeMin &&
              commentFontSize <= commentFontSizeMax,
          'commentFontSize must be between $commentFontSizeMin and $commentFontSizeMax, '
          'but was $commentFontSize',
        );

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
    favoriteUserIds: '',
    pastCommentFetchCount: PastCommentFetchCount.count100,
    showUserName: true,
    resolveUserName: true,
    commentFontSize: commentFontSizeDefault,
    autoSaveCommentLog: false,
    statisticsEnabled: false,
    statisticsViewerCommentEnabled: true,
    statisticsActiveUserEnabled: true,
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

  /// Newline-separated user IDs to monitor in the connection list.
  final String favoriteUserIds;
  final PastCommentFetchCount pastCommentFetchCount;
  final bool showUserName;
  final bool resolveUserName;
  final double commentFontSize;
  final bool autoSaveCommentLog;
  final bool statisticsEnabled;
  final bool statisticsViewerCommentEnabled;
  final bool statisticsActiveUserEnabled;
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

  Set<String> get favoriteUserIdSet {
    if (favoriteUserIds.trim().isEmpty) {
      return const <String>{};
    }
    return favoriteUserIds
        .split('\n')
        .map((String id) => id.trim())
        .where((String id) => id.isNotEmpty)
        .toSet();
  }

  AppSettings addFavoriteUserId(String userId) {
    final Set<String> current = favoriteUserIdSet;
    if (current.contains(userId)) {
      return this;
    }
    final String updated = <String>[...current, userId].join('\n');
    return copyWith(favoriteUserIds: updated);
  }

  AppSettings removeFavoriteUserId(String userId) {
    final Set<String> current = favoriteUserIdSet;
    if (!current.contains(userId)) {
      return this;
    }
    final Set<String> updated = Set<String>.from(current)..remove(userId);
    return copyWith(favoriteUserIds: updated.join('\n'));
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
    String? favoriteUserIds,
    PastCommentFetchCount? pastCommentFetchCount,
    bool? showUserName,
    bool? resolveUserName,
    double? commentFontSize,
    bool? autoSaveCommentLog,
    bool? statisticsEnabled,
    bool? statisticsViewerCommentEnabled,
    bool? statisticsActiveUserEnabled,
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
      favoriteUserIds: favoriteUserIds ?? this.favoriteUserIds,
      pastCommentFetchCount:
          pastCommentFetchCount ?? this.pastCommentFetchCount,
      showUserName: showUserName ?? this.showUserName,
      resolveUserName: resolveUserName ?? this.resolveUserName,
      commentFontSize: commentFontSize ?? this.commentFontSize,
      autoSaveCommentLog: autoSaveCommentLog ?? this.autoSaveCommentLog,
      statisticsEnabled: statisticsEnabled ?? this.statisticsEnabled,
      statisticsViewerCommentEnabled:
          statisticsViewerCommentEnabled ?? this.statisticsViewerCommentEnabled,
      statisticsActiveUserEnabled:
          statisticsActiveUserEnabled ?? this.statisticsActiveUserEnabled,
      debugMode: debugMode ?? this.debugMode,
    );
  }
}
