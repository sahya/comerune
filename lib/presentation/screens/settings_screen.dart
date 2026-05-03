import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../application/settings/settings_store.dart';
import '../../application/speech/speech_availability_notifier.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/auth/user_session_store.dart';
import '../../data/broadcaster/broadcaster_name_store.dart';
import '../../data/filter/broadcaster_ng_store.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../../data/user/user_attribute_store.dart';
import '../mixins/settings_screen_mixin.dart';
import '../strings/app_strings.dart';
import '../widgets/settings_widgets.dart';
import 'broadcaster_ng_list_screen.dart';
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
    this.broadcasterNgStore,
    this.broadcasterNameStore,
    this.broadcasterIdNotifier,
    this.userNameResolution,
    this.speechPlatform,
    this.androidTtsAvailability,
  });

  final SettingsStore settingsStore;
  final UserSessionStore? userSessionStore;
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final UserAttributeStore? userAttributeStore;

  /// Issue #727: per-broadcaster NG management store. Forwarded to the
  /// child screens that expose NG editing UI.
  final BroadcasterNgStore? broadcasterNgStore;

  /// Issue #727 follow-up: persistent cache of broadcaster display names.
  /// When provided, the NG picker uses it to render `name(id)` tile titles
  /// instead of raw IDs. Optional — null falls back to ID-only rendering.
  final BroadcasterNameStore? broadcasterNameStore;
  final ValueNotifier<String?>? broadcasterIdNotifier;
  final UserNameResolution? userNameResolution;
  final CommentSpeechPlatform? speechPlatform;

  /// Issue #694: passed through to [TtsSettingsScreen] so its availability
  /// check publishes to the cross-screen notifier.
  final SpeechAvailabilityNotifier? androidTtsAvailability;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SettingsScreenMixin {
  @override
  SettingsStore get settingsStore => widget.settingsStore;

  bool _isLoggedIn = false;
  bool _isExporting = false;
  bool _isImporting = false;

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
          title: Text(AppStrings.settings.logoutDialogTitle),
          content: Text(AppStrings.settings.logoutDialogMessage),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppStrings.settings.logoutDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(AppStrings.settings.logoutDialogConfirm),
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
          SnackBar(content: Text(AppStrings.settings.logoutSnackBar)),
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

  Future<void> _exportSettings() async {
    if (_isExporting) {
      return;
    }
    setState(() => _isExporting = true);
    try {
      // filesystem I/O は data 層の SettingsStore.writeExportToTempFile に
      // 集約し、ここでは「パスを受け取って share する」だけに留める。
      final String path = await widget.settingsStore.writeExportToTempFile();
      // Android の Google Drive 等は `EXTRA_SUBJECT` を保存時の既定ファイル名
      // として採用し、FileProvider の DISPLAY_NAME より優先する。
      // ディスク上の実体がタイムスタンプ付きでも subject が変わらないと
      // 受信側でタイムスタンプが落ちるため、basename を subject と
      // XFile.name の双方に渡して整合させる。
      final String exportFileName = Uri.file(path).pathSegments.last;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(
              path,
              name: exportFileName,
              mimeType: SettingsExport.mimeType,
            ),
          ],
          subject: exportFileName,
        ),
      );
    } on Exception catch (e) {
      developer.log('Failed to export settings: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(AppStrings.settings.exportFailedSnackBar)),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importSettings() async {
    if (_isImporting) {
      return;
    }
    setState(() => _isImporting = true);
    try {
      final FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        // `['json']` 単独だと Android の SAF は `application/json` MIME のみで
        // 絞り込むため、Drive 等で `text/plain` として保存された JSON が
        // ピッカーでグレーアウトする。`.txt` も許容して text/plain を通す。
        // 中身が JSON でなければ既存の FormatException ハンドラで拒否される。
        allowedExtensions: <String>['json', 'txt'],
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
            title: Text(AppStrings.settings.importDialogTitle),
            content: Text(AppStrings.settings.importDialogMessage),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppStrings.settings.importDialogCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppStrings.settings.importDialogConfirm),
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
        ..showSnackBar(
          SnackBar(content: Text(AppStrings.settings.importSuccessSnackBar)),
        );
    } on FormatException catch (e) {
      developer.log('Invalid settings file: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(AppStrings.settings.importInvalidFileSnackBar),
            ),
          );
      }
    } on Exception catch (e) {
      developer.log('Failed to import settings: $e', name: 'SettingsScreen');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(AppStrings.settings.importFailedSnackBar)),
          );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.settings.title)),
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
                const SizedBox(height: 12),
                _buildBroadcasterNgTile(context),
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
      title: AppStrings.settings.accountSectionTitle,
      children: <Widget>[
        if (_isLoggedIn) ...<Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(AppStrings.settings.accountLoggedInLabel),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('logout-button'),
              onPressed: _logout,
              child: Text(AppStrings.settings.accountLogoutButton),
            ),
          ),
        ] else ...<Widget>[
          Text(AppStrings.settings.accountLoginRequired),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              key: const Key('login-button'),
              onPressed: widget.userSessionStore != null
                  ? _openLoginScreen
                  : null,
              icon: const Icon(Icons.login),
              label: Text(AppStrings.settings.accountLoginButton),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildThemeSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
      title: AppStrings.settings.themeSectionTitle,
      children: <Widget>[
        DropdownButtonFormField<AppThemeMode>(
          key: const Key('theme-mode-dropdown'),
          initialValue: settings.themeMode,
          decoration: InputDecoration(
            labelText: AppStrings.settings.themeDropdownLabel,
            border: const OutlineInputBorder(),
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
          AppStrings.settings.themeDescription,
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
        title: Text(AppStrings.settings.commentDisplayTileTitle),
        subtitle: Text(
          AppStrings.settings.commentFontSizeSubtitle(
            settings.commentFontSize.round(),
          ),
        ),
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
        title: Text(AppStrings.settings.ttsTileTitle),
        subtitle: Text(
          AppStrings.settings.ttsAutoReadSubtitle(
            enabled: settings.autoReadEnabled,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final bool? changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => TtsSettingsScreen(
                settingsStore: widget.settingsStore,
                platform: widget.speechPlatform,
                initialSettings: settings,
                androidTtsAvailability: widget.androidTtsAvailability,
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
        title: Text(AppStrings.settings.userManagementTileTitle),
        subtitle: Text(AppStrings.settings.userManagementTileSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final bool? changed = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(
              builder: (_) => UserManagementSettingsScreen(
                settingsStore: widget.settingsStore,
                userAttributeStore: widget.userAttributeStore,
                broadcasterNgStore: widget.broadcasterNgStore,
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

  Widget _buildBroadcasterNgTile(BuildContext context) {
    // Issue #727 follow-up: single Settings-level entry into the
    // per-broadcaster NG editor. Title chosen to match sibling tiles
    // (「コメント表示設定」「読み上げ設定」) and the AppBar of the editor
    // (「NG 設定 - <放送者名>」). Subtitle is shown ONLY when the store
    // is unwired, so legacy embedders see a 「未対応」 hint instead of an
    // unresponsive tile.
    final BroadcasterNgStore? store = widget.broadcasterNgStore;
    final bool enabled = store != null;
    return Card(
      child: ListTile(
        key: const Key('broadcaster-ng-filter-tile'),
        enabled: enabled,
        leading: const Icon(Icons.block),
        title: Text(AppStrings.settings.ngFilterTileTitle),
        subtitle: enabled
            ? null
            : Text(AppStrings.settings.ngFilterTileSubtitleDisabled),
        trailing: const Icon(Icons.chevron_right),
        onTap: !enabled
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) {
                      final BroadcasterNameStore? nameStore =
                          widget.broadcasterNameStore;
                      return BroadcasterNgListScreen(
                        broadcasterNgStore: store,
                        broadcasterIdNotifier: widget.broadcasterIdNotifier,
                        broadcasterNameResolver: nameStore == null
                            ? null
                            : (String id) => nameStore.loadName(id),
                      );
                    },
                  ),
                );
                // Refresh settings on return so any side-effects in the NG
                // editor (e.g. future writes that touch settings) are
                // reflected without requiring the user to leave the screen.
                if (mounted) {
                  await _loadSettings();
                }
              },
      ),
    );
  }

  Widget _buildDataManagementSection(BuildContext context) {
    return SettingsSection(
      title: AppStrings.settings.dataManagementSectionTitle,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('export-settings-button'),
            onPressed: _isExporting ? null : _exportSettings,
            icon: _isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload),
            label: Text(AppStrings.settings.exportSettingsButton),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('import-settings-button'),
            onPressed: _isImporting ? null : _importSettings,
            icon: _isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(AppStrings.settings.importSettingsButton),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppStrings.settings.dataManagementDescription,
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
        title: Text(AppStrings.settings.licenseTileTitle),
        subtitle: Text(AppStrings.settings.licenseTileSubtitle),
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
      applicationName: AppStrings.settings.licenseApplicationName,
      applicationVersion: applicationVersion,
    );
  }

  Widget _buildDebugSection(BuildContext context, AppSettings settings) {
    return SettingsSection(
      title: AppStrings.settings.debugSectionTitle,
      children: <Widget>[
        SwitchListTile(
          key: const Key('debug-mode-switch'),
          title: Text(AppStrings.settings.debugModeSwitchTitle),
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
