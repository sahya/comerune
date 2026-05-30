import '../settings/settings_store.dart';

/// 任意更新通知の「後で」見送り版を記録するストア。
///
/// 通知方針は「起動毎に最大 1 回・見送った版は同一版で再通知しない」。
/// 起動毎 1 回は呼び出し側（起動時の post-frame）が 1 度だけ実行することで
/// 担保し、本ストアは「この版は見送り済みか」だけを永続化する。
///
/// 端末ローカルの一時状態であり、設定 Export/Import の対象外。
class UpdatePromptStore {
  const UpdatePromptStore({required SharedPreferencesLike prefs})
    : _prefs = prefs;

  final SharedPreferencesLike _prefs;

  static const String _kDismissedVersion = 'appUpdate.dismissedVersion';

  /// 直近に「後で」で見送った版（例 `1.2.0`）。未設定なら null。
  String? dismissedVersion() => _prefs.getString(_kDismissedVersion);

  Future<void> setDismissedVersion(String version) async {
    await _prefs.setString(_kDismissedVersion, version);
  }

  /// [version] の任意通知を出してよいか。
  /// 既に同じ版を見送っていれば false（再通知しない）。
  bool shouldPrompt(String version) => dismissedVersion() != version;
}
