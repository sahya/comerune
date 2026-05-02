import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../data/filter/broadcaster_ng_store.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';
import 'broadcaster_ng_list_screen.dart';
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

  /// Issue #727: when wired, the per-broadcaster NG management flow is
  /// available. When null the corresponding tile renders disabled with a
  /// 「未対応」 subtitle so unconnected/legacy embedders don't crash.
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

  /// Subtitle for the per-broadcaster NG tile.
  ///
  /// `listBroadcasters()` is a synchronous read — calling it from `build`
  /// is safe and stays consistent with `setState` triggered by
  /// `loadSettings()` returning from the picker.
  String _broadcasterNgSubtitle() {
    final BroadcasterNgStore? store = widget.broadcasterNgStore;
    if (store == null) {
      return '未対応';
    }
    int count;
    try {
      count = store.listBroadcasters().length;
    } on Object {
      // Defensive: an optional integration can fail to enumerate the
      // slot list; degrade to the bare description rather than break
      // the screen.
      return '放送者ごとに NG ユーザー / NG ワードを管理';
    }
    if (count == 0) {
      return '未登録 / 放送者ごとに NG ユーザー / NG ワードを管理';
    }
    return '$count 件の放送者で設定済み / 放送者ごとに NG ユーザー / NG ワードを管理';
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
                  const SizedBox(height: 12),
                  SettingsSection(
                    title: 'NG管理',
                    children: <Widget>[
                      ListTile(
                        key: const Key('broadcaster-ng-list-tile'),
                        contentPadding: EdgeInsets.zero,
                        enabled: widget.broadcasterNgStore != null,
                        leading: const Icon(Icons.person_off),
                        title: const Text('放送者別 NG 一覧'),
                        subtitle: Text(_broadcasterNgSubtitle()),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: widget.broadcasterNgStore == null
                            ? null
                            : () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => BroadcasterNgListScreen(
                                      broadcasterNgStore:
                                          widget.broadcasterNgStore!,
                                      broadcasterIdNotifier:
                                          widget.broadcasterIdNotifier,
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
