import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:path_provider/path_provider.dart';

import '../../comment_speech/src/models/replace_rule.dart';
import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_word_rule.dart';
import '../filter/legacy_ng_parser.dart';

abstract class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);

  /// Load the VOICEVOX volume stored before muting. Returns `null` if not
  /// muted on the VOICEVOX engine.
  double? loadPreMuteVolume();

  /// Save the VOICEVOX volume before muting. Pass `null` to clear.
  Future<void> savePreMuteVolume(double? volume);

  /// Load the Android TTS volume stored before muting. Returns `null` if not
  /// muted on the Android TTS engine. Stored separately from the VOICEVOX
  /// pre-mute slot so that switching engines while muted does not lose the
  /// other engine's pre-mute value (Issue #697).
  double? loadPreMuteAndroidTtsVolume();

  /// Save the Android TTS volume before muting. Pass `null` to clear.
  Future<void> savePreMuteAndroidTtsVolume(double? volume);

  /// Exports current settings as a pretty-printed JSON string.
  Future<String> exportAsJson();

  /// Writes the current settings as JSON to a temporary file and returns
  /// the written file path.
  ///
  /// Intended for use with the system share sheet so the user can choose
  /// an external destination (Files / Drive / etc.).  The file extension
  /// is always `.json`.
  ///
  /// Mirrors the naming convention of
  /// `FileCommentLogWriter.writeToTempFile` for consistency.
  Future<String> writeExportToTempFile();

  /// Imports settings from a JSON string, saves them, and returns the result.
  ///
  /// Throws [FormatException] if [jsonString] is not valid JSON.
  Future<AppSettings> importFromJson(String jsonString);
}

/// Constants and helpers describing the settings export file produced by
/// [SettingsStore.writeExportToTempFile].  Exposes the MIME type plus the
/// timestamped file name generator / matcher so the presentation and
/// data layers agree on the on-disk and shared file name without
/// re-declaring string literals.
class SettingsExport {
  const SettingsExport._();

  /// File name prefix used for timestamped exports.  Also used to match
  /// previously-written temp files for cleanup.
  static const String _fileNamePrefix = 'comerune-settings_';

  /// File extension for the exported file.
  static const String _fileExtension = '.json';

  /// MIME type of the exported file.  Passed to `XFile` when sharing.
  static const String mimeType = 'application/json';

  /// Regex matching timestamped export file names produced by
  /// [timestampedFileName].  Exposed for tests and cleanup logic.
  /// Derived from [_fileNamePrefix] / [_fileExtension] so the prefix and
  /// extension have a single source of truth.
  static final RegExp timestampedFileNamePattern = RegExp(
    '^${RegExp.escape(_fileNamePrefix)}'
    r'\d{8}_\d{6}'
    '${RegExp.escape(_fileExtension)}\$',
  );

  /// Builds a timestamped file name based on local time [now].
  ///
  /// Example: `comerune-settings_20260418_000123.json`.
  static String timestampedFileName(DateTime now) {
    final DateTime local = now.toLocal();
    String pad2(int v) => v.toString().padLeft(2, '0');
    final String timestamp =
        '${local.year.toString().padLeft(4, '0')}'
        '${pad2(local.month)}${pad2(local.day)}'
        '_${pad2(local.hour)}${pad2(local.minute)}${pad2(local.second)}';
    return '$_fileNamePrefix$timestamp$_fileExtension';
  }
}

/// SharedPreferences API のうち本画面で利用する最小セット。
///
/// 実運用では `shared_preferences` の実体をこのインターフェースに
/// 適合するアダプタ経由で渡す想定。
abstract class SharedPreferencesLike {
  bool? getBool(String key);

  int? getInt(String key);

  double? getDouble(String key);

  String? getString(String key);

  Future<bool> setBool(String key, bool value);

  Future<bool> setInt(String key, int value);

  Future<bool> setDouble(String key, double value);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  const SharedPreferencesSettingsStore({
    required SharedPreferencesLike prefs,
    Directory? tempDirectory,
    BroadcasterNgStore? broadcasterNgStore,
  }) : _prefs = prefs,
       _tempDirectory = tempDirectory,
       _broadcasterNgStore = broadcasterNgStore;

  final SharedPreferencesLike _prefs;

  /// Temp directory used by [writeExportToTempFile].  When null, falls back
  /// to `path_provider`'s `getTemporaryDirectory()` at call time.
  final Directory? _tempDirectory;

  /// Issue #727: optional integration. When provided, settings export adds
  /// a `broadcasterNgFilter` block describing the template + per-broadcaster
  /// NG layout, and import understands the same block. When null (older
  /// host scenarios / tests that do not need the NG layout), export skips
  /// the new key and import behaves like before.
  final BroadcasterNgStore? _broadcasterNgStore;

  /// Top-level export key carrying the per-broadcaster NG layout.
  /// Documented as a public constant so tests can reference the same
  /// string and the importer can detect "new schema present" without
  /// re-declaring the literal.
  static const String exportBroadcasterNgKey = 'broadcasterNgFilter';

  /// Schema version for [exportBroadcasterNgKey]. Bumped only when the
  /// JSON shape changes incompatibly. Unknown versions are still
  /// applied best-effort with a warning so newer-than-app exports do
  /// not silently drop NG state.
  static const int broadcasterNgFilterSchemaVersion = 1;

  static const String _kThemeMode = 'settings.themeMode';
  static const String _kAutoReadEnabled = 'settings.autoReadEnabled';
  static const String _kSpeechEngine = 'settings.speechEngine';
  static const String _kVoicevoxSpeaker = 'settings.voicevox.speaker';
  static const String _kVoicevoxSpeed = 'settings.voicevox.speedScale';
  static const String _kVoicevoxPitch = 'settings.voicevox.pitchScale';
  static const String _kVoicevoxIntonation =
      'settings.voicevox.intonationScale';
  static const String _kVoicevoxVolume = 'settings.voicevox.volumeScale';
  static const String _kQueueLimit = 'settings.queue.limit';
  static const String _kMaxDelaySeconds = 'settings.queue.maxDelaySeconds';
  static const String _kOmitUrl = 'settings.filter.omitUrl';
  static const String _kSuppressDuplicate = 'settings.filter.suppressDuplicate';
  static const String _kNgWords = 'settings.filter.ngWords';
  static const String _kNgUserIds = 'settings.filter.ngUserIds';
  static const String _kFavoriteUserIds = 'settings.favoriteUserIds';
  static const String _kPastCommentFetchCount =
      'settings.comment.pastFetchCount';
  static const String _kShowUserName = 'settings.comment.showUserName';
  static const String _kResolveUserName = 'settings.comment.resolveUserName';
  static const String _kCommentFontSize = 'settings.comment.fontSize';
  static const String _kAutoNicknameRegistration =
      'settings.comment.autoNicknameRegistration';
  static const String _kAutoSaveCommentLog =
      'settings.comment.autoSaveCommentLog';
  static const String _kAutoSaveCommentLogPath =
      'settings.comment.autoSaveCommentLogPath';
  static const String _kStatisticsEnabled = 'settings.statistics.enabled';
  static const String _kStatisticsViewerCommentEnabled =
      'settings.statistics.viewerComment';
  static const String _kStatisticsActiveUserEnabled =
      'settings.statistics.activeUser';
  static const String _kHighlightPickupEnabled =
      'settings.statistics.highlightPickup';
  static const String _kStarPrefixHidingEnabled =
      'settings.filter.starPrefixHiding';
  static const String _kSlashPrefixSkipEnabled =
      'settings.filter.slashPrefixSkip';
  static const String _kReadUserName = 'settings.tts.readUserName';
  static const String _kVoicevoxSynthesisMode =
      'settings.voicevox.synthesisMode';
  static const String _kVoicevoxPlayerType = 'settings.voicevox.playerType';
  static const String _kVoicevoxTermsAccepted =
      'settings.voicevox.termsAccepted';
  static const String _kNgWordRules = 'settings.filter.ngWordRules';
  static const String _kCommentTwoLineEnabled = 'settings.comment.twoLine';
  static const String _kCommentTwoLineMetaFontPercent =
      'settings.comment.twoLineMetaFontPercent';
  static const String _kCommentZebraStriping = 'settings.comment.zebraStriping';
  static const String _kShowOperatorComment = 'settings.comment.showOperator';
  static const String _kShowSystemMessage = 'settings.comment.showSystem';
  static const String _kShowEmotion = 'settings.comment.showEmotion';
  static const String _kShowGiftComment = 'settings.comment.showGift';
  static const String _kShowNicoadComment = 'settings.comment.showNicoad';
  static const String _kReadGiftComment = 'settings.tts.readGift';
  static const String _kReadNicoadComment = 'settings.tts.readNicoad';
  static const String _kEmphasizeGiftNicoadComment =
      'settings.comment.emphasizeGiftNicoad';
  static const String _kDictionaryRules = 'settings.speech.dictionaryRules';
  static const String _kDebugMode = 'settings.debugMode';
  static const String _kNgProtectionNotificationEnabled =
      'settings.ngFilter.protectionNotification';
  static const String _kShowViolentComment =
      'settings.comment.showViolentComment';
  static const String _kShowSexualComment =
      'settings.comment.showSexualComment';
  static const String _kShowDiscriminationComment =
      'settings.comment.showDiscriminationComment';
  static const String _kShowMinorsRelatedComment =
      'settings.comment.showMinorsRelatedComment';
  // Pre-mute volume slots are intentionally NOT included in
  // [exportAsJson] / [importFromJson] — they are transient device-local
  // mute state, not user-authored configuration. Restoring an old export
  // must not silently mute the user (Issue #697 cycle-2 review).
  static const String _kPreMuteVolume = 'settings.voicevox.preMuteVolume';
  static const String _kAndroidTtsSpeed = 'settings.androidTts.speed';
  static const String _kAndroidTtsPitch = 'settings.androidTts.pitch';
  static const String _kAndroidTtsVolume = 'settings.androidTts.volume';
  static const String _kPreMuteAndroidTtsVolume =
      'settings.androidTts.preMuteVolume';
  // Issue #739: ended grace 期間中も読み上げを継続するか。
  static const String _kPlayRemainingAfterEnded =
      'settings.tts.playRemainingAfterEnded';
  // Issue #774: コメント画面のスクロール方向（昇順/降順）の永続化キー。
  static const String _kCommentSortOrder = 'settings.comment.sortOrder';
  // Issue #784: コメント番号 (NDGR `Chat.no`) の表示 ON/OFF の永続化キー。
  static const String _kShowCommentNo = 'settings.comment.showCommentNo';

  @override
  Future<AppSettings> load() async {
    const AppSettings defaults = AppSettings.defaults;
    final String? engineValue = _prefs.getString(_kSpeechEngine);
    final SpeechEngine speechEngine;
    switch (engineValue) {
      case 'androidTts':
        speechEngine = SpeechEngine.androidTts;
      default:
        speechEngine = SpeechEngine.voicevox;
    }

    return AppSettings(
      themeMode: AppThemeModeValue.fromStorageValue(
        _prefs.getString(_kThemeMode),
      ),
      autoReadEnabled:
          _prefs.getBool(_kAutoReadEnabled) ?? defaults.autoReadEnabled,
      speechEngine: speechEngine,
      voicevoxSpeaker:
          _prefs.getInt(_kVoicevoxSpeaker) ?? defaults.voicevoxSpeaker,
      voicevoxSpeed:
          _prefs.getDouble(_kVoicevoxSpeed) ?? defaults.voicevoxSpeed,
      voicevoxPitch:
          _prefs.getDouble(_kVoicevoxPitch) ?? defaults.voicevoxPitch,
      voicevoxIntonation:
          _prefs.getDouble(_kVoicevoxIntonation) ?? defaults.voicevoxIntonation,
      voicevoxVolume:
          _prefs.getDouble(_kVoicevoxVolume) ?? defaults.voicevoxVolume,
      queueLimit: _prefs.getInt(_kQueueLimit) ?? defaults.queueLimit,
      maxDelaySeconds:
          _prefs.getInt(_kMaxDelaySeconds) ?? defaults.maxDelaySeconds,
      omitUrl: _prefs.getBool(_kOmitUrl) ?? defaults.omitUrl,
      suppressDuplicate:
          _prefs.getBool(_kSuppressDuplicate) ?? defaults.suppressDuplicate,
      ngWords: _prefs.getString(_kNgWords) ?? defaults.ngWords,
      ngUserIds: _prefs.getString(_kNgUserIds) ?? defaults.ngUserIds,
      favoriteUserIds:
          _prefs.getString(_kFavoriteUserIds) ?? defaults.favoriteUserIds,
      pastCommentFetchCount: PastCommentFetchCountValue.fromStorageValue(
        _prefs.getString(_kPastCommentFetchCount),
      ),
      showUserName: _prefs.getBool(_kShowUserName) ?? defaults.showUserName,
      resolveUserName:
          _prefs.getBool(_kResolveUserName) ?? defaults.resolveUserName,
      commentFontSize: commentFontSizeFromStorageValue(
        _prefs.getString(_kCommentFontSize),
      ),
      autoNicknameRegistration:
          _prefs.getBool(_kAutoNicknameRegistration) ??
          defaults.autoNicknameRegistration,
      autoSaveCommentLog:
          _prefs.getBool(_kAutoSaveCommentLog) ?? defaults.autoSaveCommentLog,
      autoSaveCommentLogPath:
          _prefs.getString(_kAutoSaveCommentLogPath) ??
          defaults.autoSaveCommentLogPath,
      statisticsEnabled:
          _prefs.getBool(_kStatisticsEnabled) ?? defaults.statisticsEnabled,
      statisticsViewerCommentEnabled:
          _prefs.getBool(_kStatisticsViewerCommentEnabled) ??
          defaults.statisticsViewerCommentEnabled,
      statisticsActiveUserEnabled:
          _prefs.getBool(_kStatisticsActiveUserEnabled) ??
          defaults.statisticsActiveUserEnabled,
      highlightPickupEnabled:
          _prefs.getBool(_kHighlightPickupEnabled) ??
          defaults.highlightPickupEnabled,
      starPrefixHidingEnabled:
          _prefs.getBool(_kStarPrefixHidingEnabled) ??
          defaults.starPrefixHidingEnabled,
      slashPrefixSkipEnabled:
          _prefs.getBool(_kSlashPrefixSkipEnabled) ??
          defaults.slashPrefixSkipEnabled,
      readUserName: _prefs.getBool(_kReadUserName) ?? defaults.readUserName,
      voicevoxSynthesisMode: SynthesisMode.fromStorageValue(
        _prefs.getString(_kVoicevoxSynthesisMode),
      ),
      voicevoxPlayerType:
          _prefs.getString(_kVoicevoxPlayerType) == 'media_player'
          ? VoicevoxPlayerType.mediaPlayer
          : VoicevoxPlayerType.audioTrack,
      voicevoxTermsAccepted:
          _prefs.getBool(_kVoicevoxTermsAccepted) ??
          defaults.voicevoxTermsAccepted,
      ngWordRules: _loadNgWordRules(),
      commentTwoLineEnabled:
          _prefs.getBool(_kCommentTwoLineEnabled) ??
          defaults.commentTwoLineEnabled,
      // 既存ユーザー（このキー未設定）は従来挙動と同じ 40% で復元する。
      // 不正値（範囲外）は clamp して AppSettings の assert を通すようにする。
      commentTwoLineMetaFontPercent:
          (_prefs.getInt(_kCommentTwoLineMetaFontPercent) ??
                  defaults.commentTwoLineMetaFontPercent)
              .clamp(
                commentTwoLineMetaFontPercentMin,
                commentTwoLineMetaFontPercentMax,
              ),
      commentZebraStripingEnabled:
          _prefs.getBool(_kCommentZebraStriping) ??
          defaults.commentZebraStripingEnabled,
      emphasizeGiftNicoadComment:
          _prefs.getBool(_kEmphasizeGiftNicoadComment) ??
          defaults.emphasizeGiftNicoadComment,
      dictionaryRules: _loadDictionaryRules(),
      debugMode: _prefs.getBool(_kDebugMode) ?? defaults.debugMode,
      showOperatorComment:
          _prefs.getBool(_kShowOperatorComment) ?? defaults.showOperatorComment,
      showSystemMessage:
          _prefs.getBool(_kShowSystemMessage) ?? defaults.showSystemMessage,
      showEmotion: _prefs.getBool(_kShowEmotion) ?? defaults.showEmotion,
      showGiftComment:
          _prefs.getBool(_kShowGiftComment) ?? defaults.showGiftComment,
      showNicoadComment:
          _prefs.getBool(_kShowNicoadComment) ?? defaults.showNicoadComment,
      readGiftComment:
          _prefs.getBool(_kReadGiftComment) ?? defaults.readGiftComment,
      readNicoadComment:
          _prefs.getBool(_kReadNicoadComment) ?? defaults.readNicoadComment,
      ngProtectionNotificationEnabled:
          _prefs.getBool(_kNgProtectionNotificationEnabled) ??
          defaults.ngProtectionNotificationEnabled,
      showViolentComment:
          _prefs.getBool(_kShowViolentComment) ?? defaults.showViolentComment,
      showSexualComment:
          _prefs.getBool(_kShowSexualComment) ?? defaults.showSexualComment,
      showDiscriminationComment:
          _prefs.getBool(_kShowDiscriminationComment) ??
          defaults.showDiscriminationComment,
      showMinorsRelatedComment:
          _prefs.getBool(_kShowMinorsRelatedComment) ??
          defaults.showMinorsRelatedComment,
      androidTtsSpeed:
          _prefs.getDouble(_kAndroidTtsSpeed) ?? defaults.androidTtsSpeed,
      androidTtsPitch:
          _prefs.getDouble(_kAndroidTtsPitch) ?? defaults.androidTtsPitch,
      androidTtsVolume:
          _prefs.getDouble(_kAndroidTtsVolume) ?? defaults.androidTtsVolume,
      playRemainingAfterEnded:
          _prefs.getBool(_kPlayRemainingAfterEnded) ??
          defaults.playRemainingAfterEnded,
      commentSortOrder: CommentSortOrderValue.fromStorageValue(
        _prefs.getString(_kCommentSortOrder),
      ),
      showCommentNo: _prefs.getBool(_kShowCommentNo) ?? defaults.showCommentNo,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_kThemeMode, settings.themeMode.storageValue);
    await _prefs.setBool(_kAutoReadEnabled, settings.autoReadEnabled);
    await _prefs.setString(_kSpeechEngine, settings.speechEngine.name);
    await _prefs.setInt(_kVoicevoxSpeaker, settings.voicevoxSpeaker);
    await _prefs.setDouble(_kVoicevoxSpeed, settings.voicevoxSpeed);
    await _prefs.setDouble(_kVoicevoxPitch, settings.voicevoxPitch);
    await _prefs.setDouble(_kVoicevoxIntonation, settings.voicevoxIntonation);
    await _prefs.setDouble(_kVoicevoxVolume, settings.voicevoxVolume);
    await _prefs.setInt(_kQueueLimit, settings.queueLimit);
    await _prefs.setInt(_kMaxDelaySeconds, settings.maxDelaySeconds);
    await _prefs.setBool(_kOmitUrl, settings.omitUrl);
    await _prefs.setBool(_kSuppressDuplicate, settings.suppressDuplicate);
    await _prefs.setString(_kNgWords, settings.ngWords);
    await _prefs.setString(_kNgUserIds, settings.ngUserIds);
    await _prefs.setString(_kFavoriteUserIds, settings.favoriteUserIds);
    await _prefs.setString(
      _kPastCommentFetchCount,
      settings.pastCommentFetchCount.storageValue,
    );
    await _prefs.setBool(_kShowUserName, settings.showUserName);
    await _prefs.setBool(_kResolveUserName, settings.resolveUserName);
    await _prefs.setString(
      _kCommentFontSize,
      settings.commentFontSize.toString(),
    );
    await _prefs.setBool(
      _kAutoNicknameRegistration,
      settings.autoNicknameRegistration,
    );
    await _prefs.setBool(_kAutoSaveCommentLog, settings.autoSaveCommentLog);
    await _prefs.setString(
      _kAutoSaveCommentLogPath,
      settings.autoSaveCommentLogPath,
    );
    await _prefs.setBool(_kStatisticsEnabled, settings.statisticsEnabled);
    await _prefs.setBool(
      _kStatisticsViewerCommentEnabled,
      settings.statisticsViewerCommentEnabled,
    );
    await _prefs.setBool(
      _kStatisticsActiveUserEnabled,
      settings.statisticsActiveUserEnabled,
    );
    await _prefs.setBool(
      _kHighlightPickupEnabled,
      settings.highlightPickupEnabled,
    );
    await _prefs.setBool(
      _kStarPrefixHidingEnabled,
      settings.starPrefixHidingEnabled,
    );
    await _prefs.setBool(
      _kSlashPrefixSkipEnabled,
      settings.slashPrefixSkipEnabled,
    );
    await _prefs.setBool(_kReadUserName, settings.readUserName);
    await _prefs.setString(
      _kVoicevoxSynthesisMode,
      settings.voicevoxSynthesisMode.storageValue,
    );
    await _prefs.setString(
      _kVoicevoxPlayerType,
      settings.voicevoxPlayerType == VoicevoxPlayerType.mediaPlayer
          ? 'media_player'
          : 'audio_track',
    );
    await _prefs.setBool(
      _kVoicevoxTermsAccepted,
      settings.voicevoxTermsAccepted,
    );
    await _prefs.setBool(
      _kCommentTwoLineEnabled,
      settings.commentTwoLineEnabled,
    );
    await _prefs.setInt(
      _kCommentTwoLineMetaFontPercent,
      settings.commentTwoLineMetaFontPercent,
    );
    await _prefs.setBool(
      _kCommentZebraStriping,
      settings.commentZebraStripingEnabled,
    );
    await _prefs.setBool(
      _kEmphasizeGiftNicoadComment,
      settings.emphasizeGiftNicoadComment,
    );
    await _prefs.setBool(_kDebugMode, settings.debugMode);
    await _prefs.setBool(_kShowOperatorComment, settings.showOperatorComment);
    await _prefs.setBool(_kShowSystemMessage, settings.showSystemMessage);
    await _prefs.setBool(_kShowEmotion, settings.showEmotion);
    await _prefs.setBool(_kShowGiftComment, settings.showGiftComment);
    await _prefs.setBool(_kShowNicoadComment, settings.showNicoadComment);
    await _prefs.setBool(_kReadGiftComment, settings.readGiftComment);
    await _prefs.setBool(_kReadNicoadComment, settings.readNicoadComment);
    await _prefs.setBool(
      _kNgProtectionNotificationEnabled,
      settings.ngProtectionNotificationEnabled,
    );
    await _prefs.setBool(_kShowViolentComment, settings.showViolentComment);
    await _prefs.setBool(_kShowSexualComment, settings.showSexualComment);
    await _prefs.setBool(
      _kShowDiscriminationComment,
      settings.showDiscriminationComment,
    );
    await _prefs.setBool(
      _kShowMinorsRelatedComment,
      settings.showMinorsRelatedComment,
    );
    await _prefs.setString(
      _kNgWordRules,
      jsonEncode(
        settings.ngWordRules.map((NgWordRule r) => r.toMap()).toList(),
      ),
    );
    await _prefs.setString(
      _kDictionaryRules,
      jsonEncode(
        settings.dictionaryRules.map((ReplaceRule r) => r.toMap()).toList(),
      ),
    );
    await _prefs.setDouble(_kAndroidTtsSpeed, settings.androidTtsSpeed);
    await _prefs.setDouble(_kAndroidTtsPitch, settings.androidTtsPitch);
    await _prefs.setDouble(_kAndroidTtsVolume, settings.androidTtsVolume);
    await _prefs.setBool(
      _kPlayRemainingAfterEnded,
      settings.playRemainingAfterEnded,
    );
    await _prefs.setString(
      _kCommentSortOrder,
      settings.commentSortOrder.storageValue,
    );
    await _prefs.setBool(_kShowCommentNo, settings.showCommentNo);
  }

  List<NgWordRule> _loadNgWordRules() {
    final String? raw = _prefs.getString(_kNgWordRules);
    if (raw == null) {
      return const <NgWordRule>[];
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic e) => NgWordRule.fromMap(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e) {
      developer.log(
        'Failed to parse ngWordRules, returning empty list: $e',
        name: 'SettingsStore',
      );
      return const <NgWordRule>[];
    }
  }

  @override
  double? loadPreMuteVolume() => _prefs.getDouble(_kPreMuteVolume);

  @override
  Future<void> savePreMuteVolume(double? volume) async {
    if (volume == null) {
      await _prefs.remove(_kPreMuteVolume);
    } else {
      await _prefs.setDouble(_kPreMuteVolume, volume);
    }
  }

  @override
  double? loadPreMuteAndroidTtsVolume() =>
      _prefs.getDouble(_kPreMuteAndroidTtsVolume);

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) async {
    if (volume == null) {
      await _prefs.remove(_kPreMuteAndroidTtsVolume);
    } else {
      await _prefs.setDouble(_kPreMuteAndroidTtsVolume, volume);
    }
  }

  List<ReplaceRule> _loadDictionaryRules() {
    final String? raw = _prefs.getString(_kDictionaryRules);
    if (raw == null) {
      return defaultNicoDictionaryRules;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((dynamic e) => ReplaceRule.fromMap(e as Map<String, dynamic>))
          .toList();
    } on Object catch (e) {
      developer.log(
        'Failed to parse dictionaryRules, falling back to defaults: $e',
        name: 'SettingsStore',
      );
      return defaultNicoDictionaryRules;
    }
  }

  @override
  Future<String> exportAsJson() async {
    final AppSettings settings = await load();
    final Map<String, dynamic> json = settings.toJson();
    final Map<String, dynamic>? ngBlock = await _buildBroadcasterNgExport();
    if (ngBlock != null) {
      json[exportBroadcasterNgKey] = ngBlock;
    }
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
  }

  /// Builds the `broadcasterNgFilter` JSON block from the current
  /// [BroadcasterNgStore] snapshot. Returns null when no store is wired
  /// — older host scenarios / tests that do not exercise the NG layout
  /// must still produce a valid export without the new key.
  ///
  /// Failures while reading individual broadcaster slots are logged and
  /// the offending slot is skipped — a single malformed slot must not
  /// abort the whole export.
  Future<Map<String, dynamic>?> _buildBroadcasterNgExport() async {
    final BroadcasterNgStore? store = _broadcasterNgStore;
    if (store == null) {
      return null;
    }
    final Set<String> templateIds = await store.loadTemplateNgUserIds();
    final List<NgWordRule> templateRules = await store
        .loadTemplateNgWordRules();

    final Map<String, dynamic> broadcasters = <String, dynamic>{};
    for (final String id in store.listBroadcasters()) {
      if (id.isEmpty) {
        continue;
      }
      try {
        final BroadcasterNgPayload payload = await store
            .loadBroadcasterNgAttributes(id);
        broadcasters[id] = <String, dynamic>{
          'ngUserIds': payload.ngUserIds.toList(),
          'ngWordRules': payload.rules
              .map((NgWordRule r) => r.toMap())
              .toList(),
        };
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to read NG slot for export; skipping one broadcaster: '
          '$error',
          name: 'SettingsStore',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return <String, dynamic>{
      'version': broadcasterNgFilterSchemaVersion,
      'template': <String, dynamic>{
        'ngUserIds': templateIds.toList(),
        'ngWordRules': templateRules.map((NgWordRule r) => r.toMap()).toList(),
      },
      'broadcasters': broadcasters,
    };
  }

  @override
  Future<String> writeExportToTempFile() async {
    final Directory dir = _tempDirectory ?? await getTemporaryDirectory();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await _removePreviousTimestampedExports(dir);
    final String json = await exportAsJson();
    final String name = SettingsExport.timestampedFileName(clock.now());
    final File file = File('${dir.path}/$name');
    await file.writeAsString(json, flush: true);
    return file.path;
  }

  /// Removes previously-written timestamped export files in [dir] so the
  /// temp directory does not accumulate stale copies across repeated
  /// exports.  Failures are logged and swallowed — stale temp files are
  /// harmless and must not block a fresh export.
  Future<void> _removePreviousTimestampedExports(Directory dir) async {
    try {
      await for (final FileSystemEntity entry in dir.list(followLinks: false)) {
        if (entry is! File) {
          continue;
        }
        final String base = entry.uri.pathSegments.isEmpty
            ? ''
            : entry.uri.pathSegments.last;
        if (SettingsExport.timestampedFileNamePattern.hasMatch(base)) {
          try {
            await entry.delete();
          } on FileSystemException catch (e) {
            developer.log(
              'Failed to delete stale export file ${entry.path}: $e',
              name: 'SettingsStore',
            );
          }
        }
      }
    } on FileSystemException catch (e) {
      developer.log(
        'Failed to scan temp directory for stale exports: $e',
        name: 'SettingsStore',
      );
    }
  }

  @override
  Future<AppSettings> importFromJson(String jsonString) async {
    // Parse legacy fields via AppSettings (unknown keys are ignored, so the
    // new `broadcasterNgFilter` block falls through unharmed).
    final AppSettings imported = AppSettings.fromJsonString(jsonString);
    await save(imported);

    // Re-parse the same JSON to inspect the optional `broadcasterNgFilter`
    // block at the top level. AppSettings.fromJson already discarded it, so
    // we do not have access to the structured block from `imported`.
    final BroadcasterNgStore? store = _broadcasterNgStore;
    if (store == null) {
      return imported;
    }

    Map<String, dynamic>? root;
    try {
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        root = decoded;
      }
    } on Object catch (error) {
      // AppSettings.fromJsonString already validated the JSON; reaching this
      // catch means a race or non-Map top-level. Log and bail out without
      // touching the NG store.
      developer.log(
        'Failed to re-parse import JSON for broadcasterNgFilter: $error',
        name: 'SettingsStore',
      );
      return imported;
    }
    if (root == null) {
      return imported;
    }

    final Object? rawBlock = root[exportBroadcasterNgKey];
    if (rawBlock is Map<String, dynamic>) {
      // New schema present. New schema wins over legacy fields per the
      // import-precedence rule (the new key is more specific and
      // describes both template + per-broadcaster slots).
      await _applyBroadcasterNgFilterBlock(store, rawBlock);
    } else {
      // Legacy fallback: restore template + already-known broadcasters
      // from the legacy fields parsed into `imported`. Mirrors
      // BroadcasterNgMigrator's first-install behaviour.
      await _applyLegacyNgFallback(store, imported);
    }

    return imported;
  }

  /// Applies the parsed `broadcasterNgFilter` block to [store].
  ///
  /// Skips malformed inner sections (logged) instead of throwing — a
  /// single bad slot must not abort the whole import.
  Future<void> _applyBroadcasterNgFilterBlock(
    BroadcasterNgStore store,
    Map<String, dynamic> block,
  ) async {
    final Object? rawVersion = block['version'];
    if (rawVersion is int && rawVersion != broadcasterNgFilterSchemaVersion) {
      developer.log(
        'broadcasterNgFilter version $rawVersion differs from expected '
        '$broadcasterNgFilterSchemaVersion; applying best-effort.',
        name: 'SettingsStore',
      );
    }

    // Template.
    final Object? rawTemplate = block['template'];
    if (rawTemplate is Map<String, dynamic>) {
      final Set<String> templateIds = _parseNgUserIdsList(
        rawTemplate['ngUserIds'],
      );
      final List<NgWordRule> templateRules = _parseNgWordRulesList(
        rawTemplate['ngWordRules'],
      );
      try {
        await store.saveTemplateNgUserIds(templateIds);
        await store.saveTemplateNgWordRules(templateRules);
      } on Object catch (error, stackTrace) {
        developer.log(
          'Failed to apply imported NG template: $error',
          name: 'SettingsStore',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else if (rawTemplate != null) {
      developer.log(
        'broadcasterNgFilter.template is not a Map; skipping template.',
        name: 'SettingsStore',
      );
    }

    // Broadcasters.
    int applied = 0;
    final Object? rawBroadcasters = block['broadcasters'];
    if (rawBroadcasters is Map<String, dynamic>) {
      for (final MapEntry<String, dynamic> entry in rawBroadcasters.entries) {
        final String broadcasterId = entry.key;
        if (broadcasterId.isEmpty) {
          developer.log(
            'Skipping empty broadcasterId key in broadcasterNgFilter.',
            name: 'SettingsStore',
          );
          continue;
        }
        final Object? slot = entry.value;
        if (slot is! Map) {
          developer.log(
            'broadcasterNgFilter.broadcasters[$broadcasterId] is not a Map; '
            'skipping.',
            name: 'SettingsStore',
          );
          continue;
        }
        final Map<String, dynamic> typed = slot.cast<String, dynamic>();
        final Set<String> ids = _parseNgUserIdsList(typed['ngUserIds']);
        final List<NgWordRule> rules = _parseNgWordRulesList(
          typed['ngWordRules'],
        );
        try {
          await store.saveNgUserIds(broadcasterId, ids);
          await store.saveNgWordRules(broadcasterId, rules);
          applied++;
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to apply imported NG slot for one broadcaster: $error',
            name: 'SettingsStore',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    } else if (rawBroadcasters != null) {
      developer.log(
        'broadcasterNgFilter.broadcasters is not a Map; skipping all '
        'per-broadcaster slots.',
        name: 'SettingsStore',
      );
    }
    developer.log(
      'Imported broadcasterNgFilter: $applied broadcaster slot(s) applied.',
      name: 'SettingsStore',
    );
  }

  /// Legacy fallback: when the import JSON has no `broadcasterNgFilter`
  /// block, treat the legacy global NG fields as the user's prior
  /// state. Seed the template AND every already-known broadcaster slot
  /// with the legacy values so "import = restore my old NG settings
  /// everywhere" matches the user's mental model.
  ///
  /// Broadcasters that are not yet in the store's index are NOT created
  /// — this matches the migrator's "known broadcasters only" rule.
  Future<void> _applyLegacyNgFallback(
    BroadcasterNgStore store,
    AppSettings imported,
  ) async {
    final Set<String> legacyIds = imported.ngUserIdSet;
    final List<NgWordRule> legacyRules = LegacyNgParser.mergeLegacyNgWordRules(
      structuredRules: imported.ngWordRules,
      legacyNgWords: imported.ngWords,
    );

    try {
      await store.saveTemplateNgUserIds(legacyIds);
      await store.saveTemplateNgWordRules(legacyRules);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Legacy import: failed to seed NG template: $error',
        name: 'SettingsStore',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }

    int reseeded = 0;
    for (final String broadcasterId in store.listBroadcasters()) {
      if (broadcasterId.isEmpty) {
        continue;
      }
      try {
        await store.saveNgUserIds(broadcasterId, legacyIds);
        await store.saveNgWordRules(broadcasterId, legacyRules);
        reseeded++;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Legacy import: failed to reseed one broadcaster slot: $error',
          name: 'SettingsStore',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    developer.log(
      'Legacy NG import: $reseeded broadcaster slot(s) reseeded from legacy '
      'fields.',
      name: 'SettingsStore',
    );
  }

  static Set<String> _parseNgUserIdsList(Object? raw) {
    if (raw is! List) {
      return <String>{};
    }
    final Set<String> ids = <String>{};
    for (final Object? item in raw) {
      if (item is String) {
        final String trimmed = item.trim();
        if (trimmed.isNotEmpty) {
          ids.add(trimmed);
        }
      }
    }
    return ids;
  }

  static List<NgWordRule> _parseNgWordRulesList(Object? raw) {
    if (raw is! List) {
      return <NgWordRule>[];
    }
    final List<NgWordRule> rules = <NgWordRule>[];
    final Set<String> seen = <String>{};
    for (final Object? item in raw) {
      if (item is! Map) {
        continue;
      }
      try {
        final NgWordRule rule = NgWordRule.fromMap(
          item.cast<String, dynamic>(),
        );
        if (rule.pattern.isEmpty) {
          continue;
        }
        if (seen.add(rule.pattern)) {
          rules.add(rule);
        }
      } on Object catch (error) {
        developer.log(
          'Skipped malformed ngWordRules entry during import: $error',
          name: 'SettingsStore',
        );
      }
    }
    return rules;
  }
}
