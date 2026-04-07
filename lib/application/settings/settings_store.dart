import 'dart:convert';
import 'dart:developer' as developer;

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

  /// Imports settings from a JSON string, saves them, and returns the result.
  ///
  /// Throws [FormatException] if [jsonString] is not valid JSON.
  Future<AppSettings> importFromJson(String jsonString);
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
  const SharedPreferencesSettingsStore({required SharedPreferencesLike prefs})
    : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _kThemeMode = 'settings.themeMode';
  static const String _kAutoReadEnabled = 'settings.autoReadEnabled';
  static const String _kSpeechEngine = 'settings.speechEngine';
  static const String _kBouyomiHost = 'settings.bouyomi.host';
  static const String _kBouyomiSpeed = 'settings.bouyomi.speed';
  static const String _kBouyomiTone = 'settings.bouyomi.tone';
  static const String _kBouyomiVolume = 'settings.bouyomi.volume';
  static const String _kBouyomiVoice = 'settings.bouyomi.voice';
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
  static const String _kDictionaryRules = 'settings.speech.dictionaryRules';
  static const String _kDebugMode = 'settings.debugMode';
  static const String _kPreMuteVolume = 'settings.voicevox.preMuteVolume';

  @override
  Future<AppSettings> load() async {
    const AppSettings defaults = AppSettings.defaults;
    final String? engineValue = _prefs.getString(_kSpeechEngine);
    final SpeechEngine speechEngine = engineValue == 'bouyomi'
        ? SpeechEngine.bouyomi
        : SpeechEngine.voicevox;

    return AppSettings(
      themeMode: AppThemeModeValue.fromStorageValue(
        _prefs.getString(_kThemeMode),
      ),
      autoReadEnabled:
          _prefs.getBool(_kAutoReadEnabled) ?? defaults.autoReadEnabled,
      speechEngine: speechEngine,
      bouyomiHost: _prefs.getString(_kBouyomiHost) ?? defaults.bouyomiHost,
      bouyomiSpeed: _prefs.getInt(_kBouyomiSpeed) ?? defaults.bouyomiSpeed,
      bouyomiTone: _prefs.getInt(_kBouyomiTone) ?? defaults.bouyomiTone,
      bouyomiVolume: _prefs.getInt(_kBouyomiVolume) ?? defaults.bouyomiVolume,
      bouyomiVoice: _prefs.getInt(_kBouyomiVoice) ?? defaults.bouyomiVoice,
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
      dictionaryRules: _loadDictionaryRules(),
      debugMode: _prefs.getBool(_kDebugMode) ?? defaults.debugMode,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _prefs.setString(_kThemeMode, settings.themeMode.storageValue);
    await _prefs.setBool(_kAutoReadEnabled, settings.autoReadEnabled);
    await _prefs.setString(
      _kSpeechEngine,
      settings.speechEngine == SpeechEngine.voicevox ? 'voicevox' : 'bouyomi',
    );
    await _prefs.setString(_kBouyomiHost, settings.bouyomiHost);
    await _prefs.setInt(_kBouyomiSpeed, settings.bouyomiSpeed);
    await _prefs.setInt(_kBouyomiTone, settings.bouyomiTone);
    await _prefs.setInt(_kBouyomiVolume, settings.bouyomiVolume);
    await _prefs.setInt(_kBouyomiVoice, settings.bouyomiVoice);
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
    await _prefs.setBool(_kDebugMode, settings.debugMode);
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
  Future<AppSettings> importFromJson(String jsonString) async {
    final AppSettings imported = AppSettings.fromJsonString(jsonString);
    await save(imported);
    return imported;
  }
}
