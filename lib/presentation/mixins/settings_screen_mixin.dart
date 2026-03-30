import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/settings_widgets.dart';

/// Mixin that provides the common load/save pattern shared by settings screens.
///
/// Subclasses must implement [settingsStore] and call [loadSettings] from
/// [initState].  Override [onSettingsLoaded] or [onSettingsUpdated] to run
/// screen-specific side-effects (e.g. syncing a theme notifier or populating
/// text controllers).
mixin SettingsScreenMixin<T extends StatefulWidget> on State<T> {
  /// The store used to persist and retrieve [AppSettings].
  SettingsStore get settingsStore;

  /// The currently loaded settings, or `null` while loading.
  AppSettings? settings;

  /// Loads settings from [settingsStore] and updates [settings] via
  /// [setState].  Safe to call even after the widget has been disposed.
  Future<void> loadSettings() async {
    final AppSettings loaded = await settingsStore.load();
    if (!mounted) {
      return;
    }
    setState(() {
      settings = loaded;
    });
  }

  /// Applies [next] to local state and persists it asynchronously.
  void updateAndSave(AppSettings next) {
    setState(() {
      settings = next;
    });
    unawaited(saveSettingsToStore(settingsStore, next));
  }
}
