import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/settings_widgets.dart';

/// Mixin that provides common settings load/save logic for settings screens.
///
/// Requires the using class to implement [settingsStore] to provide the
/// [SettingsStore] instance.
mixin SettingsScreenMixin<T extends StatefulWidget> on State<T> {
  /// The settings store to load from and save to.
  SettingsStore get settingsStore;

  /// The currently loaded settings, or null if not yet loaded.
  AppSettings? settings;

  /// Whether any settings have been changed since the screen was opened.
  ///
  /// Set to `true` automatically when [updateAndSave] is called.
  /// Child screens can use this to report whether the parent needs to reload.
  bool get hasChanges => _hasChanges;
  bool _hasChanges = false;

  /// Error message when settings failed to load, or null if no error.
  String? settingsError;

  /// Loads settings from [settingsStore] and calls [setState].
  ///
  /// Subclasses can override this method to perform additional actions
  /// (e.g. loading models). If overriding completely, call [onSettingsLoaded]
  /// and set [settings] manually.
  Future<void> loadSettings() async {
    try {
      final AppSettings loaded = await settingsStore.load();
      if (!mounted) {
        return;
      }
      onSettingsLoaded(loaded);
      setState(() {
        settingsError = null;
        settings = loaded;
      });
    } on Object catch (e, st) {
      // `Exception` だけでなく `Error`（`StateError` / `TypeError` /
      // `ArgumentError` / `RangeError` / `AssertionError` 等）も捕捉する。
      // これらが伝播すると `settings` も `settingsError` も null のままになり、
      // 画面が CircularProgressIndicator のまま固まる（旧バージョンが
      // 保存した値を新バージョンで読めないアップデート時に発生し得る）。
      developer.log(
        'Failed to load settings',
        name: 'SettingsScreenMixin',
        error: e,
        stackTrace: st,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        settingsError = e.toString();
      });
    }
  }

  /// Builds an error UI with a retry button for when settings fail to load.
  ///
  /// NOTE: Retry re-runs [loadSettings] (i.e. [SettingsStore.load]) as-is.
  /// It does NOT auto-recover from persistent data corruption — if the
  /// underlying SharedPreferences value is the source of the failure,
  /// retry will simply re-throw and the user will be stuck in a loop.
  /// A real self-heal mechanism (e.g. "factory reset" affordance, or
  /// silently dropping the corrupt key) is intentionally out of scope
  /// for this PR; see follow-up issue for self-heal options.
  Widget buildSettingsError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Semantics(liveRegion: true, child: const Text('設定の読み込みに失敗しました')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                settingsError = null;
              });
              loadSettings();
            },
            child: const Text('再試行'),
          ),
        ],
      ),
    );
  }

  /// Called after settings are loaded but before [setState].
  ///
  /// Override to perform setup like populating text controllers.
  /// The default implementation does nothing.
  void onSettingsLoaded(AppSettings loaded) {}

  /// Marks that settings have been modified.
  ///
  /// Called automatically by [updateAndSave]. Subclasses that perform custom
  /// save logic without [updateAndSave] should call this explicitly.
  @protected
  void markChanged() {
    _hasChanges = true;
  }

  /// Updates [settings] in state and saves asynchronously.
  ///
  /// Also sets [hasChanges] to `true` so callers can detect modifications.
  void updateAndSave(AppSettings next) {
    markChanged();
    setState(() {
      settings = next;
    });
    unawaited(saveSettings(next));
  }

  /// Persists [next] to [settingsStore].
  Future<void> saveSettings(AppSettings next) =>
      saveSettingsToStore(settingsStore, next);
}
