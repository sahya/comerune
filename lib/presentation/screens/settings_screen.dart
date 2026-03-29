import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../application/settings/settings_store.dart';
import '../../data/auth/user_session_store.dart';
import '../../domain/models/app_settings.dart';
import '../../data/user/user_attribute_store.dart';
import 'login_screen.dart';
import 'favorite_user_list_screen.dart';
import 'ng_user_list_screen.dart';
import 'nickname_list_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settingsStore,
    this.userSessionStore,
    this.themeModeNotifier,
    this.userAttributeStore,
    this.broadcasterId,
  });

  final SettingsStore settingsStore;
  final UserSessionStore? userSessionStore;
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final UserAttributeStore? userAttributeStore;
  final String? broadcasterId;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const int _queueLimitMin = 1;
  static const int _queueLimitMax = 100;
  static const int _maxDelayMin = 1;
  static const int _maxDelayMax = 60;

  late final TextEditingController _bouyomiHostController;
  late final TextEditingController _queueLimitController;
  late final TextEditingController _maxDelayController;
  late final TextEditingController _ngWordsController;

  late final FocusNode _bouyomiHostFocusNode;
  late final FocusNode _queueLimitFocusNode;
  late final FocusNode _maxDelayFocusNode;
  late final FocusNode _ngWordsFocusNode;

  AppSettings? _settings;
  String? _queueLimitError;
  String? _maxDelayError;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _bouyomiHostController = TextEditingController();
    _queueLimitController = TextEditingController();
    _maxDelayController = TextEditingController();
    _ngWordsController = TextEditingController();

    _bouyomiHostFocusNode = FocusNode()
      ..addListener(_onBouyomiHostFocusChanged);
    _queueLimitFocusNode = FocusNode()..addListener(_onQueueLimitFocusChanged);
    _maxDelayFocusNode = FocusNode()..addListener(_onMaxDelayFocusChanged);
    _ngWordsFocusNode = FocusNode()..addListener(_onNgWordsFocusChanged);

    _loadSettings();
  }

  @override
  void dispose() {
    _bouyomiHostFocusNode
      ..removeListener(_onBouyomiHostFocusChanged)
      ..dispose();
    _queueLimitFocusNode
      ..removeListener(_onQueueLimitFocusChanged)
      ..dispose();
    _maxDelayFocusNode
      ..removeListener(_onMaxDelayFocusChanged)
      ..dispose();
    _ngWordsFocusNode
      ..removeListener(_onNgWordsFocusChanged)
      ..dispose();
    _bouyomiHostController.dispose();
    _queueLimitController.dispose();
    _maxDelayController.dispose();
    _ngWordsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final AppSettings loaded = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }

    _bouyomiHostController.text = loaded.bouyomiHost;
    _queueLimitController.text = loaded.queueLimit.toString();
    _maxDelayController.text = loaded.maxDelaySeconds.toString();
    _ngWordsController.text = loaded.ngWords;

    await _refreshLoginState();

    setState(() {
      _settings = loaded;
    });
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

  void _onBouyomiHostFocusChanged() {
    if (_bouyomiHostFocusNode.hasFocus) {
      return;
    }

    _saveBouyomiHost();
  }

  void _onQueueLimitFocusChanged() {
    if (_queueLimitFocusNode.hasFocus) {
      return;
    }

    _saveQueueLimit();
  }

  void _onMaxDelayFocusChanged() {
    if (_maxDelayFocusNode.hasFocus) {
      return;
    }

    _saveMaxDelaySeconds();
  }

  void _onNgWordsFocusChanged() {
    if (_ngWordsFocusNode.hasFocus) {
      return;
    }

    _saveNgWords();
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

  void _saveNextSettings(AppSettings next) {
    setState(() {
      _settings = next;
    });
    if (widget.themeModeNotifier != null &&
        widget.themeModeNotifier!.value != next.themeMode) {
      widget.themeModeNotifier!.value = next.themeMode;
    }
    unawaited(_saveSettings(next));
  }

  Future<void> _saveSettings(AppSettings next) async {
    try {
      await widget.settingsStore.save(next);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'settings_screen',
          context: ErrorDescription('while saving settings'),
        ),
      );
    }
  }

  void _saveBouyomiHost() {
    final AppSettings? current = _settings;
    if (current == null) {
      return;
    }

    final String host = _bouyomiHostController.text.trim();
    if (host == current.bouyomiHost) {
      return;
    }

    _saveNextSettings(current.copyWith(bouyomiHost: host));
  }

  void _saveNgWords() {
    final AppSettings? current = _settings;
    if (current == null) {
      return;
    }

    final String ngWords = _ngWordsController.text;
    if (ngWords == current.ngWords) {
      return;
    }

    // TODO(issue-12-followup): NGワードは正規表現入力のため、保存前に
    // RegExp.tryParse 相当で妥当性を検証し、無効パターンは保存を抑止する。
    _saveNextSettings(current.copyWith(ngWords: ngWords));
  }

  void _saveQueueLimit() {
    final AppSettings? current = _settings;
    if (current == null) {
      return;
    }

    final int? parsed = int.tryParse(_queueLimitController.text.trim());
    if (parsed == null) {
      setState(() {
        _queueLimitError = '数値を入力してください';
        // TODO(issue-12-followup): バリデーション失敗時の表示値は、
        // 「直前に保存済みの値へ復帰」仕様にするかを仕様側で再整理する。
      });
      return;
    }

    if (parsed < _queueLimitMin || parsed > _queueLimitMax) {
      setState(() {
        _queueLimitError = '$_queueLimitMin〜$_queueLimitMax の範囲で入力してください';
        // TODO(issue-12-followup): バリデーション失敗時の表示値復帰仕様を定義後、
        // ここで controller 値のロールバックを実装する。
      });
      return;
    }

    setState(() {
      _queueLimitError = null;
      _queueLimitController.text = parsed.toString();
    });

    if (parsed == current.queueLimit) {
      return;
    }

    _saveNextSettings(current.copyWith(queueLimit: parsed));
  }

  void _saveMaxDelaySeconds() {
    final AppSettings? current = _settings;
    if (current == null) {
      return;
    }

    final int? parsed = int.tryParse(_maxDelayController.text.trim());
    if (parsed == null) {
      setState(() {
        _maxDelayError = '数値を入力してください';
        // TODO(issue-12-followup): バリデーション失敗時の表示値は、
        // 「直前に保存済みの値へ復帰」仕様にするかを仕様側で再整理する。
      });
      return;
    }

    if (parsed < _maxDelayMin || parsed > _maxDelayMax) {
      setState(() {
        _maxDelayError = '$_maxDelayMin〜$_maxDelayMax の範囲で入力してください';
        // TODO(issue-12-followup): バリデーション失敗時の表示値復帰仕様を定義後、
        // ここで controller 値のロールバックを実装する。
      });
      return;
    }

    setState(() {
      _maxDelayError = null;
      _maxDelayController.text = parsed.toString();
    });

    if (parsed == current.maxDelaySeconds) {
      return;
    }

    _saveNextSettings(current.copyWith(maxDelaySeconds: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = _settings;

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
                _Section(
                  title: 'テーマ',
                  children: <Widget>[
                    DropdownButtonFormField<AppThemeMode>(
                      key: const Key('theme-mode-dropdown'),
                      value: settings.themeMode,
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
                        _saveNextSettings(
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
                _Section(
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
                _Section(
                  title: '読み上げ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('auto-read-switch'),
                      title: const Text('自動読み上げ'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoReadEnabled,
                      onChanged: (bool value) {
                        _saveNextSettings(
                            settings.copyWith(autoReadEnabled: value));
                      },
                    ),
                    const Text('読み上げエンジン'),
                    Column(
                      children: <Widget>[
                        RadioListTile<SpeechEngine>(
                          key: const Key('engine-bouyomi-radio'),
                          title: const Text('棒読みちゃん'),
                          contentPadding: EdgeInsets.zero,
                          value: SpeechEngine.bouyomi,
                          groupValue: settings.speechEngine,
                          onChanged: (SpeechEngine? value) {
                            if (value == null) return;
                            _saveNextSettings(
                                settings.copyWith(speechEngine: value));
                          },
                        ),
                        RadioListTile<SpeechEngine>(
                          key: const Key('engine-voicevox-radio'),
                          title: const Text('VOICEVOX'),
                          contentPadding: EdgeInsets.zero,
                          value: SpeechEngine.voicevox,
                          groupValue: settings.speechEngine,
                          onChanged: (SpeechEngine? value) {
                            if (value == null) return;
                            _saveNextSettings(
                                settings.copyWith(speechEngine: value));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (settings.speechEngine == SpeechEngine.bouyomi)
                  _Section(
                    key: const Key('bouyomi-section'),
                    title: '棒読みちゃん',
                    children: <Widget>[
                      TextFormField(
                        key: const Key('bouyomi-host-field'),
                        controller: _bouyomiHostController,
                        focusNode: _bouyomiHostFocusNode,
                        decoration: const InputDecoration(
                          labelText: 'ホスト',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _IntSliderField(
                        key: const Key('bouyomi-speed-slider'),
                        label: '速度',
                        min: -1,
                        max: 300,
                        divisions: 301,
                        value: settings.bouyomiSpeed,
                        onChanged: (int value) {
                          _saveNextSettings(
                              settings.copyWith(bouyomiSpeed: value));
                        },
                      ),
                      _IntSliderField(
                        key: const Key('bouyomi-tone-slider'),
                        label: '音程',
                        min: -1,
                        max: 300,
                        divisions: 301,
                        value: settings.bouyomiTone,
                        onChanged: (int value) {
                          _saveNextSettings(
                              settings.copyWith(bouyomiTone: value));
                        },
                      ),
                      _IntSliderField(
                        key: const Key('bouyomi-volume-slider'),
                        label: '音量',
                        min: -1,
                        max: 100,
                        divisions: 101,
                        value: settings.bouyomiVolume,
                        onChanged: (int value) {
                          _saveNextSettings(
                              settings.copyWith(bouyomiVolume: value));
                        },
                      ),
                      DropdownButtonFormField<int>(
                        key: const Key('bouyomi-voice-dropdown'),
                        value: settings.bouyomiVoice,
                        decoration: const InputDecoration(
                          labelText: '声質',
                          border: OutlineInputBorder(),
                        ),
                        items: _bouyomiVoiceOptions.entries
                            .map(
                              (MapEntry<int, String> entry) =>
                                  DropdownMenuItem<int>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        onChanged: (int? value) {
                          if (value == null) {
                            return;
                          }
                          _saveNextSettings(
                              settings.copyWith(bouyomiVoice: value));
                        },
                      ),
                    ],
                  ),
                if (settings.speechEngine == SpeechEngine.voicevox)
                  _Section(
                    key: const Key('voicevox-section'),
                    title: 'VOICEVOX',
                    children: <Widget>[
                      DropdownButtonFormField<int>(
                        key: const Key('voicevox-speaker-dropdown'),
                        value: settings.voicevoxSpeaker,
                        decoration: const InputDecoration(
                          labelText: '話者',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<int>>[
                          DropdownMenuItem<int>(
                            value: 0,
                            child: Text('四国めたん・あまあま (ID:0)'),
                          ),
                        ],
                        onChanged: (int? value) {
                          if (value == null) {
                            return;
                          }
                          _saveNextSettings(
                              settings.copyWith(voicevoxSpeaker: value));
                        },
                      ),
                      const SizedBox(height: 12),
                      _DoubleSliderField(
                        key: const Key('voicevox-speed-slider'),
                        label: '話速',
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        value: settings.voicevoxSpeed,
                        onChanged: (double value) {
                          _saveNextSettings(
                              settings.copyWith(voicevoxSpeed: value));
                        },
                      ),
                      _DoubleSliderField(
                        key: const Key('voicevox-pitch-slider'),
                        label: '音高',
                        min: -0.15,
                        max: 0.15,
                        divisions: 30,
                        value: settings.voicevoxPitch,
                        onChanged: (double value) {
                          _saveNextSettings(
                              settings.copyWith(voicevoxPitch: value));
                        },
                      ),
                      _DoubleSliderField(
                        key: const Key('voicevox-intonation-slider'),
                        label: '抑揚',
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        value: settings.voicevoxIntonation,
                        onChanged: (double value) {
                          _saveNextSettings(
                            settings.copyWith(voicevoxIntonation: value),
                          );
                        },
                      ),
                      _DoubleSliderField(
                        key: const Key('voicevox-volume-slider'),
                        label: '音量',
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        value: settings.voicevoxVolume,
                        onChanged: (double value) {
                          _saveNextSettings(
                              settings.copyWith(voicevoxVolume: value));
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                _Section(
                  title: '読み上げキュー',
                  children: <Widget>[
                    TextFormField(
                      key: const Key('queue-limit-field'),
                      controller: _queueLimitController,
                      focusNode: _queueLimitFocusNode,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'キュー上限',
                        border: const OutlineInputBorder(),
                        errorText: _queueLimitError,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('max-delay-field'),
                      controller: _maxDelayController,
                      focusNode: _maxDelayFocusNode,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '最大遅延（秒）',
                        border: const OutlineInputBorder(),
                        errorText: _maxDelayError,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: '読み上げフィルタ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('slash-prefix-skip-switch'),
                      title: const Text('「/」で読み上げスキップ'),
                      subtitle:
                          const Text('/ で始まるコメントを読み上げない'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.slashPrefixSkipEnabled,
                      onChanged: (bool value) {
                        _saveNextSettings(
                          settings.copyWith(slashPrefixSkipEnabled: value),
                        );
                      },
                    ),
                    SwitchListTile(
                      key: const Key('star-prefix-hiding-switch'),
                      title: const Text('「☆」で本文非表示'),
                      subtitle: const Text(
                        '☆ で始まるコメントの本文を隠す（タップで展開可能）。読み上げもしない',
                      ),
                      contentPadding: EdgeInsets.zero,
                      value: settings.starPrefixHidingEnabled,
                      onChanged: (bool value) {
                        _saveNextSettings(
                          settings.copyWith(starPrefixHidingEnabled: value),
                        );
                      },
                    ),
                    SwitchListTile(
                      key: const Key('omit-url-switch'),
                      title: const Text('URLを省略する'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.omitUrl,
                      onChanged: (bool value) {
                        _saveNextSettings(settings.copyWith(omitUrl: value));
                      },
                    ),
                    SwitchListTile(
                      key: const Key('suppress-duplicate-switch'),
                      title: const Text('連投抑制'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.suppressDuplicate,
                      onChanged: (bool value) {
                        _saveNextSettings(
                            settings.copyWith(suppressDuplicate: value));
                      },
                    ),
                    TextFormField(
                      key: const Key('ng-words-field'),
                      controller: _ngWordsController,
                      focusNode: _ngWordsFocusNode,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'NGワード（正規表現）',
                        hintText: '例: ^8+\$',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      key: const Key('ng-user-list-tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_off),
                      title: const Text('NGユーザーID管理'),
                      subtitle: Text(
                        settings.ngUserIdSet.isEmpty
                            ? '未登録'
                            : '${settings.ngUserIdSet.length}件登録中',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NgUserListScreen(
                              settingsStore: widget.settingsStore,
                            ),
                          ),
                        );
                        await _loadSettings();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
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
                            ),
                          ),
                        );
                        await _loadSettings();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'コテハン',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('auto-nickname-registration-switch'),
                      title: const Text('コテハン自動登録'),
                      subtitle: const Text('@名前 コメントで自動登録'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoNicknameRegistration,
                      onChanged: (bool value) {
                        _saveNextSettings(
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
                const SizedBox(height: 12),
                _Section(
                  title: 'コメント表示',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('show-user-name-switch'),
                      title: const Text('ユーザー名表示'),
                      subtitle: const Text('コメントにユーザー名カラムを表示'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.showUserName,
                      onChanged: (bool value) {
                        _saveNextSettings(
                            settings.copyWith(showUserName: value));
                      },
                    ),
                    SwitchListTile(
                      key: const Key('resolve-user-name-switch'),
                      title: const Text('ユーザーID名前解決'),
                      subtitle: const Text('数値IDをニックネームに変換'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.resolveUserName,
                      onChanged: settings.showUserName
                          ? (bool value) {
                              _saveNextSettings(
                                  settings.copyWith(resolveUserName: value));
                            }
                          : null,
                    ),
                    SwitchListTile(
                      key: const Key('auto-save-comment-log-switch'),
                      title: const Text('コメントログ自動保存'),
                      subtitle: const Text('接続終了時にコメントをファイルに保存'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoSaveCommentLog,
                      onChanged: (bool value) {
                        _saveNextSettings(
                            settings.copyWith(autoSaveCommentLog: value));
                      },
                    ),
                    const SizedBox(height: 8),
                    _IntSliderField(
                      key: const Key('comment-font-size-slider'),
                      label: 'コメント文字サイズ',
                      value: settings.commentFontSize.round(),
                      min: commentFontSizeMin.round(),
                      max: commentFontSizeMax.round(),
                      divisions:
                          (commentFontSizeMax - commentFontSizeMin).round(),
                      suffix: 'px',
                      sweetSpotMin: 12,
                      sweetSpotMax: 18,
                      sweetSpotLabel: 'おすすめ',
                      onChanged: (int value) {
                        _saveNextSettings(
                          settings.copyWith(commentFontSize: value.toDouble()),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<PastCommentFetchCount>(
                      key: const Key('past-comment-count-dropdown'),
                      value: settings.pastCommentFetchCount,
                      decoration: const InputDecoration(
                        labelText: '過去コメント取得件数',
                        border: OutlineInputBorder(),
                      ),
                      items: PastCommentFetchCount.values
                          .map(
                            (PastCommentFetchCount value) =>
                                DropdownMenuItem<PastCommentFetchCount>(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (PastCommentFetchCount? value) {
                        if (value == null) {
                          return;
                        }
                        _saveNextSettings(
                          settings.copyWith(pastCommentFetchCount: value),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'デバッグ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('debug-mode-switch'),
                      title: const Text('デバッグモード'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.debugMode,
                      onChanged: (bool value) {
                        _saveNextSettings(settings.copyWith(debugMode: value));
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

const Map<int, String> _bouyomiVoiceOptions = <int, String>{
  0: '既定',
  1: '女性1',
  2: '女性2',
  3: '男性1',
  4: '男性2',
  5: '中性',
  6: 'ロボット',
  7: '機械1',
  8: '機械2',
};

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _IntSliderField extends StatelessWidget {
  const _IntSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
    this.suffix = '',
    this.sweetSpotMin,
    this.sweetSpotMax,
    this.sweetSpotLabel,
  });

  final String label;
  final int min;
  final int max;
  final int divisions;
  final int value;
  final ValueChanged<int> onChanged;
  final String suffix;
  final int? sweetSpotMin;
  final int? sweetSpotMax;
  final String? sweetSpotLabel;

  @override
  Widget build(BuildContext context) {
    final bool hasSweetSpot = sweetSpotMin != null && sweetSpotMax != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label),
            const Spacer(),
            Text(value == -1 ? '-1 (既定)' : '$value$suffix'),
          ],
        ),
        if (hasSweetSpot)
          _SweetSpotSlider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            suffix: suffix,
            sweetSpotMin: sweetSpotMin!,
            sweetSpotMax: sweetSpotMax!,
            sweetSpotLabel: sweetSpotLabel,
            onChanged: onChanged,
          )
        else
          Slider(
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            value: value.toDouble(),
            semanticFormatterCallback:
                suffix.isNotEmpty ? (double v) => '${v.round()}$suffix' : null,
            onChanged: (double next) {
              onChanged(next.round());
            },
          ),
      ],
    );
  }
}

class _SweetSpotSlider extends StatelessWidget {
  const _SweetSpotSlider({
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.suffix,
    required this.sweetSpotMin,
    required this.sweetSpotMax,
    this.sweetSpotLabel,
    required this.onChanged,
  });

  final int min;
  final int max;
  final int divisions;
  final int value;
  final String suffix;
  final int sweetSpotMin;
  final int sweetSpotMax;
  final String? sweetSpotLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Slider has 24px horizontal padding on each side by default.
        const double sliderPadding = 24.0;
        final double trackWidth = constraints.maxWidth - sliderPadding * 2;
        final double range = (max - min).toDouble();
        final double leftFraction = (sweetSpotMin - min) / range;
        final double rightFraction = (sweetSpotMax - min) / range;
        final double left = sliderPadding + trackWidth * leftFraction;
        final double width = trackWidth * (rightFraction - leftFraction);

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: left,
              top: 16,
              width: width,
              height: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x1A4CAF50),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Slider(
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
              value: value.toDouble(),
              semanticFormatterCallback: suffix.isNotEmpty
                  ? (double v) => '${v.round()}$suffix'
                  : null,
              onChanged: (double next) {
                onChanged(next.round());
              },
            ),
            if (sweetSpotLabel != null)
              Positioned(
                left: left,
                top: 40,
                width: width,
                child: Text(
                  sweetSpotLabel!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DoubleSliderField extends StatelessWidget {
  const _DoubleSliderField({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label),
            const Spacer(),
            Text(value.toStringAsFixed(2)),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value,
          onChanged: (double next) {
            onChanged(double.parse(next.toStringAsFixed(2)));
          },
        ),
      ],
    );
  }
}
