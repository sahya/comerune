import 'dart:developer' as developer;

import '../../comment_speech/src/models/replace_rule.dart';
import '../../comment_speech/src/models/speech_settings.dart';
import '../utils/newline_parser.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  protanopia,
  deuteranopia,
  tritanopia,
}

extension AppThemeModeValue on AppThemeMode {
  String get storageValue {
    switch (this) {
      case AppThemeMode.system:
        return 'system';
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
      case AppThemeMode.system:
        return 'システム設定に従う';
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
      case 'system':
        return AppThemeMode.system;
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

// TODO(#13): 棒読みちゃん(bouyomi)はUIから非表示。サーバー管理しない方針のため、
// 今後削除するか再実装するかは未定。bouyomi の enum 値・設定フィールドは
// 後方互換のため残している。
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

/// ニコニコ用語のデフォルト読み上げ辞書ルール。
const List<ReplaceRule> defaultNicoDictionaryRules = <ReplaceRule>[
  ReplaceRule(pattern: r'[wｗ]{3,}', replacement: 'わらわら'),
  ReplaceRule(pattern: r'[wｗ]{1,2}$', replacement: 'わら'),
  ReplaceRule(pattern: r'8{3,}|８{3,}', replacement: 'ぱちぱちぱち'),
  ReplaceRule(pattern: r'おつ$', replacement: 'おつかれ'),
  ReplaceRule(pattern: r'わこつ', replacement: 'わくおつ'),
  ReplaceRule(pattern: r'うぽつ', replacement: 'うぷおつ'),
  ReplaceRule(pattern: r'初見', replacement: 'しょけん'),
  ReplaceRule(pattern: r'[kｋ][wｗ][sｓ][kｋ]', replacement: 'くわしく'),
  ReplaceRule(pattern: r'[kｋ][sｓ][kｋ]', replacement: 'かそく'),
];

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
    required this.autoNicknameRegistration,
    required this.autoSaveCommentLog,
    required this.autoSaveCommentLogPath,
    required this.statisticsEnabled,
    required this.statisticsViewerCommentEnabled,
    required this.statisticsActiveUserEnabled,
    required this.highlightPickupEnabled,
    required this.starPrefixHidingEnabled,
    required this.slashPrefixSkipEnabled,
    required this.readUserName,
    required this.voicevoxTermsAccepted,
    required this.dictionaryRules,
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
    speechEngine: SpeechEngine.voicevox,
    bouyomiHost: '',
    bouyomiSpeed: -1,
    bouyomiTone: -1,
    bouyomiVolume: -1,
    bouyomiVoice: 0,
    voicevoxSpeaker: 10000,
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
    autoNicknameRegistration: true,
    autoSaveCommentLog: false,
    autoSaveCommentLogPath: '',
    statisticsEnabled: false,
    statisticsViewerCommentEnabled: true,
    statisticsActiveUserEnabled: true,
    highlightPickupEnabled: false,
    starPrefixHidingEnabled: false,
    slashPrefixSkipEnabled: true,
    readUserName: false,
    voicevoxTermsAccepted: false,
    dictionaryRules: defaultNicoDictionaryRules,
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
  final bool autoNicknameRegistration;
  final bool autoSaveCommentLog;

  /// User-selected directory path for auto-saving comment logs.
  /// Empty string means the default app documents directory is used.
  final String autoSaveCommentLogPath;
  final bool statisticsEnabled;
  final bool statisticsViewerCommentEnabled;
  final bool statisticsActiveUserEnabled;

  /// When true, peak time comments are automatically picked up and displayed
  /// when a broadcast ends.
  final bool highlightPickupEnabled;

  /// When true, comments starting with `☆` have their body hidden
  /// (tap to reveal) and are skipped for TTS.
  final bool starPrefixHidingEnabled;

  /// When true, comments starting with `/` are skipped for TTS
  /// but displayed normally.
  final bool slashPrefixSkipEnabled;

  /// When true, the user name is prepended to the comment text for TTS
  /// in the format `{userName}、{comment}`.
  final bool readUserName;

  /// VOICEVOX 音声モデルの利用規約に同意済みかどうか。
  final bool voicevoxTermsAccepted;

  /// 読み上げ時のテキスト置換ルール（ニコニコ用語辞書）。
  final List<ReplaceRule> dictionaryRules;

  final bool debugMode;

  /// Parses [ngWords] into a list of lower-cased NG word strings.
  ///
  /// Each line is trimmed and lower-cased; blank lines are ignored.
  /// The result is pre-lowered so that callers can compare with a single
  /// [String.contains] against lower-cased content.
  List<String> get ngWordList {
    return parseNewlineSeparatedLowerList(ngWords);
  }

  /// Returns `true` when [content] contains any of the configured NG words.
  ///
  /// Matching is case-insensitive and uses plain substring search.
  bool containsNgWord(String content) {
    final List<String> words = ngWordList;
    if (words.isEmpty) {
      return false;
    }
    final String lowerContent = content.toLowerCase();
    return words.any(
      (String word) => lowerContent.contains(word),
    );
  }

  Set<String> get ngUserIdSet {
    return parseNewlineSeparatedSet(ngUserIds);
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
    return parseNewlineSeparatedSet(favoriteUserIds);
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
    bool? autoNicknameRegistration,
    bool? autoSaveCommentLog,
    String? autoSaveCommentLogPath,
    bool? statisticsEnabled,
    bool? statisticsViewerCommentEnabled,
    bool? statisticsActiveUserEnabled,
    bool? highlightPickupEnabled,
    bool? starPrefixHidingEnabled,
    bool? slashPrefixSkipEnabled,
    bool? readUserName,
    bool? voicevoxTermsAccepted,
    List<ReplaceRule>? dictionaryRules,
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
      autoNicknameRegistration:
          autoNicknameRegistration ?? this.autoNicknameRegistration,
      autoSaveCommentLog: autoSaveCommentLog ?? this.autoSaveCommentLog,
      autoSaveCommentLogPath:
          autoSaveCommentLogPath ?? this.autoSaveCommentLogPath,
      statisticsEnabled: statisticsEnabled ?? this.statisticsEnabled,
      statisticsViewerCommentEnabled:
          statisticsViewerCommentEnabled ?? this.statisticsViewerCommentEnabled,
      statisticsActiveUserEnabled:
          statisticsActiveUserEnabled ?? this.statisticsActiveUserEnabled,
      highlightPickupEnabled:
          highlightPickupEnabled ?? this.highlightPickupEnabled,
      starPrefixHidingEnabled:
          starPrefixHidingEnabled ?? this.starPrefixHidingEnabled,
      slashPrefixSkipEnabled:
          slashPrefixSkipEnabled ?? this.slashPrefixSkipEnabled,
      readUserName: readUserName ?? this.readUserName,
      voicevoxTermsAccepted:
          voicevoxTermsAccepted ?? this.voicevoxTermsAccepted,
      dictionaryRules: dictionaryRules ?? this.dictionaryRules,
      debugMode: debugMode ?? this.debugMode,
    );
  }

  /// Convert to [SpeechSettings] for the platform speech engine.
  SpeechSettings toSpeechSettings() => SpeechSettings(
        enabled: autoReadEnabled && speechEngine == SpeechEngine.voicevox,
        speakerId: voicevoxSpeaker,
        speedScale: voicevoxSpeed,
        pitchScale: voicevoxPitch,
        intonationScale: voicevoxIntonation,
        volumeScale: voicevoxVolume,
        maxQueueSize: queueLimit,
        ngWords: ngWordList,
        dictionaryRules: dictionaryRules,
      );
}
