import 'dart:async';

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

  /// Loads settings from [settingsStore] and calls [setState].
  ///
  /// Subclasses can override [onSettingsLoaded] to perform additional
  /// actions after the settings are loaded (e.g. populating text controllers).
  @mustCallSuper
  Future<void> loadSettings() async {
    final AppSettings loaded = await settingsStore.load();
    if (!mounted) {
      return;
    }
    onSettingsLoaded(loaded);
    setState(() {
      settings = loaded;
    });
  }

  /// Called after settings are loaded but before [setState].
  ///
  /// Override to perform setup like populating text controllers.
  /// The default implementation does nothing.
  void onSettingsLoaded(AppSettings loaded) {}

  /// Updates [settings] in state and saves asynchronously.
  void updateAndSave(AppSettings next) {
    setState(() {
      settings = next;
    });
    unawaited(saveSettings(next));
  }

  /// Persists [next] to [settingsStore].
  Future<void> saveSettings(AppSettings next) =>
      saveSettingsToStore(settingsStore, next);
}
