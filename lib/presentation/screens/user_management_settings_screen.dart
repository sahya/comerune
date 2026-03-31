import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/settings_widgets.dart';
import 'favorite_user_list_screen.dart';
import 'nickname_list_screen.dart';

class UserManagementSettingsScreen extends StatefulWidget {
  const UserManagementSettingsScreen({
    super.key,
    required this.settingsStore,
    this.userAttributeStore,
    this.broadcasterIdNotifier,
    this.resolveUserName,
    this.requestUserNameResolve,
    this.userNameListenable,
  });

  final SettingsStore settingsStore;
  final UserAttributeStore? userAttributeStore;
  final ValueNotifier<String?>? broadcasterIdNotifier;
  final String? Function(String userId)? resolveUserName;
  final void Function(String userId)? requestUserNameResolve;
  final Listenable? userNameListenable;

  @override
  State<UserManagementSettingsScreen> createState() =>
      _UserManagementSettingsScreenState();
}

class _UserManagementSettingsScreenState
    extends State<UserManagementSettingsScreen> {
  AppSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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

  Future<void> _loadSettings() async {
    final AppSettings loaded = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }

    setState(() {
      _settings = loaded;
    });
  }

  void _updateAndSave(AppSettings next) {
    setState(() {
      _settings = next;
    });
    unawaited(_saveSettings(next));
  }

  Future<void> _saveSettings(AppSettings next) =>
      saveSettingsToStore(widget.settingsStore, next);

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ユーザー管理'),
      ),
      body: settings == null
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
                              resolveUserName: widget.resolveUserName,
                              requestUserNameResolve:
                                  widget.requestUserNameResolve,
                              userNameListenable: widget.userNameListenable,
                            ),
                          ),
                        );
                        await _loadSettings();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SettingsSection(
                  title: 'コテハン',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('auto-nickname-registration-switch'),
                      title: const Text('コテハン自動登録'),
                      subtitle: const Text('@名前 コメントで自動登録'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoNicknameRegistration,
                      onChanged: (bool value) {
                        _updateAndSave(
                          settings.copyWith(
                            autoNicknameRegistration: value,
                          ),
                        );
                      },
                    ),
                    if (widget.userAttributeStore != null)
                      Builder(builder: (BuildContext context) {
                        final String? broadcasterId =
                            widget.broadcasterIdNotifier?.value;
                        final bool enabled = broadcasterId != null;
                        return ListTile(
                          key: const Key('nickname-list-tile'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.badge),
                          title: const Text('コテハン管理'),
                          subtitle: enabled
                              ? null
                              : const Text('放送に接続すると利用できます'),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: enabled,
                          onTap: enabled
                              ? () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => NicknameListScreen(
                                        userAttributeStore:
                                            widget.userAttributeStore!,
                                        broadcasterId: broadcasterId!,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        );
                      }),
                  ],
                ),
              ],
            ),
    );
  }
}
