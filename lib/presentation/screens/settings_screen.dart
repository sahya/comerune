import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
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
        ..showSnackBar(const SnackBar(content: Text('ログアウトしました')));
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

  Future<void> _exportSettings() async {
    try {
      final String json = await widget.settingsStore.exportAsJson();
      await SharePlus.instance.share(
        ShareParams(text: json, subject: 'comerune-settings.json'),
      );
    } on Exception catch (e) {
      developer.log('Failed to export settings: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('設定のエクスポートに失敗しました')));
      }
    }
  }

  Future<void> _importSettings() async {
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final String? path = result.files.single.path;
      if (path == null) {
        return;
      }
      final String jsonString = await File(path).readAsString();

      if (!mounted) {
        return;
      }

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('設定のインポート'),
            content: const Text('現在の設定がインポートしたデータで上書きされます。よろしいですか？'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('インポート'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final AppSettings imported = await widget.settingsStore.importFromJson(
        jsonString,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        settings = imported;
      });

      if (widget.themeModeNotifier != null &&
          widget.themeModeNotifier!.value != imported.themeMode) {
        widget.themeModeNotifier!.value = imported.themeMode;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('設定をインポートしました')));
    } on FormatException catch (e) {
      developer.log('Invalid settings file: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('無効な設定ファイルです')));
      }
    } on Exception catch (e) {
      developer.log('Failed to import settings: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('設定のインポートに失敗しました')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: settingsError != null
          ? buildSettingsError(context)
          : settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('settings-list'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                // --- アカウント ---
                _buildAccountSection(context),
                const Divider(height: 24),
                // --- コア設定 ---
                _buildThemeSection(context, settings),
                const SizedBox(height: 12),
                _buildCommentDisplayTile(context, settings),
                const SizedBox(height: 12),
                _buildTtsTile(context, settings),
                const SizedBox(height: 12),
                _buildUserManagementTile(context, settings),
                const Divider(height: 24),
                // --- 管理・上級 ---
                _buildDataManagementSection(context),
                const Divider(height: 24),
                // --- ライセンス ---
                _buildLicenseTile(context),
                const SizedBox(height: 12),
                _buildDebugSection(context, settings),
              ],
            ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return SettingsSection(
      title: 'ニコニコアカウント',
      children: <Widget>[
        if (_isLoggedIn) ...<Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
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
    );
  }

  Widget _buildThemeSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
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
                (AppThemeMode mode) => DropdownMenuItem<AppThemeMode>(
                  value: mode,
                  child: Text(mode.label),
                ),
              )
              .toList(),
          onChanged: (AppThemeMode? value) {
            if (value == null) {
              return;
            }
            updateAndSave(settings.copyWith(themeMode: value));
          },
        ),
        const SizedBox(height: 8),
        Text(
          'ダークモードは夜間の視認性を向上します。\n'
          '色覚テーマは色の区別が難しい方に配慮した配色です。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCommentDisplayTile(BuildContext context, AppSettings settings) {
    return Card(
      child: ListTile(
        key: const Key('comment-display-settings-tile'),
        leading: const Icon(Icons.chat_bubble_outline),
        title: const Text('コメント表示設定'),
        subtitle: Text('フォントサイズ: ${settings.commentFontSize.round()}px'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final bool? changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => CommentDisplaySettingsScreen(
                settingsStore: widget.settingsStore,
                initialSettings: settings,
              ),
            ),
          );
          if (changed == true) {
            await _loadSettings();
          }
        },
      ),
    );
  }

  Widget _buildTtsTile(BuildContext context, AppSettings settings) {
    return Card(
      child: ListTile(
        key: const Key('tts-settings-tile'),
        leading: const Icon(Icons.record_voice_over),
        title: const Text('読み上げ設定'),
        subtitle: Text(settings.autoReadEnabled ? '自動読み上げ: ON' : '自動読み上げ: OFF'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final bool? changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => TtsSettingsScreen(
                settingsStore: widget.settingsStore,
                platform: widget.speechPlatform,
                initialSettings: settings,
              ),
            ),
          );
          if (changed == true) {
            await _loadSettings();
          }
        },
      ),
    );
  }

  Widget _buildUserManagementTile(BuildContext context, AppSettings settings) {
    return Card(
      child: ListTile(
        key: const Key('user-management-settings-tile'),
        leading: const Icon(Icons.people_outline),
        title: const Text('ユーザー管理'),
        subtitle: const Text('お気に入り・コテハン'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final bool? changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => UserManagementSettingsScreen(
                settingsStore: widget.settingsStore,
                userAttributeStore: widget.userAttributeStore,
                broadcasterIdNotifier: widget.broadcasterIdNotifier,
                userNameResolution: widget.userNameResolution,
                initialSettings: settings,
              ),
            ),
          );
          if (changed == true) {
            await _loadSettings();
          }
        },
      ),
    );
  }

  Widget _buildDataManagementSection(BuildContext context) {
    return SettingsSection(
      title: 'データ管理',
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('export-settings-button'),
            onPressed: _exportSettings,
            icon: const Icon(Icons.upload),
            label: const Text('設定をエクスポート'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('import-settings-button'),
            onPressed: _importSettings,
            icon: const Icon(Icons.download),
            label: const Text('設定をインポート'),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'JSON形式で設定のバックアップ・復元ができます。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildLicenseTile(BuildContext context) {
    return Card(
      child: ListTile(
        key: const Key('license-tile'),
        leading: const Icon(Icons.description_outlined),
        title: const Text('ライセンス'),
        subtitle: const Text('第三者ライブラリのライセンス情報'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openLicensePage(context),
      ),
    );
  }

  Future<void> _openLicensePage(BuildContext context) async {
    // pubspec.yaml と自動同期するため PackageInfo からバージョンを取得する。
    // 取得に失敗した場合はバージョン非表示でライセンス画面を開く（UX 上、
    // ライセンス情報の閲覧自体は阻害しない）。
    // Error 系（OutOfMemoryError 等）は握りつぶさず伝搬させるため、
    // Exception に限定して捕捉する。
    //
    // パッケージ一覧・ライセンス本文は Flutter 標準の [LicenseRegistry] が
    // `pubspec.yaml` の依存解決結果を起動時に自動登録する仕組みに一本化している。
    // [showLicensePage] は [LicenseRegistry.licenses] を参照して描画するため、
    // 依存の追加・削除・バージョン更新は本画面で手動同期する必要はない。
    //
    // ポリシー: このアプリでは [LicenseRegistry.addLicense] を呼び出さない。
    // - パッケージ名・ライセンス本文のハードコードを禁じ、真実の源を
    //   `pubspec.yaml` に一本化するため。
    // - もし将来 third-party asset（同梱フォント等）を追加する場合のみ、
    //   そのアセットに限って [LicenseRegistry.addLicense] で登録する。
    String? applicationVersion;
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      applicationVersion = packageInfo.version;
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to load PackageInfo for license page',
        name: 'SettingsScreen',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!context.mounted) {
      return;
    }

    showLicensePage(
      context: context,
      applicationName: 'comerune',
      applicationVersion: applicationVersion,
    );
  }

  Widget _buildDebugSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
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
    );
  }
}
