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
  static const String _kVoicevoxIntonation = 'settings.voicevox.intonationScale';
  static const String _kVoicevoxVolume = 'settings.voicevox.volumeScale';
  static const String _kQueueLimit = 'settings.queue.limit';
  static const String _kMaxDelaySeconds = 'settings.queue.maxDelaySeconds';
  static const String _kOmitUrl = 'settings.filter.omitUrl';
  static const String _kSuppressDuplicate = 'settings.filter.suppressDuplicate';
  static const String _kNgWords = 'settings.filter.ngWords';
  static const String _kPastCommentFetchCount = 'settings.comment.pastFetchCount';
  static const String _kDebugMode = 'settings.debugMode';

  @override
  Future<AppSettings> load() async {
    final AppSettings defaults = AppSettings.defaults;
    final String? engineValue = _prefs.getString(_kSpeechEngine);
    final SpeechEngine speechEngine = engineValue == 'voicevox'
        ? SpeechEngine.voicevox
        : SpeechEngine.bouyomi;

    return AppSettings(
      autoReadEnabled: _prefs.getBool(_kAutoReadEnabled) ?? defaults.autoReadEnabled,
      speechEngine: speechEngine,
      bouyomiHost: _prefs.getString(_kBouyomiHost) ?? defaults.bouyomiHost,
      bouyomiSpeed: _prefs.getInt(_kBouyomiSpeed) ?? defaults.bouyomiSpeed,
      bouyomiTone: _prefs.getInt(_kBouyomiTone) ?? defaults.bouyomiTone,
      bouyomiVolume: _prefs.getInt(_kBouyomiVolume) ?? defaults.bouyomiVolume,
      bouyomiVoice: _prefs.getInt(_kBouyomiVoice) ?? defaults.bouyomiVoice,
      voicevoxSpeaker: _prefs.getInt(_kVoicevoxSpeaker) ?? defaults.voicevoxSpeaker,
      voicevoxSpeed: _prefs.getDouble(_kVoicevoxSpeed) ?? defaults.voicevoxSpeed,
      voicevoxPitch: _prefs.getDouble(_kVoicevoxPitch) ?? defaults.voicevoxPitch,
      voicevoxIntonation:
          _prefs.getDouble(_kVoicevoxIntonation) ?? defaults.voicevoxIntonation,
      voicevoxVolume: _prefs.getDouble(_kVoicevoxVolume) ?? defaults.voicevoxVolume,
      queueLimit: _prefs.getInt(_kQueueLimit) ?? defaults.queueLimit,
      maxDelaySeconds: _prefs.getInt(_kMaxDelaySeconds) ?? defaults.maxDelaySeconds,
      omitUrl: _prefs.getBool(_kOmitUrl) ?? defaults.omitUrl,
      suppressDuplicate:
          _prefs.getBool(_kSuppressDuplicate) ?? defaults.suppressDuplicate,
      ngWords: _prefs.getString(_kNgWords) ?? defaults.ngWords,
      pastCommentFetchCount: PastCommentFetchCountValue.fromStorageValue(
        _prefs.getString(_kPastCommentFetchCount),
      ),
      debugMode: _prefs.getBool(_kDebugMode) ?? defaults.debugMode,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
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
    await _prefs.setString(
      _kPastCommentFetchCount,
      settings.pastCommentFetchCount.storageValue,
    );
    await _prefs.setBool(_kDebugMode, settings.debugMode);
  }
}

class InMemorySharedPreferences implements SharedPreferencesLike {
  final Map<String, Object> _values = <String, Object>{};

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }
}
