import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../domain/models/app_settings.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';
import 'ng_user_list_screen.dart';

// TODO(#13): 棒読みちゃん対応は UIから非表示とした。サーバーを管理しない方針のため、
// 今後削除するか再実装するかは未定。万が一機会があれば再検討する。
// 棒読みちゃん関連のドメインモデル・設定ストアのフィールドは後方互換のため残している。
class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({
    super.key,
    required this.settingsStore,
  });

  final SettingsStore settingsStore;

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen>
    with SettingsScreenMixin {
  static const int _queueLimitMin = 1;
  static const int _queueLimitMax = 100;
  static const int _maxDelayMin = 1;
  static const int _maxDelayMax = 60;

  late final TextEditingController _queueLimitController;
  late final TextEditingController _maxDelayController;
  late final TextEditingController _ngWordsController;

  late final FocusNode _queueLimitFocusNode;
  late final FocusNode _maxDelayFocusNode;
  late final FocusNode _ngWordsFocusNode;

  @override
  SettingsStore get settingsStore => widget.settingsStore;

  String? _queueLimitError;
  String? _maxDelayError;

  @override
  void initState() {
    super.initState();
    _queueLimitController = TextEditingController();
    _maxDelayController = TextEditingController();
    _ngWordsController = TextEditingController();

    _queueLimitFocusNode = FocusNode()..addListener(_onQueueLimitFocusChanged);
    _maxDelayFocusNode = FocusNode()..addListener(_onMaxDelayFocusChanged);
    _ngWordsFocusNode = FocusNode()..addListener(_onNgWordsFocusChanged);

    loadSettings();
  }

  @override
  void dispose() {
    _queueLimitFocusNode
      ..removeListener(_onQueueLimitFocusChanged)
      ..dispose();
    _maxDelayFocusNode
      ..removeListener(_onMaxDelayFocusChanged)
      ..dispose();
    _ngWordsFocusNode
      ..removeListener(_onNgWordsFocusChanged)
      ..dispose();
    _queueLimitController.dispose();
    _maxDelayController.dispose();
    _ngWordsController.dispose();
    super.dispose();
  }

  @override
  Future<void> loadSettings() async {
    await super.loadSettings();
    final AppSettings? loaded = settings;
    if (loaded == null) {
      return;
    }
    _queueLimitController.text = loaded.queueLimit.toString();
    _maxDelayController.text = loaded.maxDelaySeconds.toString();
    _ngWordsController.text = loaded.ngWords;
  }

  @override
  void updateAndSave(AppSettings next) {
    debugPrint(
        '[TtsSettings] save: autoRead=${next.autoReadEnabled}, engine=${next.speechEngine}, speaker=${next.voicevoxSpeaker}, speed=${next.voicevoxSpeed}');
    super.updateAndSave(next);
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

  void _saveNgWords() {
    final AppSettings? current = settings;
    if (current == null) {
      return;
    }

    final String ngWords = _ngWordsController.text;
    if (ngWords == current.ngWords) {
      return;
    }

    // TODO(issue-12-followup): NGワードは正規表現入力のため、保存前に
    // RegExp.tryParse 相当で妥当性を検証し、無効パターンは保存を抑止する。
    updateAndSave(current.copyWith(ngWords: ngWords));
  }

  void _saveQueueLimit() {
    final AppSettings? current = settings;
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

    updateAndSave(current.copyWith(queueLimit: parsed));
  }

  void _saveMaxDelaySeconds() {
    final AppSettings? current = settings;
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

    updateAndSave(current.copyWith(maxDelaySeconds: parsed));
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

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
                        updateAndSave(
                            settings.copyWith(autoReadEnabled: value));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                        updateAndSave(
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
                        updateAndSave(settings.copyWith(voicevoxSpeed: value));
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
                        updateAndSave(settings.copyWith(voicevoxPitch: value));
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
                        updateAndSave(
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
                        updateAndSave(settings.copyWith(voicevoxVolume: value));
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
                        updateAndSave(
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
                        updateAndSave(
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
                        updateAndSave(settings.copyWith(omitUrl: value));
                      },
                    ),
                    SwitchListTile(
                      key: const Key('suppress-duplicate-switch'),
                      title: const Text('連投抑制'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.suppressDuplicate,
                      onChanged: (bool value) {
                        updateAndSave(
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
                        await loadSettings();
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
