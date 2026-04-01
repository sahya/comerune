import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/auth/user_session_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../../data/user/user_attribute_store.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';
import 'comment_display_settings_screen.dart';
import 'login_screen.dart';
import 'tts_settings_screen.dart';
import 'user_management_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    this.userSessionStore,
    this.themeModeNotifier,
    this.userAttributeStore,
    this.broadcasterIdNotifier,
    this.userNameResolution,
    this.speechPlatform,
  });

  final SettingsStore settingsStore;
  final UserSessionStore? userSessionStore;
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final UserAttributeStore? userAttributeStore;
  final ValueNotifier<String?>? broadcasterIdNotifier;
  final UserNameResolution? userNameResolution;
  final CommentSpeechPlatform? speechPlatform;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await loadSettings();
    await _refreshLoginState();
  }

  Future<void> _refreshLoginState() async {
    final UserSessionStore? sessionStore = widget.userSessionStore;
    if (sessionStore == null) {
      return;
    }
    final String session = await sessionStore.load();
    if (!mounted) {
      return;
    }
    final bool loggedIn = session.isNotEmpty;
    if (loggedIn != _isLoggedIn) {
      setState(() {
        _isLoggedIn = loggedIn;
      });
    }
  }

  bool _isOpeningLogin = false;

  Future<void> _openLoginScreen() async {
    if (_isOpeningLogin) {
      return;
    }
    final UserSessionStore? sessionStore = widget.userSessionStore;
    if (sessionStore == null) {
      return;
    }

    _isOpeningLogin = true;
    try {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => LoginScreen(userSessionStore: sessionStore),
        ),
      );
    } finally {
      _isOpeningLogin = false;
    }

    if (mounted) {
      await _refreshLoginState();
    }
  }

  Future<void> _logout() async {
    final UserSessionStore? sessionStore = widget.userSessionStore;
    if (sessionStore == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ログアウト'),
          content: const Text('ログアウトしますか？再度ログインが必要になります。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ログアウト'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await sessionStore.clear();
    // Also clear WebView cookies so re-login doesn't reuse stale session
    await WebViewCookieManager().clearCookies();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('ログアウトしました')),
        );
    }
  }

  @override
  void updateAndSave(AppSettings next) {
    super.updateAndSave(next);
    if (widget.themeModeNotifier != null &&
        widget.themeModeNotifier!.value != next.themeMode) {
      widget.themeModeNotifier!.value = next.themeMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('settings-list'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                SettingsSection(
                  title: 'テーマ',
                  children: <Widget>[
                    DropdownButtonFormField<AppThemeMode>(
                      key: const Key('theme-mode-dropdown'),
                      initialValue: settings.themeMode,
                      decoration: const InputDecoration(
                        labelText: '配色テーマ',
                        border: OutlineInputBorder(),
                      ),
                      items: AppThemeMode.values
                          .map(
                            (AppThemeMode mode) =>
                                DropdownMenuItem<AppThemeMode>(
                              value: mode,
                              child: Text(mode.label),
                            ),
                          )
                          .toList(),
                      onChanged: (AppThemeMode? value) {
                        if (value == null) {
                          return;
                        }
                        updateAndSave(
                          settings.copyWith(themeMode: value),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ダークモードは夜間の視認性を向上します。\n'
                      '色覚テーマは色の区別が難しい方に配慮した配色です。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SettingsSection(
                  title: 'ニコニコアカウント',
                  children: <Widget>[
                    if (_isLoggedIn) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text('ログイン済み'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          key: const Key('logout-button'),
                          onPressed: _logout,
                          child: const Text('ログアウト'),
                        ),
                      ),
                    ] else ...<Widget>[
                      const Text('コメント取得にはログインが必要です'),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('login-button'),
                          onPressed: widget.userSessionStore != null
                              ? _openLoginScreen
                              : null,
                          icon: const Icon(Icons.login),
                          label: const Text('ニコニコにログイン'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('tts-settings-tile'),
                    leading: const Icon(Icons.record_voice_over),
                    title: const Text('読み上げ設定'),
                    subtitle: Text(
                      settings.autoReadEnabled ? '自動読み上げ: ON' : '自動読み上げ: OFF',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TtsSettingsScreen(
                            settingsStore: widget.settingsStore,
                            platform: widget.speechPlatform,
                          ),
                        ),
                      );
                      await _loadSettings();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('comment-display-settings-tile'),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: const Text('コメント表示設定'),
                    subtitle: Text(
                      'フォントサイズ: ${settings.commentFontSize.round()}px',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CommentDisplaySettingsScreen(
                            settingsStore: widget.settingsStore,
                          ),
                        ),
                      );
                      await _loadSettings();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    key: const Key('user-management-settings-tile'),
                    leading: const Icon(Icons.people_outline),
                    title: const Text('ユーザー管理'),
                    subtitle: const Text('お気に入り・コテハン'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => UserManagementSettingsScreen(
                            settingsStore: widget.settingsStore,
                            userAttributeStore: widget.userAttributeStore,
                            broadcasterIdNotifier: widget.broadcasterIdNotifier,
                            userNameResolution: widget.userNameResolution,
                          ),
                        ),
                      );
                      await _loadSettings();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                SettingsSection(
                  title: 'デバッグ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('debug-mode-switch'),
                      title: const Text('デバッグモード'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.debugMode,
                      onChanged: (bool value) {
                        updateAndSave(settings.copyWith(debugMode: value));
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
