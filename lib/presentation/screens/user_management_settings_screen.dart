import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/models/app_settings.dart';
import '../mixins/settings_screen_mixin.dart';
import '../models/user_name_resolution.dart';
import '../widgets/settings_widgets.dart';
import 'favorite_user_list_screen.dart';
import 'nickname_list_screen.dart';

class UserManagementSettingsScreen extends StatefulWidget {
  const UserManagementSettingsScreen({
    super.key,
    required this.settingsStore,
    this.userAttributeStore,
    this.broadcasterId,
    this.userNameResolution,
  });

  final SettingsStore settingsStore;
  final UserAttributeStore? userAttributeStore;
  final String? broadcasterId;
  final UserNameResolution? userNameResolution;

  @override
  State<UserManagementSettingsScreen> createState() =>
      _UserManagementSettingsScreenState();
}

class _UserManagementSettingsScreenState
    extends State<UserManagementSettingsScreen> with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

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
                  title: 'コテハン',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('auto-nickname-registration-switch'),
                      title: const Text('コテハン自動登録'),
                      subtitle: const Text('@名前 コメントで自動登録'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoNicknameRegistration,
                      onChanged: (bool value) {
                        updateAndSave(
                          settings.copyWith(
                            autoNicknameRegistration: value,
                          ),
                        );
                      },
                    ),
                    if (widget.userAttributeStore != null)
                      ListTile(
                        key: const Key('nickname-list-tile'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.badge),
                        title: const Text('コテハン一覧管理'),
                        subtitle: widget.broadcasterId == null
                            ? const Text('放送に接続すると利用できます')
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        enabled: widget.broadcasterId != null,
                        onTap: widget.broadcasterId != null
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => NicknameListScreen(
                                      userAttributeStore:
                                          widget.userAttributeStore!,
                                      broadcasterId: widget.broadcasterId!,
                                    ),
                                  ),
                                );
                              }
                            : null,
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
