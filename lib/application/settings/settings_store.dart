import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:path_provider/path_provider.dart';

import '../../comment_speech/src/models/replace_rule.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_word_rule.dart';

abstract class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);

  /// Load the volume stored before muting. Returns `null` if not muted.
  double? loadPreMuteVolume();

  /// Save the volume before muting. Pass `null` to clear.
  Future<void> savePreMuteVolume(double? volume);

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
  }) : _prefs = prefs,
       _tempDirectory = tempDirectory;

  final SharedPreferencesLike _prefs;

  /// Temp directory used by [writeExportToTempFile].  When null, falls back
  /// to `path_provider`'s `getTemporaryDirectory()` at call time.
  final Directory? _tempDirectory;

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
  static const String _kPreMuteVolume = 'settings.voicevox.preMuteVolume';
  static const String _kAndroidTtsSpeed = 'settings.androidTts.speed';
  static const String _kAndroidTtsPitch = 'settings.androidTts.pitch';
  static const String _kAndroidTtsVolume = 'settings.androidTts.volume';

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
    const JsonEncoder encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(json);
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
    final AppSettings imported = AppSettings.fromJsonString(jsonString);
    await save(imported);
    return imported;
  }
}
