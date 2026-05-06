import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/domain/models/app_settings.dart';

import 'in_memory_shared_preferences.dart';

/// Test stub: a [SettingsStore] whose [load] throws a configurable [Object]
/// (defaults to [Exception]).
///
/// Mutate [shouldThrow] to switch the store between failing and delegating
/// loads at runtime — useful for verifying retry-after-failure flows.
/// Pass [errorToThrow] to simulate `Error` subclasses (e.g. `StateError`,
/// `TypeError`) escaping `SettingsStore.load()` from legacy persisted-data
/// parsing, not just `Exception`.
///
/// All non-`load` operations delegate to a real
/// [SharedPreferencesSettingsStore] backed by [InMemorySharedPreferences],
/// so save / export / import behave like a normal in-memory store.
class ThrowingSettingsStore implements SettingsStore {
  ThrowingSettingsStore({this.errorToThrow});

  /// Whether the next [load] call should throw. Defaults to `true`. Tests
  /// can flip this to `false` to make a subsequent load (e.g. a retry)
  /// succeed.
  bool shouldThrow = true;

  /// Optional alternative thing to throw — allows tests to simulate `Error`
  /// subclasses (`StateError` / `TypeError` 等) escaping `load()`, not just
  /// `Exception`. When `null`, a generic `Exception` is thrown.
  final Object? errorToThrow;

  final SharedPreferencesSettingsStore _delegate =
      SharedPreferencesSettingsStore(prefs: InMemorySharedPreferences());

  @override
  Future<AppSettings> load() async {
    if (shouldThrow) {
      // ignore: only_throw_errors, test stub intentionally throws Object
      // subclasses (Exception or Error) for parameterized failure cases.
      throw errorToThrow ?? Exception('simulated load failure');
    }
    return _delegate.load();
  }

  @override
  Future<void> save(AppSettings settings) => _delegate.save(settings);

  @override
  double? loadPreMuteVolume() => _delegate.loadPreMuteVolume();

  @override
  Future<void> savePreMuteVolume(double? volume) =>
      _delegate.savePreMuteVolume(volume);

  @override
  double? loadPreMuteAndroidTtsVolume() =>
      _delegate.loadPreMuteAndroidTtsVolume();

  @override
  Future<void> savePreMuteAndroidTtsVolume(double? volume) =>
      _delegate.savePreMuteAndroidTtsVolume(volume);

  @override
  Future<String> exportAsJson() => _delegate.exportAsJson();

  @override
  Future<String> writeExportToTempFile() => _delegate.writeExportToTempFile();

  @override
  Future<AppSettings> importFromJson(String jsonString) =>
      _delegate.importFromJson(jsonString);
}
