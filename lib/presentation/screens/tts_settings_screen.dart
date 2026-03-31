import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/voicevox_model_info.dart';
import '../widgets/settings_widgets.dart';
import 'dictionary_rules_screen.dart';
import 'ng_user_list_screen.dart';
import 'voice_library_screen.dart';

// TODO(#13): 棒読みちゃん対応は UIから非表示とした。サーバーを管理しない方針のため、
// 今後削除するか再実装するかは未定。万が一機会があれば再検討する。
// 棒読みちゃん関連のドメインモデル・設定ストアのフィールドは後方互換のため残している。
class TtsSettingsScreen extends StatefulWidget {
  const TtsSettingsScreen({
    super.key,
    required this.settingsStore,
    this.platform,
  });

  final SettingsStore settingsStore;
  final CommentSpeechPlatform? platform;

  @override
  State<TtsSettingsScreen> createState() => _TtsSettingsScreenState();
}

class _TtsSettingsScreenState extends State<TtsSettingsScreen> {
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

  AppSettings? _settings;
  List<VoicevoxModelInfo>? _voicevoxModels;
  String? _queueLimitError;
  String? _maxDelayError;
  bool _isLoadingModel = false;

  /// Generation counter to discard stale model-load results when the user
  /// changes the speaker multiple times in quick succession.
  int _speakerChangeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _queueLimitController = TextEditingController();
    _maxDelayController = TextEditingController();
    _ngWordsController = TextEditingController();

    _queueLimitFocusNode = FocusNode()..addListener(_onQueueLimitFocusChanged);
    _maxDelayFocusNode = FocusNode()..addListener(_onMaxDelayFocusChanged);
    _ngWordsFocusNode = FocusNode()..addListener(_onNgWordsFocusChanged);

    _loadSettings();
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

  Future<void> _loadSettings() async {
    final AppSettings loaded = await widget.settingsStore.load();
    if (!mounted) {
      return;
    }

    _queueLimitController.text = loaded.queueLimit.toString();
    _maxDelayController.text = loaded.maxDelaySeconds.toString();
    _ngWordsController.text = loaded.ngWords;

    if (widget.platform != null) {
      await _refreshVoicevoxModels();
    }

    setState(() {
      _settings = loaded;
    });
  }

  Future<void> _refreshVoicevoxModels() async {
    final platform = widget.platform;
    if (platform == null) return;
    try {
      final rawList = await platform.getAvailableModels();
      final allModels =
          rawList.map((m) => VoicevoxModelInfo.fromMap(m)).toList();
      if (!mounted) return;
      setState(() {
        _voicevoxModels = allModels;
      });
    } on Object {
      // Model listing failed; keep existing state.
    }
  }

  /// Load the VVM model corresponding to [speakerId] into the native engine.
  ///
  /// Returns `true` when the model was loaded successfully, `false` otherwise.
  Future<bool> _loadModelForSpeaker(int speakerId) async {
    final platform = widget.platform;
    final models = _voicevoxModels;
    if (platform == null || models == null) return false;

    // Find which model contains this speaker ID.
    VoicevoxModelInfo? model;
    for (final m in models) {
      if (m.speakerIds.contains(speakerId)) {
        model = m;
        break;
      }
    }
    if (model == null) return false;

    try {
      await platform.loadModel(model.modelId);
      return true;
    } on Object catch (e) {
      debugPrint('[TtsSettings] loadModel FAILED for speaker $speakerId: $e');
      return false;
    }
  }

  /// Handle speaker change: save immediately, load the model, then push
  /// settings to the engine only after the model is ready.
  Future<void> _onSpeakerChanged(AppSettings settings, int newSpeaker) async {
    final int previousSpeaker = settings.voicevoxSpeaker;
    final int generation = ++_speakerChangeGeneration;

    // Optimistically update the UI and persist the new speaker.
    final AppSettings next = settings.copyWith(voicevoxSpeaker: newSpeaker);
    setState(() {
      _settings = next;
      _isLoadingModel = true;
    });
    unawaited(_saveSettings(next));

    final bool success = await _loadModelForSpeaker(newSpeaker);

    // If another speaker change happened while we were loading, discard this
    // result — the newer change takes precedence.
    if (generation != _speakerChangeGeneration || !mounted) return;

    if (success) {
      setState(() {
        _isLoadingModel = false;
      });
      _pushSettingsToEngine(next);
    } else {
      // Revert to the previous speaker and notify the user.
      final AppSettings reverted =
          next.copyWith(voicevoxSpeaker: previousSpeaker);
      setState(() {
        _settings = reverted;
        _isLoadingModel = false;
      });
      unawaited(_saveSettings(reverted));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('speaker-load-error-snackbar'),
            content: Text('話者の読み込みに失敗しました。前の話者に戻します。'),
          ),
        );
      }
    }
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
    _pushSettingsToEngine(next);
  }

  /// Push the current settings to the native speech engine so that changes
  /// (speed, pitch, intonation, volume, speaker, etc.) take effect immediately
  /// without requiring the user to navigate back.
  void _pushSettingsToEngine(AppSettings settings) {
    final platform = widget.platform;
    if (platform == null) return;

    unawaited(
      platform.updateSettings(settings.toSpeechSettings()).catchError(
        (Object e) {
          debugPrint('[TtsSettings] pushSettings FAILED: $e');
        },
      ),
    );
  }

  Future<void> _saveSettings(AppSettings next) =>
      saveSettingsToStore(widget.settingsStore, next);

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

  String _buildCreditText(int speakerId) {
    final List<VoicevoxModelInfo>? models = _voicevoxModels;
    if (models != null) {
      for (final model in models) {
        if (model.speakerIds.contains(speakerId)) {
          return 'Credit: ${model.displayName}';
        }
      }
    }
    // Nemo speaker IDs: 10000..10008
    if (speakerId >= 10000 && speakerId <= 10008) {
      return 'Credit: VOICEVOX Nemo';
    }
    return 'Credit: VOICEVOX';
  }

  Widget _buildVoicevoxSpeakerDropdown(AppSettings settings) {
    final List<VoicevoxModelInfo>? models = _voicevoxModels;

    // When models are available, build items from downloaded/bundled models.
    if (models != null && models.isNotEmpty) {
      final List<DropdownMenuItem<int>> items = [];
      for (final model in models) {
        if (model.downloadState != ModelDownloadState.downloaded &&
            !model.isBundled) {
          continue;
        }
        for (final speakerId in model.speakerIds) {
          items.add(
            DropdownMenuItem<int>(
              value: speakerId,
              child: Text('${model.displayName} (ID:$speakerId)'),
            ),
          );
        }
      }

      // If the current speaker is not in the list, add a fallback entry
      // to avoid a Flutter assertion error.
      final bool currentInList =
          items.any((item) => item.value == settings.voicevoxSpeaker);
      if (!currentInList && items.isNotEmpty) {
        // Defer the state update to avoid calling setState during build.
        final int firstSpeaker = items.first.value!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateAndSave(settings.copyWith(voicevoxSpeaker: firstSpeaker));
          }
        });
      }

      if (items.isEmpty) {
        items.add(
          const DropdownMenuItem<int>(
            value: 10000,
            child: Text('VOICEVOX Nemo・男声2 (ID:10000)'),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            key: const Key('voicevox-speaker-dropdown'),
            value: currentInList ? settings.voicevoxSpeaker : items.first.value,
            decoration: const InputDecoration(
              labelText: '話者',
              border: OutlineInputBorder(),
            ),
            items: items,
            onChanged: _isLoadingModel
                ? null
                : (int? value) {
                    if (value == null) return;
                    _onSpeakerChanged(settings, value);
                  },
          ),
          if (_isLoadingModel)
            Semantics(
              label: '話者モデルを読み込み中',
              child: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(
                  key: Key('speaker-loading-indicator'),
                ),
              ),
            ),
        ],
      );
    }

    // Fallback: static dropdown when platform is not available.
    return DropdownButtonFormField<int>(
      key: const Key('voicevox-speaker-dropdown'),
      value: settings.voicevoxSpeaker,
      decoration: const InputDecoration(
        labelText: '話者',
        border: OutlineInputBorder(),
      ),
      items: const <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(
          value: 10000,
          child: Text('VOICEVOX Nemo・男声2 (ID:10000)'),
        ),
      ],
      onChanged: (int? value) {
        if (value == null) return;
        _updateAndSave(settings.copyWith(voicevoxSpeaker: value));
      },
    );
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
                    SwitchListTile(
                      key: const Key('read-user-name-switch'),
                      title: const Text('名前を読み上げる'),
                      subtitle: const Text('ONにすると「名前、コメント」の形式で読み上げます'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.readUserName,
                      onChanged: (bool value) {
                        _updateAndSave(settings.copyWith(readUserName: value));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SettingsSection(
                  key: const Key('voicevox-section'),
                  title: 'VOICEVOX',
                  children: <Widget>[
                    _buildVoicevoxSpeakerDropdown(settings),
                    if (widget.platform != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          key: const Key('voicevox-add-speaker-btn'),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => VoiceLibraryScreen(
                                  platform: widget.platform!,
                                ),
                              ),
                            );
                            await _refreshVoicevoxModels();
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('話者を追加'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SettingsDoubleSliderField(
                      key: const Key('voicevox-speed-slider'),
                      label: '話速',
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      value: settings.voicevoxSpeed,
                      onChanged: (double value) {
                        _updateAndSave(settings.copyWith(voicevoxSpeed: value));
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
                        _updateAndSave(settings.copyWith(voicevoxPitch: value));
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
                    const SizedBox(height: 12),
                    Text(
                      _buildCreditText(settings.voicevoxSpeaker),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
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
                      key: const Key('dictionary-rules-tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.book),
                      title: const Text('読み上げ辞書'),
                      subtitle: Text(
                        settings.dictionaryRules.isEmpty
                            ? '未登録'
                            : '${settings.dictionaryRules.length}件登録中',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DictionaryRulesScreen(
                              settingsStore: widget.settingsStore,
                            ),
                          ),
                        );
                        await _loadSettings();
                        if (_settings != null) {
                          _pushSettingsToEngine(_settings!);
                        }
                      },
                    ),
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
                        if (_settings != null) {
                          _pushSettingsToEngine(_settings!);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
