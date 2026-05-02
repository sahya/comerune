import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../data/filter/broadcaster_ng_store.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';
import 'favorite_user_list_screen.dart';

class UserManagementSettingsScreen extends StatefulWidget {
  const UserManagementSettingsScreen({
    super.key,
    required this.settingsStore,
    this.userAttributeStore,
    this.broadcasterNgStore,
    this.broadcasterIdNotifier,
    this.userNameResolution,
    this.initialSettings,
  });

  final SettingsStore settingsStore;
  final UserAttributeStore? userAttributeStore;

  /// Issue #727: kept on the constructor signature so existing call sites
  /// (and the Settings screen wiring) continue to compile after the
  /// per-broadcaster NG management entry was promoted to a top-level
  /// Settings tile. The fields are unused here for now; future
  /// per-broadcaster コテハン work will reuse them.
  final BroadcasterNgStore? broadcasterNgStore;
  final ValueNotifier<String?>? broadcasterIdNotifier;
  final UserNameResolution? userNameResolution;

  /// Pre-loaded settings from the parent screen.
  ///
  /// When provided, the screen uses these settings directly instead of
  /// loading from the store, avoiding a redundant read.
  final AppSettings? initialSettings;

  @override
  State<UserManagementSettingsScreen> createState() =>
      _UserManagementSettingsScreenState();
}

class _UserManagementSettingsScreenState
    extends State<UserManagementSettingsScreen>
    with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  @override
  void initState() {
    super.initState();
    if (widget.initialSettings != null) {
      onSettingsLoaded(widget.initialSettings!);
      settings = widget.initialSettings;
    } else {
      loadSettings();
    }
    widget.broadcasterIdNotifier?.addListener(_onBroadcasterIdChanged);
  }

  @override
  void didUpdateWidget(covariant UserManagementSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.broadcasterIdNotifier != widget.broadcasterIdNotifier) {
      oldWidget.broadcasterIdNotifier?.removeListener(_onBroadcasterIdChanged);
      widget.broadcasterIdNotifier?.addListener(_onBroadcasterIdChanged);
    }
  }

  @override
  void dispose() {
    widget.broadcasterIdNotifier?.removeListener(_onBroadcasterIdChanged);
    super.dispose();
  }

  void _onBroadcasterIdChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (!didPop) {
          Navigator.of(context).pop(hasChanges);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('ユーザー管理')),
        body: settingsError != null
            ? buildSettingsError(context)
            : settings == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                key: const Key('user-management-settings-list'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: <Widget>[
                  SettingsSection(
                    title: 'お気に入りユーザー',
                    children: <Widget>[
                      ListTile(
                        key: const Key('favorite-user-list-tile'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_add),
                        title: const Text('お気に入りユーザーID管理'),
                        subtitle: Text(
                          settings.favoriteUserIdSet.isEmpty
                              ? '未登録'
                              : '${settings.favoriteUserIdSet.length}件登録中',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => FavoriteUserListScreen(
                                settingsStore: widget.settingsStore,
                                userNameResolution: widget.userNameResolution,
                              ),
                            ),
                          );
                          await loadSettings();
                        },
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
