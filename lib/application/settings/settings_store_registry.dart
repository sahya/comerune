import 'settings_store.dart';

/// アプリ起動時に SettingsStore を登録し、画面側から参照するための注入ポイント。
class SettingsStoreRegistry {
  SettingsStoreRegistry._();

  static SettingsStore? _settingsStore;

  static void register(SettingsStore settingsStore) {
    _settingsStore = settingsStore;
  }

  static SettingsStore get instance {
    final SettingsStore? current = _settingsStore;
    if (current == null) {
      throw StateError(
        'SettingsStore is not registered. '
        'Register it at app startup via SettingsStoreRegistry.register(...)',
      );
    }
    return current;
  }

  static void resetForTest() {
    _settingsStore = null;
  }
}
