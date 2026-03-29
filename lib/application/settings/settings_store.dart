import '../../domain/models/app_settings.dart';

abstract class SettingsStore {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
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
  static const String _kAutoSaveCommentLog =
      'settings.comment.autoSaveCommentLog';
  static const String _kDebugMode = 'settings.debugMode';

  @override
  Future<AppSettings> load() async {
    const AppSettings defaults = AppSettings.defaults;
    final String? engineValue = _prefs.getString(_kSpeechEngine);
    final SpeechEngine speechEngine = engineValue == 'voicevox'
        ? SpeechEngine.voicevox
        : SpeechEngine.bouyomi;

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
      autoSaveCommentLog:
          _prefs.getBool(_kAutoSaveCommentLog) ?? defaults.autoSaveCommentLog,
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
    await _prefs.setBool(_kAutoSaveCommentLog, settings.autoSaveCommentLog);
    await _prefs.setBool(_kDebugMode, settings.debugMode);
  }
}
