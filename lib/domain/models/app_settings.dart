import 'dart:convert';
import 'dart:developer' as developer;

import '../../comment_speech/src/models/replace_rule.dart';
import '../../comment_speech/src/models/speech_settings.dart';
import '../utils/newline_parser.dart';
import 'ng_word_rule.dart';

export '../../comment_speech/src/models/speech_settings.dart'
    show SpeechEngineType, SynthesisMode;

enum AppThemeMode { system, light, dark, protanopia, deuteranopia, tritanopia }

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

enum SpeechEngine { voicevox, androidTts }

/// 音声再生方式。
enum VoicevoxPlayerType {
  /// AudioTrack（メモリ直接再生）— 応答時間: 小 / ファイルI/Oなし
  audioTrack,

  /// MediaPlayer（一時ファイル経由）— 応答時間: 大 / ファイルI/Oあり
  mediaPlayer,
}

/// コメント文字サイズの最小値 (px)。
const double commentFontSizeMin = 10;

/// コメント文字サイズの最大値 (px)。
const double commentFontSizeMax = 48;

/// コメント文字サイズのデフォルト値 (px)。
const double commentFontSizeDefault = 14;

/// 二段表示の上段（時刻・ユーザー名）の文字サイズが、本文サイズに対して
/// 占める割合の最小値 (%)。極端に小さい値でも、表示時には別途 9px の
/// 下限が適用される（[commentTwoLineMetaFontPercentToRatio] と
/// クライアント側 clamp の組み合わせ）。
const int commentTwoLineMetaFontPercentMin = 20;

/// 二段表示の上段の文字サイズ割合の最大値 (%)。
/// 100% を超えると本文より大きくなり「上段=メタ情報」という階層が崩れるため
/// 100 を上限とする。
const int commentTwoLineMetaFontPercentMax = 100;

/// 二段表示の上段の文字サイズ割合のデフォルト値 (%)。
/// 過去バージョンでハードコードされていた 0.4 と等価。
const int commentTwoLineMetaFontPercentDefault = 40;

/// 整数パーセンテージ (例: 40) を比率 (例: 0.4) に変換し、
/// 想定範囲外の値を許容範囲へクランプする。
double commentTwoLineMetaFontPercentToRatio(int percent) {
  final int clamped = percent.clamp(
    commentTwoLineMetaFontPercentMin,
    commentTwoLineMetaFontPercentMax,
  );
  return clamped / 100.0;
}

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

/// コメントスクロール（タイムライン表示）の並び順。
///
/// `ascending` は古いコメントが上、新しいコメントが下に並ぶ。
/// `descending` は逆。AppBar のソート切替ボタンで反転する。
///
/// 永続化は [SharedPreferencesSettingsStore] が `String?` 経由で行う。
/// 未保存・不正値・未知値はすべて [AppSettings.defaults.commentSortOrder]
/// (=`ascending`) にフォールバックする。
enum CommentSortOrder { ascending, descending }

extension CommentSortOrderValue on CommentSortOrder {
  /// 永続化や JSON Export に使う安定した文字列表現（`enum.name` に揃える）。
  String get storageValue => name;

  /// 保存値（または JSON 値）から [CommentSortOrder] を復元する。
  /// `null`・未知値はデフォルト ([AppSettings.defaults.commentSortOrder]) に
  /// フォールバックする。
  static CommentSortOrder fromStorageValue(String? raw) {
    switch (raw) {
      case 'descending':
        return CommentSortOrder.descending;
      case 'ascending':
        return CommentSortOrder.ascending;
      case null:
        return AppSettings.defaults.commentSortOrder;
      default:
        developer.log(
          'Unknown CommentSortOrder storage value: "$raw", '
          'falling back to default',
          name: 'CommentSortOrder',
        );
        return AppSettings.defaults.commentSortOrder;
    }
  }
}

enum PastCommentFetchCount { count100, count500, count1000, all }

/// タイムライン表示容量を算出する際に、過去コメント取得数へ上乗せする
/// 新着ライブコメント用のバッファサイズ。
///
/// 取得直後の過去コメントが、新着コメントの流入で即座にトリムされないよう、
/// `TimelineStore.capacity` は `historyCount + timelineLiveCommentBufferSize`
/// として計算する。5000 は一般的なライブ配信 1 本分の新着コメントを
/// 余裕をもって保持できるサイズとして選択している。
const int timelineLiveCommentBufferSize = 5000;

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

  /// `TimelineStore` が保持するメッセージ数の上限。
  ///
  /// 取得した過去コメントを新着コメントの流入で失わないよう、
  /// 取得数そのものではなく [timelineLiveCommentBufferSize] を加算した値を
  /// 表示容量として用いる。
  ///
  /// 不変条件: `displayCapacity > historyCount` を常に満たすこと。
  /// この関係を崩す（例: buffer を 0 にする、同値を返す等）と、
  /// 過去コメント取得直後から新着 1 件ごとに最古の過去コメントが
  /// `TimelineStore._trimOverflow` で消える回帰バグが再発する。
  ///
  /// 境界: 新着コメントが `timelineLiveCommentBufferSize` を超えて
  /// 流入し続けると、超過分から最古の（取得済み）過去コメントが
  /// 順次トリムされる。本 PR のスコープは「典型的な視聴時間の新着数」
  /// までの保証で、無制限ではない。恒久的な過去コメント保持や
  /// 漸進的なさらなる取得は別 Issue で対応する。
  int get displayCapacity => historyCount + timelineLiveCommentBufferSize;

  static PastCommentFetchCount fromStorageValue(String? raw) {
    switch (raw) {
      // 明示的に 100 を選んだ既存ユーザーの設定は尊重する（後方互換）。
      case '100':
        return PastCommentFetchCount.count100;
      case '500':
        return PastCommentFetchCount.count500;
      case '1000':
        return PastCommentFetchCount.count1000;
      case 'all':
        return PastCommentFetchCount.all;
      // 未保存 (null) または未知の値は新デフォルト（500 件）に揃える。
      // `AppSettings.defaults.pastCommentFetchCount` と常に一致させること。
      case null:
      default:
        return PastCommentFetchCount.count500;
    }
  }
}

/// ニコニコ用語のデフォルト読み上げ辞書ルール。
///
/// 「w」「ｗ」による笑いプリセットの設計方針:
/// - 3 個以上連続 → 「わらわら」（文中の位置を問わず）
/// - 末尾 2 個 → 「わらわら」
/// - 末尾 1 個 → 「わら」
/// - 文中の単独 1 個 → 「わら」。英数字で挟まれていない（空白・記号・
///   日本語で区切られた）ものを先読み/後読みで広く捕捉する。英単語中の
///   `w`（`we`, `watch` 等）や URL の連続 `w` を壊さないよう、半角英数字
///   との隣接を除外している。
///
/// 末尾専用の `[wｗ]$` / `[wｑ]{2}$` と文中対応の lookbehind/lookahead 版は
/// **機能的に重複** する（末尾の単独 w は両方で捕捉される）。それでも
/// 両方を残している理由:
/// 1. 既存ユーザーの SharedPreferences に保存された旧デフォルトを
///    [isDefaultNicoDictionaryRule] が「組み込み」として認識し続けられる
/// 2. 辞書適用は冪等（最初のルールが置換した後は 2 つ目のルールに `w` は
///    残っていない）ため、重複実行による誤変換は起きない
///
/// Android 側 (`DefaultCommentNormalizer.compressSymbols`) の PATTERN_W は
/// `[wWｗＷ]{2,}` を辞書適用前に「わらわら」に変換するため、末尾 2 個の
/// dictionary ルールは Android 実行時には冗長。ただし単体テストでは
/// 辞書ルールのみを評価するため、テスト期待値の維持目的でも保持する。
const List<ReplaceRule> defaultNicoDictionaryRules = <ReplaceRule>[
  ReplaceRule(pattern: r'[wｗ]{3,}', replacement: 'わらわら'),
  ReplaceRule(pattern: r'[wｗ]{2}$', replacement: 'わらわら'),
  ReplaceRule(pattern: r'[wｗ]$', replacement: 'わら'),
  // 文中（末尾以外）に単独で現れる w/ｗ を「わら」として読ませる。
  // 上 2 つの末尾限定ルールの拡張版。上で捕捉済みの末尾ケースに対しては
  // 既に置換後なので再マッチしない（冪等）。
  ReplaceRule(
    pattern: r'(?<![A-Za-z0-9])[wｗ](?![A-Za-z0-9])',
    replacement: 'わら',
  ),
  ReplaceRule(pattern: r'8{3,}|８{3,}', replacement: 'ぱちぱちぱち'),
  ReplaceRule(pattern: r'おつ$', replacement: 'おつかれ'),
  ReplaceRule(pattern: r'わこつ', replacement: 'わくおつ'),
  ReplaceRule(pattern: r'うぽつ', replacement: 'うぷおつ'),
  ReplaceRule(pattern: r'初見', replacement: 'しょけん'),
  ReplaceRule(pattern: r'[kｋ][wｗ][sｓ][kｋ]', replacement: 'くわしく'),
  ReplaceRule(pattern: r'[kｋ][sｓ][kｋ]', replacement: 'かそく'),
];

/// Returns `true` when [rule] matches one of the built-in dictionary rules.
///
/// The [enabled] flag is ignored so that a disabled built-in rule is still
/// recognized as protected.
bool isDefaultNicoDictionaryPattern(String pattern) {
  return defaultNicoDictionaryRules.any(
    (ReplaceRule defaultRule) => defaultRule.pattern == pattern,
  );
}

/// Returns `true` when [rule] is one of the built-in dictionary rules.
///
/// Protection is pattern-based so that even if replacement text was changed by
/// older versions, the same built-in pattern remains protected.
bool isDefaultNicoDictionaryRule(ReplaceRule rule) {
  return isDefaultNicoDictionaryPattern(rule.pattern);
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.autoReadEnabled,
    required this.speechEngine,
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
    required this.voicevoxSynthesisMode,
    required this.voicevoxPlayerType,
    required this.voicevoxTermsAccepted,
    required this.ngWordRules,
    required this.commentTwoLineEnabled,
    required this.commentTwoLineMetaFontPercent,
    required this.commentZebraStripingEnabled,
    required this.emphasizeGiftNicoadComment,
    required this.dictionaryRules,
    required this.debugMode,
    required this.showOperatorComment,
    required this.showSystemMessage,
    required this.showEmotion,
    required this.showGiftComment,
    required this.showNicoadComment,
    required this.readGiftComment,
    required this.readNicoadComment,
    required this.ngProtectionNotificationEnabled,
    required this.showViolentComment,
    required this.showSexualComment,
    required this.showDiscriminationComment,
    required this.showMinorsRelatedComment,
    required this.androidTtsSpeed,
    required this.androidTtsPitch,
    required this.androidTtsVolume,
    required this.playRemainingAfterEnded,
    required this.commentSortOrder,
    required this.showCommentNo,
  }) : assert(
         commentFontSize >= commentFontSizeMin &&
             commentFontSize <= commentFontSizeMax,
         'commentFontSize must be between $commentFontSizeMin and $commentFontSizeMax, '
         'but was $commentFontSize',
       ),
       assert(
         commentTwoLineMetaFontPercent >= commentTwoLineMetaFontPercentMin &&
             commentTwoLineMetaFontPercent <= commentTwoLineMetaFontPercentMax,
         'commentTwoLineMetaFontPercent must be between '
         '$commentTwoLineMetaFontPercentMin and $commentTwoLineMetaFontPercentMax, '
         'but was $commentTwoLineMetaFontPercent',
       );

  static const AppSettings defaults = AppSettings(
    themeMode: AppThemeMode.light,
    autoReadEnabled: false,
    speechEngine: SpeechEngine.voicevox,
    voicevoxSpeaker: 10004, // VOICEVOX Nemo・女声3
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
    pastCommentFetchCount: PastCommentFetchCount.count500,
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
    voicevoxSynthesisMode: SynthesisMode.audioQuery,
    voicevoxPlayerType: VoicevoxPlayerType.audioTrack,
    voicevoxTermsAccepted: false,
    ngWordRules: <NgWordRule>[],
    commentTwoLineEnabled: false,
    commentTwoLineMetaFontPercent: commentTwoLineMetaFontPercentDefault,
    commentZebraStripingEnabled: false,
    emphasizeGiftNicoadComment: true,
    dictionaryRules: defaultNicoDictionaryRules,
    debugMode: false,
    showOperatorComment: true,
    showSystemMessage: true,
    showEmotion: true,
    showGiftComment: true,
    showNicoadComment: true,
    readGiftComment: false,
    readNicoadComment: false,
    ngProtectionNotificationEnabled: false,
    showViolentComment: false,
    showSexualComment: false,
    showDiscriminationComment: false,
    showMinorsRelatedComment: false,
    androidTtsSpeed: 1.0,
    androidTtsPitch: 1.0,
    androidTtsVolume: 1.0,
    playRemainingAfterEnded: true,
    commentSortOrder: CommentSortOrder.ascending,
    // Issue #784. Default OFF so existing users see no change; opt-in via
    // CommentDisplaySettingsScreen.
    showCommentNo: false,
  );

  final AppThemeMode themeMode;
  final bool autoReadEnabled;
  final SpeechEngine speechEngine;
  final int voicevoxSpeaker;
  final double voicevoxSpeed;
  final double voicevoxPitch;
  final double voicevoxIntonation;
  final double voicevoxVolume;
  final int queueLimit;
  final int maxDelaySeconds;
  final bool omitUrl;
  final bool suppressDuplicate;
  // TODO(#388): マイグレーション完了後、ngWords フィールドと SettingsStore の
  // 関連 load/save を削除する。現在は後方互換のために残している。
  final String ngWords;

  /// Newline-separated user IDs to filter out from display.
  // TODO(#727 follow-up): now vestigial after PR2 removed the read path
  // and PR3 keeps them only for legacy export/import compatibility.
  // Plan a deprecation issue once a few releases ship the new schema.
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

  final SynthesisMode voicevoxSynthesisMode;

  /// VOICEVOX の音声再生方式。
  final VoicevoxPlayerType voicevoxPlayerType;

  /// VOICEVOX 音声モデルの利用規約に同意済みかどうか。
  final bool voicevoxTermsAccepted;

  /// 構造化されたNGワードルール（有効/無効トグル付き）。
  ///
  /// 空リストの場合は旧形式の [ngWords] 文字列にフォールバックする。
  /// マイグレーション後は常にこちらが使用される。
  // TODO(#727 follow-up): now vestigial after PR2 removed the read path
  // and PR3 keeps them only for legacy export/import compatibility.
  // Plan a deprecation issue once a few releases ship the new schema.
  final List<NgWordRule> ngWordRules;

  /// 横幅が狭い端末向けにコメントを二段表示するかどうか。
  final bool commentTwoLineEnabled;

  /// 二段表示時に上段（時刻・ユーザー名）に適用するフォントサイズの割合 (%)。
  /// 本文サイズに対して [commentTwoLineMetaFontPercent]% のサイズで描画する。
  ///
  /// 表示側では追加で「9px の絶対下限」を適用するため、本値を最小値に
  /// しても極端に潰れることはない。
  ///
  /// 1段表示時は無視される。
  final int commentTwoLineMetaFontPercent;

  /// コメント行にゼブラストライプ（偶数/奇数で背景色交互）を適用するかどうか。
  final bool commentZebraStripingEnabled;

  /// ギフト / ニコニ広告コメントを薄い網掛け背景とアイコンで強調表示するかどうか。
  ///
  /// false の場合は通常コメントと同じ見た目になる（ただし種別自体は表示される）。
  final bool emphasizeGiftNicoadComment;

  /// 読み上げ時のテキスト置換ルール（ニコニコ用語辞書）。
  final List<ReplaceRule> dictionaryRules;

  final bool debugMode;

  /// 運営コメント（配信者のマーキー）を表示するかどうか。既定 true。
  final bool showOperatorComment;

  /// システムメッセージ（ICHIBA 等）を表示するかどうか。既定 true。
  final bool showSystemMessage;

  /// エモーション通知を表示するかどうか。既定 true。
  final bool showEmotion;

  /// ギフトコメントを表示するかどうか。既定 true。
  final bool showGiftComment;

  /// ニコニ広告コメントを表示するかどうか。既定 true。
  final bool showNicoadComment;

  /// ギフトコメントを読み上げるかどうか。既定 false。
  ///
  /// true のとき、ギフトメッセージの本文をそのまま読み上げる
  /// （ユーザー名などは付与しない）。
  final bool readGiftComment;

  /// ニコニ広告コメントを読み上げるかどうか。既定 false。
  ///
  /// true のとき、ニコニ広告メッセージの本文をそのまま読み上げる
  /// （ユーザー名などは付与しない）。
  final bool readNicoadComment;

  /// When true, the comment screen shows a snackbar + AppBar badge
  /// whenever a comment is hidden by NG word or NG user filtering.
  ///
  /// Defaults to `false` so that filtering stays silent — matching the
  /// historical behavior — and only announces itself when the broadcaster
  /// opts in. Off means both snackbar and badge are suppressed.
  final bool ngProtectionNotificationEnabled;

  /// When true, comments matched by preset NG categories whose
  /// [NgDisplaySubcategory] is `violence` are still displayed in the comment
  /// list. Defaults to `false` so that the conservative pre-#614 behavior
  /// (preset categories block both display and speech) is preserved until the
  /// user opts in. Wiring of this flag into the actual filter pipeline is
  /// performed in #615; for #614 the value only affects how the auto-saved
  /// log is tagged.
  final bool showViolentComment;

  /// When true, comments matched by preset NG categories whose
  /// [NgDisplaySubcategory] is `sexual` are still displayed in the comment
  /// list. Defaults to `false`. See [showViolentComment] for scope notes.
  final bool showSexualComment;

  /// When true, comments matched by preset NG categories whose
  /// [NgDisplaySubcategory] is `discrimination` are still displayed in the
  /// comment list. Defaults to `false`. See [showViolentComment] for scope
  /// notes.
  final bool showDiscriminationComment;

  /// When true, comments matched by preset NG categories whose
  /// [NgDisplaySubcategory] is `minors` are still displayed in the comment
  /// list. Defaults to `false`. See [showViolentComment] for scope notes.
  final bool showMinorsRelatedComment;

  /// Android標準TTS の話速。0.5〜2.0、デフォルト 1.0。
  final double androidTtsSpeed;

  /// Android標準TTS の音高。0.5〜2.0、デフォ���ト 1.0。
  final double androidTtsPitch;

  /// Android標準TTS の音量。0.0〜1.0、デフォルト 1.0。
  final double androidTtsVolume;

  /// 配信が `ended` になった後も、最大 30 秒間は読み上げキューを継続させる
  /// （Issue #739）。`true` のとき、`ConnectionStatus.ended` を受けても
  /// FGS とキューを即時停止せず、grace 期間内に未読み上げのコメントを
  /// 読み終えるよう試みる。
  ///
  /// `failed` / `stopped` には適用されず、これらは従来通り即時停止する。
  final bool playRemainingAfterEnded;

  /// コメント画面のスクロール方向（並び順）。
  ///
  /// `ascending`（既定）は古いコメントが上、新しいコメントが下に並ぶ。
  /// `descending` は逆順。AppBar のソート切替ボタンで反転し、
  /// 値はセッションをまたいで永続化される（Issue #774）。
  final CommentSortOrder commentSortOrder;

  /// `true` のとき、コメント行のメタ情報領域に NDGR `Chat.no` 由来の
  /// コメント番号を時刻の前に表示する（Issue #784）。
  ///
  /// 既定 `false`。番号は NDGR chat 経路のメッセージにのみ付与され、
  /// 運営コメント / システム通知 / ギフト / ニコニ広告 / 転送コメント
  /// （ニコ生クルーズ等）には表示されない。Legacy WebSocket 経路で
  /// 受信したコメントにも現状は付与されない（Phase 2 以降）。
  /// 一意性・連番性は upstream から保証されないため、ソートキー・
  /// 重複排除キーとしての利用は禁止。
  final bool showCommentNo;

  /// Returns a list of lower-cased NG word pattern strings for filtering.
  ///
  /// When [ngWordRules] is populated (post-migration), only **enabled** rules
  /// are returned. Otherwise falls back to the legacy [ngWords] string.
  List<String> get ngWordList {
    if (ngWordRules.isNotEmpty) {
      // Issue #727: shared helper so the legacy and per-broadcaster paths
      // normalize patterns identically.
      return enabledNgWordPatterns(ngWordRules);
    }
    return parseNewlineSeparatedLowerList(ngWords);
  }

  /// Returns `true` when [content] contains any of the configured NG words.
  ///
  /// Matching is case-insensitive and uses plain substring search.
  bool containsNgWord(String content) {
    return matchedNgWord(content) != null;
  }

  /// Returns the first NG word pattern matched in [content], or `null`
  /// when no configured NG word matches.
  ///
  /// Returned string is the lower-cased pattern from [ngWordList]
  /// (same source as [containsNgWord]). Matching is case-insensitive.
  String? matchedNgWord(String content) {
    final List<String> words = ngWordList;
    if (words.isEmpty) {
      return null;
    }
    final String lowerContent = content.toLowerCase();
    for (final String word in words) {
      if (lowerContent.contains(word)) {
        return word;
      }
    }
    return null;
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
    SynthesisMode? voicevoxSynthesisMode,
    VoicevoxPlayerType? voicevoxPlayerType,
    bool? voicevoxTermsAccepted,
    List<NgWordRule>? ngWordRules,
    bool? commentTwoLineEnabled,
    int? commentTwoLineMetaFontPercent,
    bool? commentZebraStripingEnabled,
    bool? emphasizeGiftNicoadComment,
    List<ReplaceRule>? dictionaryRules,
    bool? debugMode,
    bool? showOperatorComment,
    bool? showSystemMessage,
    bool? showEmotion,
    bool? showGiftComment,
    bool? showNicoadComment,
    bool? readGiftComment,
    bool? readNicoadComment,
    bool? ngProtectionNotificationEnabled,
    bool? showViolentComment,
    bool? showSexualComment,
    bool? showDiscriminationComment,
    bool? showMinorsRelatedComment,
    double? androidTtsSpeed,
    double? androidTtsPitch,
    double? androidTtsVolume,
    bool? playRemainingAfterEnded,
    CommentSortOrder? commentSortOrder,
    bool? showCommentNo,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      autoReadEnabled: autoReadEnabled ?? this.autoReadEnabled,
      speechEngine: speechEngine ?? this.speechEngine,
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
      voicevoxSynthesisMode:
          voicevoxSynthesisMode ?? this.voicevoxSynthesisMode,
      voicevoxPlayerType: voicevoxPlayerType ?? this.voicevoxPlayerType,
      voicevoxTermsAccepted:
          voicevoxTermsAccepted ?? this.voicevoxTermsAccepted,
      ngWordRules: ngWordRules ?? this.ngWordRules,
      commentTwoLineEnabled:
          commentTwoLineEnabled ?? this.commentTwoLineEnabled,
      commentTwoLineMetaFontPercent:
          commentTwoLineMetaFontPercent ?? this.commentTwoLineMetaFontPercent,
      commentZebraStripingEnabled:
          commentZebraStripingEnabled ?? this.commentZebraStripingEnabled,
      emphasizeGiftNicoadComment:
          emphasizeGiftNicoadComment ?? this.emphasizeGiftNicoadComment,
      dictionaryRules: dictionaryRules ?? this.dictionaryRules,
      debugMode: debugMode ?? this.debugMode,
      showOperatorComment: showOperatorComment ?? this.showOperatorComment,
      showSystemMessage: showSystemMessage ?? this.showSystemMessage,
      showEmotion: showEmotion ?? this.showEmotion,
      showGiftComment: showGiftComment ?? this.showGiftComment,
      showNicoadComment: showNicoadComment ?? this.showNicoadComment,
      readGiftComment: readGiftComment ?? this.readGiftComment,
      readNicoadComment: readNicoadComment ?? this.readNicoadComment,
      ngProtectionNotificationEnabled:
          ngProtectionNotificationEnabled ??
          this.ngProtectionNotificationEnabled,
      showViolentComment: showViolentComment ?? this.showViolentComment,
      showSexualComment: showSexualComment ?? this.showSexualComment,
      showDiscriminationComment:
          showDiscriminationComment ?? this.showDiscriminationComment,
      showMinorsRelatedComment:
          showMinorsRelatedComment ?? this.showMinorsRelatedComment,
      androidTtsSpeed: androidTtsSpeed ?? this.androidTtsSpeed,
      androidTtsPitch: androidTtsPitch ?? this.androidTtsPitch,
      androidTtsVolume: androidTtsVolume ?? this.androidTtsVolume,
      playRemainingAfterEnded:
          playRemainingAfterEnded ?? this.playRemainingAfterEnded,
      commentSortOrder: commentSortOrder ?? this.commentSortOrder,
      showCommentNo: showCommentNo ?? this.showCommentNo,
    );
  }

  /// Settings export format version for forward compatibility.
  static const int settingsVersion = 1;

  /// 改行区切りで保持している favoriteUserIds を、Export 用に
  /// 登録順を保った重複なし文字列配列へ変換する。
  List<String> _serializeFavoriteUserIds() {
    if (favoriteUserIds.trim().isEmpty) {
      return const <String>[];
    }
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String line in favoriteUserIds.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Serializes all fields to a JSON-compatible map.
  ///
  /// Uses the same key names and value formats as
  /// [SharedPreferencesSettingsStore] for consistency.
  // TODO: toJson/fromJson のフィールドマッピングは SharedPreferencesSettingsStore.load/save と
  // 重複している。フィールド追加時の変更漏れを防ぐため、将来的にマッピング定義の共通化を検討する。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      '_version': settingsVersion,
      'themeMode': themeMode.storageValue,
      'autoReadEnabled': autoReadEnabled,
      'speechEngine': speechEngine.name,
      'voicevoxSpeaker': voicevoxSpeaker,
      'voicevoxSpeed': voicevoxSpeed,
      'voicevoxPitch': voicevoxPitch,
      'voicevoxIntonation': voicevoxIntonation,
      'voicevoxVolume': voicevoxVolume,
      'queueLimit': queueLimit,
      'maxDelaySeconds': maxDelaySeconds,
      'omitUrl': omitUrl,
      'suppressDuplicate': suppressDuplicate,
      'ngWords': ngWords,
      'ngUserIds': ngUserIds,
      // 改行区切りの内部表現は入出力の見通しが悪いため、
      // Export ではトリム済みの配列として書き出す。元の登録順を保持する。
      // Import は後方互換のため配列・文字列のどちらも受け付ける。
      'favoriteUserIds': _serializeFavoriteUserIds(),
      'pastCommentFetchCount': pastCommentFetchCount.storageValue,
      'showUserName': showUserName,
      'resolveUserName': resolveUserName,
      'commentFontSize': commentFontSize,
      'autoNicknameRegistration': autoNicknameRegistration,
      'autoSaveCommentLog': autoSaveCommentLog,
      'autoSaveCommentLogPath': autoSaveCommentLogPath,
      'statisticsEnabled': statisticsEnabled,
      'statisticsViewerCommentEnabled': statisticsViewerCommentEnabled,
      'statisticsActiveUserEnabled': statisticsActiveUserEnabled,
      'highlightPickupEnabled': highlightPickupEnabled,
      'starPrefixHidingEnabled': starPrefixHidingEnabled,
      'slashPrefixSkipEnabled': slashPrefixSkipEnabled,
      'readUserName': readUserName,
      'voicevoxSynthesisMode': voicevoxSynthesisMode.storageValue,
      'voicevoxPlayerType': voicevoxPlayerType == VoicevoxPlayerType.mediaPlayer
          ? 'media_player'
          : 'audio_track',
      'voicevoxTermsAccepted': voicevoxTermsAccepted,
      'ngWordRules': ngWordRules.map((NgWordRule r) => r.toMap()).toList(),
      'commentTwoLineEnabled': commentTwoLineEnabled,
      'commentTwoLineMetaFontPercent': commentTwoLineMetaFontPercent,
      'commentZebraStripingEnabled': commentZebraStripingEnabled,
      'emphasizeGiftNicoadComment': emphasizeGiftNicoadComment,
      'dictionaryRules': dictionaryRules
          .map((ReplaceRule r) => r.toMap())
          .toList(),
      'debugMode': debugMode,
      'showOperatorComment': showOperatorComment,
      'showSystemMessage': showSystemMessage,
      'showEmotion': showEmotion,
      'showGiftComment': showGiftComment,
      'showNicoadComment': showNicoadComment,
      'readGiftComment': readGiftComment,
      'readNicoadComment': readNicoadComment,
      'ngProtectionNotificationEnabled': ngProtectionNotificationEnabled,
      'showViolentComment': showViolentComment,
      'showSexualComment': showSexualComment,
      'showDiscriminationComment': showDiscriminationComment,
      'showMinorsRelatedComment': showMinorsRelatedComment,
      'androidTtsSpeed': androidTtsSpeed,
      'androidTtsPitch': androidTtsPitch,
      'androidTtsVolume': androidTtsVolume,
      'playRemainingAfterEnded': playRemainingAfterEnded,
      'commentSortOrder': commentSortOrder.storageValue,
      'showCommentNo': showCommentNo,
    };
  }

  /// Deserializes from a JSON map, using defaults for missing/invalid fields.
  ///
  /// Designed for defensive parsing: unknown keys are ignored and missing
  /// keys fall back to [AppSettings.defaults].
  static AppSettings fromJson(Map<String, dynamic> json) {
    const AppSettings d = AppSettings.defaults;

    List<NgWordRule> parseNgWordRules() {
      final Object? raw = json['ngWordRules'];
      if (raw is List) {
        try {
          return raw
              .map((dynamic e) => NgWordRule.fromMap(e as Map<String, dynamic>))
              .toList();
        } on Object {
          return d.ngWordRules;
        }
      }
      return d.ngWordRules;
    }

    // favoriteUserIds は現行の Export では JSON 配列、旧 Export では
    // 改行区切りの文字列として保存される。どちらの形式も受け付ける。
    // 想定外の型や、配列内に非文字列（ネスト配列・Map・数値等）が混入
    // していても落ちないよう、他の parseXxx と同じく try/catch で
    // デフォルトへフォールバックする。
    String parseFavoriteUserIds() {
      final Object? raw = json['favoriteUserIds'];
      if (raw is List) {
        try {
          final List<String> ids = <String>[];
          for (final Object? item in raw) {
            if (item is String) {
              final String trimmed = item.trim();
              if (trimmed.isNotEmpty) {
                ids.add(trimmed);
              }
            }
          }
          return ids.join('\n');
        } on Object {
          return d.favoriteUserIds;
        }
      }
      if (raw is String) {
        return raw;
      }
      return d.favoriteUserIds;
    }

    List<ReplaceRule> parseDictionaryRules() {
      final Object? raw = json['dictionaryRules'];
      if (raw is List) {
        try {
          return raw
              .map(
                (dynamic e) => ReplaceRule.fromMap(e as Map<String, dynamic>),
              )
              .toList();
        } on Object {
          return d.dictionaryRules;
        }
      }
      return d.dictionaryRules;
    }

    final double fontSize =
        (json['commentFontSize'] as num?)?.toDouble() ?? d.commentFontSize;

    return AppSettings(
      themeMode: AppThemeModeValue.fromStorageValue(
        json['themeMode'] as String?,
      ),
      autoReadEnabled: json['autoReadEnabled'] as bool? ?? d.autoReadEnabled,
      speechEngine: _parseSpeechEngine(json['speechEngine'] as String?),
      voicevoxSpeaker: json['voicevoxSpeaker'] as int? ?? d.voicevoxSpeaker,
      voicevoxSpeed:
          (json['voicevoxSpeed'] as num?)?.toDouble() ?? d.voicevoxSpeed,
      voicevoxPitch:
          (json['voicevoxPitch'] as num?)?.toDouble() ?? d.voicevoxPitch,
      voicevoxIntonation:
          (json['voicevoxIntonation'] as num?)?.toDouble() ??
          d.voicevoxIntonation,
      voicevoxVolume:
          (json['voicevoxVolume'] as num?)?.toDouble() ?? d.voicevoxVolume,
      queueLimit: json['queueLimit'] as int? ?? d.queueLimit,
      maxDelaySeconds: json['maxDelaySeconds'] as int? ?? d.maxDelaySeconds,
      omitUrl: json['omitUrl'] as bool? ?? d.omitUrl,
      suppressDuplicate:
          json['suppressDuplicate'] as bool? ?? d.suppressDuplicate,
      ngWords: json['ngWords'] as String? ?? d.ngWords,
      ngUserIds: json['ngUserIds'] as String? ?? d.ngUserIds,
      favoriteUserIds: parseFavoriteUserIds(),
      pastCommentFetchCount: PastCommentFetchCountValue.fromStorageValue(
        json['pastCommentFetchCount'] as String?,
      ),
      showUserName: json['showUserName'] as bool? ?? d.showUserName,
      resolveUserName: json['resolveUserName'] as bool? ?? d.resolveUserName,
      commentFontSize: fontSize.clamp(commentFontSizeMin, commentFontSizeMax),
      autoNicknameRegistration:
          json['autoNicknameRegistration'] as bool? ??
          d.autoNicknameRegistration,
      autoSaveCommentLog:
          json['autoSaveCommentLog'] as bool? ?? d.autoSaveCommentLog,
      autoSaveCommentLogPath:
          json['autoSaveCommentLogPath'] as String? ?? d.autoSaveCommentLogPath,
      statisticsEnabled:
          json['statisticsEnabled'] as bool? ?? d.statisticsEnabled,
      statisticsViewerCommentEnabled:
          json['statisticsViewerCommentEnabled'] as bool? ??
          d.statisticsViewerCommentEnabled,
      statisticsActiveUserEnabled:
          json['statisticsActiveUserEnabled'] as bool? ??
          d.statisticsActiveUserEnabled,
      highlightPickupEnabled:
          json['highlightPickupEnabled'] as bool? ?? d.highlightPickupEnabled,
      starPrefixHidingEnabled:
          json['starPrefixHidingEnabled'] as bool? ?? d.starPrefixHidingEnabled,
      slashPrefixSkipEnabled:
          json['slashPrefixSkipEnabled'] as bool? ?? d.slashPrefixSkipEnabled,
      readUserName: json['readUserName'] as bool? ?? d.readUserName,
      voicevoxSynthesisMode: SynthesisMode.fromStorageValue(
        json['voicevoxSynthesisMode'] as String?,
      ),
      voicevoxPlayerType:
          (json['voicevoxPlayerType'] as String?) == 'media_player'
          ? VoicevoxPlayerType.mediaPlayer
          : VoicevoxPlayerType.audioTrack,
      voicevoxTermsAccepted:
          json['voicevoxTermsAccepted'] as bool? ?? d.voicevoxTermsAccepted,
      ngWordRules: parseNgWordRules(),
      commentTwoLineEnabled:
          json['commentTwoLineEnabled'] as bool? ?? d.commentTwoLineEnabled,
      // 旧 Export ファイル（このキーが存在しない）や型不整合な値は
      // デフォルト (40%) にフォールバックし、許容範囲外の値は clamp して
      // assert に引っかからないよう安全側に倒す。`as num?` キャストは
      // String 等の不正値で失敗するため、明示的に型を判定して
      // フォールバックする。
      commentTwoLineMetaFontPercent:
          switch (json['commentTwoLineMetaFontPercent']) {
            num n => n.toInt().clamp(
              commentTwoLineMetaFontPercentMin,
              commentTwoLineMetaFontPercentMax,
            ),
            _ => d.commentTwoLineMetaFontPercent,
          },
      commentZebraStripingEnabled:
          json['commentZebraStripingEnabled'] as bool? ??
          d.commentZebraStripingEnabled,
      emphasizeGiftNicoadComment:
          json['emphasizeGiftNicoadComment'] as bool? ??
          d.emphasizeGiftNicoadComment,
      dictionaryRules: parseDictionaryRules(),
      debugMode: json['debugMode'] as bool? ?? d.debugMode,
      showOperatorComment:
          json['showOperatorComment'] as bool? ?? d.showOperatorComment,
      showSystemMessage:
          json['showSystemMessage'] as bool? ?? d.showSystemMessage,
      showEmotion: json['showEmotion'] as bool? ?? d.showEmotion,
      showGiftComment: json['showGiftComment'] as bool? ?? d.showGiftComment,
      showNicoadComment:
          json['showNicoadComment'] as bool? ?? d.showNicoadComment,
      readGiftComment: json['readGiftComment'] as bool? ?? d.readGiftComment,
      readNicoadComment:
          json['readNicoadComment'] as bool? ?? d.readNicoadComment,
      ngProtectionNotificationEnabled:
          json['ngProtectionNotificationEnabled'] as bool? ??
          d.ngProtectionNotificationEnabled,
      showViolentComment:
          json['showViolentComment'] as bool? ?? d.showViolentComment,
      showSexualComment:
          json['showSexualComment'] as bool? ?? d.showSexualComment,
      showDiscriminationComment:
          json['showDiscriminationComment'] as bool? ??
          d.showDiscriminationComment,
      showMinorsRelatedComment:
          json['showMinorsRelatedComment'] as bool? ??
          d.showMinorsRelatedComment,
      androidTtsSpeed:
          (json['androidTtsSpeed'] as num?)?.toDouble() ?? d.androidTtsSpeed,
      androidTtsPitch:
          (json['androidTtsPitch'] as num?)?.toDouble() ?? d.androidTtsPitch,
      androidTtsVolume:
          (json['androidTtsVolume'] as num?)?.toDouble() ?? d.androidTtsVolume,
      // Issue #739: 旧 Export ファイル（このキーが存在しない）を Import しても
      // 既定値 (true) で復元できる。`bool` 以外の不正値はデフォルトに
      // フォールバックして安全側に倒す（他の parse* 関数と同じ規約）。
      playRemainingAfterEnded: switch (json['playRemainingAfterEnded']) {
        bool b => b,
        _ => d.playRemainingAfterEnded,
      },
      // Issue #774: 旧 Export ファイル（このキーが存在しない）や不正値は
      // デフォルト (ascending) にフォールバックする。
      commentSortOrder: switch (json['commentSortOrder']) {
        String s => CommentSortOrderValue.fromStorageValue(s),
        _ => d.commentSortOrder,
      },
      // Issue #784: 旧 Export ファイル（このキーが存在しない）はデフォルト
      // (false) にフォールバックする。型が違う値（文字列・数値等）も同様に
      // デフォルトへ落とす — `as bool?` キャストだと `String` を読み込んだ
      // 瞬間 `TypeError` を投げて Import 全体が失敗するため、defensive な
      // switch で受ける（commentSortOrder と同じ流儀）。
      showCommentNo: switch (json['showCommentNo']) {
        bool b => b,
        _ => d.showCommentNo,
      },
    );
  }

  /// Converts a JSON string to [AppSettings].
  ///
  /// Throws [FormatException] if the string is not valid JSON or not a
  /// JSON object.
  static AppSettings fromJsonString(String jsonString) {
    final Object? decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Invalid settings JSON: expected a JSON object',
      );
    }
    return fromJson(decoded);
  }

  /// Convert to [SpeechSettings] for the platform speech engine.
  SpeechSettings toSpeechSettings() => SpeechSettings(
    enabled: autoReadEnabled,
    engineType: speechEngine == SpeechEngine.androidTts
        ? SpeechEngineType.androidTts
        : SpeechEngineType.voicevox,
    synthesisMode: voicevoxSynthesisMode,
    speakerId: voicevoxSpeaker,
    speedScale: voicevoxSpeed,
    pitchScale: voicevoxPitch,
    intonationScale: voicevoxIntonation,
    volumeScale: voicevoxVolume,
    maxQueueSize: queueLimit,
    ngWords: ngWordList,
    dictionaryRules: dictionaryRules,
    playerType: voicevoxPlayerType == VoicevoxPlayerType.mediaPlayer
        ? 'media_player'
        : 'audio_track',
    androidTtsSpeed: androidTtsSpeed,
    androidTtsPitch: androidTtsPitch,
    androidTtsVolume: androidTtsVolume,
  );
}

SpeechEngine _parseSpeechEngine(String? raw) {
  switch (raw) {
    case 'androidTts':
      return SpeechEngine.androidTts;
    case 'voicevox':
    default:
      return SpeechEngine.voicevox;
  }
}
