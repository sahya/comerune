import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

/// `shared_preferences` 実体を `SharedPreferencesLike` に接続するアダプタ。
class SharedPreferencesAdapter implements SharedPreferencesLike {
  const SharedPreferencesAdapter(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  double? getDouble(String key) => _prefs.getDouble(key);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}

Future<SettingsStore> createSharedPreferencesSettingsStore() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPreferencesSettingsStore(
    prefs: SharedPreferencesAdapter(prefs),
  );
}
