import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../widgets/settings_widgets.dart';
import 'ng_user_list_screen.dart';

class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({
    super.key,
    required this.settingsStore,
  });

  final SettingsStore settingsStore;

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen> {
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

    setState(() {
      _settings = loaded;
    });
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

  void _updateAndSave(AppSettings next) {
    debugPrint(
        '[TtsSettings] save: autoRead=${next.autoReadEnabled}, engine=${next.speechEngine}, speaker=${next.voicevoxSpeaker}, speed=${next.voicevoxSpeed}');
    setState(() {
      _settings = next;
    });
    unawaited(_saveSettings(next));
  }

  Future<void> _saveSettings(AppSettings next) =>
      saveSettingsToStore(widget.settingsStore, next);

  void _saveBouyomiHost() {
    final AppSettings? current = _settings;
    if (current == null) {
      return;
    }

    final String host = _bouyomiHostController.text.trim();
    if (host == current.bouyomiHost) {
      return;
    }

    _updateAndSave(current.copyWith(bouyomiHost: host));
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
    _updateAndSave(current.copyWith(ngWords: ngWords));
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

    _updateAndSave(current.copyWith(queueLimit: parsed));
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

    _updateAndSave(current.copyWith(maxDelaySeconds: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = _settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('読み上げ設定'),
      ),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('tts-settings-list'),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                SettingsSection(
                  title: '読み上げ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('auto-read-switch'),
                      title: const Text('自動読み上げ'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.autoReadEnabled,
                      onChanged: (bool value) {
                        _updateAndSave(
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
                            _updateAndSave(
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
                            _updateAndSave(
                                settings.copyWith(speechEngine: value));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (settings.speechEngine == SpeechEngine.bouyomi)
                  SettingsSection(
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
                      SettingsIntSliderField(
                        key: const Key('bouyomi-speed-slider'),
                        label: '速度',
                        min: -1,
                        max: 300,
                        divisions: 301,
                        value: settings.bouyomiSpeed,
                        onChanged: (int value) {
                          _updateAndSave(
                              settings.copyWith(bouyomiSpeed: value));
                        },
                      ),
                      SettingsIntSliderField(
                        key: const Key('bouyomi-tone-slider'),
                        label: '音程',
                        min: -1,
                        max: 300,
                        divisions: 301,
                        value: settings.bouyomiTone,
                        onChanged: (int value) {
                          _updateAndSave(settings.copyWith(bouyomiTone: value));
                        },
                      ),
                      SettingsIntSliderField(
                        key: const Key('bouyomi-volume-slider'),
                        label: '音量',
                        min: -1,
                        max: 100,
                        divisions: 101,
                        value: settings.bouyomiVolume,
                        onChanged: (int value) {
                          _updateAndSave(
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
                          _updateAndSave(
                              settings.copyWith(bouyomiVoice: value));
                        },
                      ),
                    ],
                  ),
                if (settings.speechEngine == SpeechEngine.voicevox)
                  SettingsSection(
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
                          _updateAndSave(
                              settings.copyWith(voicevoxSpeaker: value));
                        },
                      ),
                      const SizedBox(height: 12),
                      SettingsDoubleSliderField(
                        key: const Key('voicevox-speed-slider'),
                        label: '話速',
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        value: settings.voicevoxSpeed,
                        onChanged: (double value) {
                          _updateAndSave(
                              settings.copyWith(voicevoxSpeed: value));
                        },
                      ),
                      SettingsDoubleSliderField(
                        key: const Key('voicevox-pitch-slider'),
                        label: '音高',
                        min: -0.15,
                        max: 0.15,
                        divisions: 30,
                        value: settings.voicevoxPitch,
                        onChanged: (double value) {
                          _updateAndSave(
                              settings.copyWith(voicevoxPitch: value));
                        },
                      ),
                      SettingsDoubleSliderField(
                        key: const Key('voicevox-intonation-slider'),
                        label: '抑揚',
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        value: settings.voicevoxIntonation,
                        onChanged: (double value) {
                          _updateAndSave(
                            settings.copyWith(voicevoxIntonation: value),
                          );
                        },
                      ),
                      SettingsDoubleSliderField(
                        key: const Key('voicevox-volume-slider'),
                        label: '音量',
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        value: settings.voicevoxVolume,
                        onChanged: (double value) {
                          _updateAndSave(
                              settings.copyWith(voicevoxVolume: value));
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                SettingsSection(
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
                SettingsSection(
                  title: '読み上げフィルタ',
                  children: <Widget>[
                    SwitchListTile(
                      key: const Key('slash-prefix-skip-switch'),
                      title: const Text('「/」で読み上げスキップ'),
                      subtitle: const Text('/ で始まるコメントを読み上げない'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.slashPrefixSkipEnabled,
                      onChanged: (bool value) {
                        _updateAndSave(
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
                        _updateAndSave(
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
                        _updateAndSave(settings.copyWith(omitUrl: value));
                      },
                    ),
                    SwitchListTile(
                      key: const Key('suppress-duplicate-switch'),
                      title: const Text('連投抑制'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.suppressDuplicate,
                      onChanged: (bool value) {
                        _updateAndSave(
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
