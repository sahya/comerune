import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_logging.dart';
import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/voicevox_model_info.dart';
import '../mixins/settings_screen_mixin.dart';
import '../widgets/settings_widgets.dart';
import 'dictionary_rules_screen.dart';
import 'voice_library_screen.dart';

enum _NemoStylePreset { standard, energetic, calm }

void _debugLogLazy(String Function() messageBuilder) {
  appDebugLogLazy(messageBuilder);
}

void _errorLog(String message, {Object? error, StackTrace? stackTrace}) {
  appErrorLog(
    name: 'TtsSettings',
    message: message,
    error: error,
    stackTrace: stackTrace,
  );
}

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

class _TtsSettingsScreenState extends State<TtsSettingsScreen>
    with SettingsScreenMixin {
  static const int _queueLimitMin = 1;
  static const int _queueLimitMax = 100;
  static const int _maxDelayMin = 1;
  static const int _maxDelayMax = 60;
  static const double _energeticPresetSpeed = 1.3;
  static const double _energeticPresetPitch = 0.08;
  static const double _energeticPresetIntonation = 1.3;
  static const double _energeticPresetVolume = 1.0;
  static const double _calmPresetSpeed = 1.0;
  static const double _calmPresetPitch = -0.02;
  static const double _calmPresetIntonation = 0.9;
  static const double _calmPresetVolume = 1.0;
  static const double _standardPresetSpeed = 1.0;
  static const double _standardPresetPitch = 0.0;
  static const double _standardPresetIntonation = 1.0;
  static const double _standardPresetVolume = 1.0;

  late final TextEditingController _queueLimitController;
  late final TextEditingController _maxDelayController;
  late final TextEditingController _ngWordsController;

  late final FocusNode _queueLimitFocusNode;
  late final FocusNode _maxDelayFocusNode;
  late final FocusNode _ngWordsFocusNode;

  @override
  SettingsStore get settingsStore => widget.settingsStore;

  List<VoicevoxModelInfo>? _voicevoxModels;
  Set<int> _nemoSpeakerIds = <int>{};
  String? _queueLimitError;
  String? _maxDelayError;
  String? _ngWordsError;
  bool _isLoadingModel = false;

  static const Map<int, String> _nemoSpeakerNames = <int, String>{
    10000: '男声2',
    10001: '男声1',
    10002: '男声3',
    10003: '女声4',
    10004: '女声3',
    10005: '女声1',
    10006: '女声6',
    10007: '女声2',
    10008: '女声5',
  };

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
  void onSettingsLoaded(AppSettings loaded) {
    _queueLimitController.text = loaded.queueLimit.toString();
    _maxDelayController.text = loaded.maxDelaySeconds.toString();
    _ngWordsController.text = loaded.ngWords;
  }

  @override
  Future<void> loadSettings() async {
    final AppSettings loaded = await settingsStore.load();
    if (!mounted) {
      return;
    }

    onSettingsLoaded(loaded);

    if (widget.platform != null) {
      await _refreshVoicevoxModels();
    }

    setState(() {
      settings = loaded;
    });
  }

  Future<void> _refreshVoicevoxModels() async {
    final platform = widget.platform;
    if (platform == null) return;
    try {
      final rawList = await platform.getAvailableModels();
      final allModels =
          rawList.map((m) => VoicevoxModelInfo.fromMap(m)).toList();
      final Set<int> nemoSpeakerIds = <int>{};
      for (final VoicevoxModelInfo model in allModels) {
        if (model.modelId == 'n0') {
          nemoSpeakerIds.addAll(model.speakerIds);
        }
      }
      if (!mounted) return;
      setState(() {
        _voicevoxModels = allModels;
        _nemoSpeakerIds = nemoSpeakerIds;
      });
    } on Object {
      // Model listing failed; keep existing state.
    }
  }

  /// Load the VVM model corresponding to [speakerId] into the native engine.
  ///
  /// Returns `true` when the model was loaded successfully, `false` otherwise.
  Future<bool> _loadModelForSpeaker(
    int speakerId, {
    int? fallbackCurrentSpeakerId,
  }) async {
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
    final VoicevoxModelInfo selectedModel = model;

    try {
      _debugLogLazy(
        () =>
            '[TtsSettings] loadModel begin: speaker=$speakerId modelId=${selectedModel.modelId}',
      );
      await ensureEngineReadyForModelLoad(
        platform,
        logTag: '[TtsSettings]',
        pollInterval: voicevoxReadyPollInterval,
        maxPollAttempts: voicevoxReadyMaxPollAttempts,
      );
      int? currentSpeakerId;
      try {
        final SpeechRuntimeStatus status = await platform.getStatus();
        currentSpeakerId = status.currentSpeakerId;
        _debugLogLazy(
          () =>
              '[TtsSettings] status-check(skip-guard): currentSpeaker=$currentSpeakerId '
              'targetSpeaker=$speakerId modelId=${selectedModel.modelId}',
        );
      } on Object catch (e) {
        // Fallback to loading the model when status refresh fails.
        _errorLog(
          '[TtsSettings] loadModel decision=load_model '
          'reason=status_refresh_failed '
          'speaker=$speakerId modelId=${selectedModel.modelId}',
          error: e,
        );
      }
      if (currentSpeakerId == null && fallbackCurrentSpeakerId != null) {
        currentSpeakerId = fallbackCurrentSpeakerId;
        _debugLogLazy(
          () =>
              '[TtsSettings] status-check(skip-guard): using settings fallback '
              'currentSpeaker=$currentSpeakerId targetSpeaker=$speakerId',
        );
      }
      if (currentSpeakerId != null &&
          _isSpeakerInSameModel(currentSpeakerId, speakerId, models)) {
        _debugLogLazy(
          () => '[TtsSettings] loadModel decision=skip_same_model '
              'currentSpeaker=$currentSpeakerId '
              'and targetSpeaker=$speakerId are in same modelId=${selectedModel.modelId}',
        );
        return true;
      }
      _debugLogLazy(
        () => '[TtsSettings] loadModel decision=load_model '
            'speaker=$speakerId modelId=${selectedModel.modelId}',
      );
      await platform.loadModel(selectedModel.modelId);
      _debugLogLazy(
        () =>
            '[TtsSettings] loadModel success: speaker=$speakerId modelId=${selectedModel.modelId}',
      );
      return true;
    } on Object catch (e) {
      _errorLog(
        '[TtsSettings] loadModel FAILED: speaker=$speakerId modelId=${selectedModel.modelId}',
        error: e,
      );
      return false;
    }
  }

  bool _isSpeakerInSameModel(
    int currentSpeakerId,
    int targetSpeakerId,
    List<VoicevoxModelInfo> models,
  ) {
    String? currentModelId;
    String? targetModelId;

    for (final VoicevoxModelInfo m in models) {
      if (currentModelId == null && m.speakerIds.contains(currentSpeakerId)) {
        currentModelId = m.modelId;
      }
      if (targetModelId == null && m.speakerIds.contains(targetSpeakerId)) {
        targetModelId = m.modelId;
      }
      if (currentModelId != null && targetModelId != null) {
        break;
      }
    }

    return currentModelId != null &&
        targetModelId != null &&
        currentModelId == targetModelId;
  }

  /// Handle speaker change: save immediately, load the model, then push
  /// settings to the engine only after the model is ready.
  Future<void> _onSpeakerChanged(AppSettings current, int newSpeaker) async {
    if (newSpeaker == current.voicevoxSpeaker) {
      _debugLogLazy(
        () => '[TtsSettings] speaker change decision=no_op_same_speaker '
            'fromSpeaker=${current.voicevoxSpeaker} toSpeaker=$newSpeaker',
      );
      return;
    }

    final int previousSpeaker = current.voicevoxSpeaker;
    final int generation = ++_speakerChangeGeneration;
    _debugLogLazy(
      () => '[TtsSettings] speaker change requested: '
          'fromSpeaker=$previousSpeaker toSpeaker=$newSpeaker '
          'generation=$generation',
    );

    // Optimistically update the UI and persist the new speaker.
    final AppSettings next = current.copyWith(voicevoxSpeaker: newSpeaker);
    setState(() {
      settings = next;
      _isLoadingModel = true;
    });
    unawaited(saveSettings(next));

    final bool success = await _loadModelForSpeaker(
      newSpeaker,
      fallbackCurrentSpeakerId: previousSpeaker,
    );

    // If another speaker change happened while we were loading, discard this
    // result -- the newer change takes precedence.
    if (generation != _speakerChangeGeneration) {
      _debugLogLazy(
        () => '[TtsSettings] speaker change discarded stale result: '
            'reason=stale_generation '
            'fromSpeaker=$previousSpeaker toSpeaker=$newSpeaker '
            'generation=$generation latestGeneration=$_speakerChangeGeneration',
      );
      return;
    }
    if (!mounted) {
      _debugLogLazy(
        () => '[TtsSettings] speaker change discarded result: '
            'reason=widget_unmounted '
            'fromSpeaker=$previousSpeaker toSpeaker=$newSpeaker '
            'generation=$generation latestGeneration=$_speakerChangeGeneration',
      );
      return;
    }

    if (success) {
      setState(() {
        _isLoadingModel = false;
      });
      _debugLogLazy(
        () => '[TtsSettings] speaker change applied: '
            'fromSpeaker=$previousSpeaker toSpeaker=$newSpeaker',
      );
      _pushSettingsToEngine(next);
    } else {
      // Revert to the previous speaker and notify the user.
      final AppSettings reverted = next.copyWith(
        voicevoxSpeaker: previousSpeaker,
      );
      setState(() {
        settings = reverted;
        _isLoadingModel = false;
      });
      unawaited(saveSettings(reverted));
      _debugLogLazy(
        () => '[TtsSettings] speaker change reverted: '
            'fromSpeaker=$previousSpeaker toSpeaker=$newSpeaker '
            'revertedToSpeaker=$previousSpeaker',
      );

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

  @override
  void updateAndSave(AppSettings next) {
    _debugLogLazy(
      () => '[TtsSettings] save: autoRead=${next.autoReadEnabled}, '
          'engine=${next.speechEngine}, speaker=${next.voicevoxSpeaker}, '
          'speed=${next.voicevoxSpeed}',
    );
    super.updateAndSave(next);
    _pushSettingsToEngine(next);
  }

  /// Push the current settings to the native speech engine so that changes
  /// (speed, pitch, intonation, volume, speaker, etc.) take effect immediately
  /// without requiring the user to navigate back.
  void _pushSettingsToEngine(AppSettings settings) {
    final platform = widget.platform;
    if (platform == null) return;

    unawaited(
      platform.updateSettings(settings.toSpeechSettings()).catchError((
        Object e,
      ) {
        _errorLog('[TtsSettings] pushSettings FAILED', error: e);
      }),
    );
  }

  void _applyVoicevoxPreset(
    AppSettings current, {
    required double speed,
    required double pitch,
    required double intonation,
    required double volume,
  }) {
    updateAndSave(
      current.copyWith(
        voicevoxSpeed: speed,
        voicevoxPitch: pitch,
        voicevoxIntonation: intonation,
        voicevoxVolume: volume,
      ),
    );
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

    final String? invalidPattern = _findInvalidRegExpPattern(ngWords);
    if (invalidPattern != null) {
      setState(() {
        final String display = invalidPattern.length > 30
            ? '${invalidPattern.substring(0, 30)}...'
            : invalidPattern;
        _ngWordsError = '無効な正規表現: $display';
      });
      return;
    }

    setState(() {
      _ngWordsError = null;
    });
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

  static String? _findInvalidRegExpPattern(String ngWords) {
    final List<String> lines = ngWords.split('\n');
    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        RegExp(trimmed);
      } on FormatException {
        return trimmed;
      }
    }
    return null;
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

  String _buildPerformanceHint(AppSettings settings) {
    final bool isAudioQuery =
        settings.voicevoxSynthesisMode == SynthesisMode.audioQuery;
    final bool isAudioTrack =
        settings.voicevoxPlayerType == VoicevoxPlayerType.audioTrack;

    if (isAudioQuery && isAudioTrack) {
      return '応答が速く、声の調整も可能な構成です（推奨）';
    } else if (!isAudioQuery && isAudioTrack) {
      return '最速ですが、話速・音高などの調整はできません';
    } else if (isAudioQuery && !isAudioTrack) {
      return '声の調整ができますが、応答はやや遅くなります';
    } else {
      return '調整なしで互換再生です。特殊な端末向けです';
    }
  }

  Widget _buildPerformanceSection(AppSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '音声処理',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '音声合成',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        SegmentedButton<SynthesisMode>(
          key: const Key('synthesis-mode-selector'),
          segments: const <ButtonSegment<SynthesisMode>>[
            ButtonSegment<SynthesisMode>(
              value: SynthesisMode.audioQuery,
              label: Text('高品質（調整あり）'),
            ),
            ButtonSegment<SynthesisMode>(
              value: SynthesisMode.oneShot,
              label: Text('低遅延（調整なし）'),
            ),
          ],
          selected: <SynthesisMode>{settings.voicevoxSynthesisMode},
          onSelectionChanged: (Set<SynthesisMode> selected) {
            updateAndSave(
              settings.copyWith(voicevoxSynthesisMode: selected.first),
            );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<VoicevoxPlayerType>(
          key: const Key('player-type-dropdown'),
          value: settings.voicevoxPlayerType,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: '再生方式',
          ),
          items: const <DropdownMenuItem<VoicevoxPlayerType>>[
            DropdownMenuItem<VoicevoxPlayerType>(
              value: VoicevoxPlayerType.audioTrack,
              child: Text('低遅延モード（推奨）'),
            ),
            DropdownMenuItem<VoicevoxPlayerType>(
              value: VoicevoxPlayerType.mediaPlayer,
              child: Text('互換モード'),
            ),
          ],
          onChanged: (VoicevoxPlayerType? value) {
            if (value != null) {
              updateAndSave(
                settings.copyWith(voicevoxPlayerType: value),
              );
            }
          },
        ),
        const SizedBox(height: 4),
        Text(
          _buildPerformanceHint(settings),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  Widget _buildVoicevoxSpeakerDropdown(AppSettings settings) {
    final List<VoicevoxModelInfo>? models = _voicevoxModels;
    const int fallbackSpeakerId = 10000;

    // When models are available, build items from downloaded/bundled models.
    if (models != null && models.isNotEmpty) {
      final List<DropdownMenuItem<int>> items = [];
      for (final model in models) {
        if (model.downloadState != ModelDownloadState.downloaded &&
            !model.isBundled) {
          continue;
        }
        final List<int> orderedSpeakerIds = _orderedSpeakerIds(model);
        for (final speakerId in orderedSpeakerIds) {
          items.add(
            DropdownMenuItem<int>(
              value: speakerId,
              child: Text(_speakerMenuLabel(model, speakerId)),
            ),
          );
        }
      }

      // If the current speaker is not in the list, add a fallback entry
      // to avoid a Flutter assertion error.
      final bool currentInList = items.any(
        (item) => item.value == settings.voicevoxSpeaker,
      );
      if (!currentInList && items.isNotEmpty) {
        // Defer the state update to avoid calling setState during build.
        final int firstSpeaker = items.first.value!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            updateAndSave(settings.copyWith(voicevoxSpeaker: firstSpeaker));
          }
        });
      }

      if (items.isEmpty) {
        items.add(
          const DropdownMenuItem<int>(
            value: fallbackSpeakerId,
            child: Text('Nemo | 男声2 (ID:10000)'),
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
    final bool fallbackCurrentInList =
        settings.voicevoxSpeaker == fallbackSpeakerId;
    if (!fallbackCurrentInList) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          updateAndSave(settings.copyWith(voicevoxSpeaker: fallbackSpeakerId));
        }
      });
    }

    return DropdownButtonFormField<int>(
      key: const Key('voicevox-speaker-dropdown'),
      value:
          fallbackCurrentInList ? settings.voicevoxSpeaker : fallbackSpeakerId,
      decoration: const InputDecoration(
        labelText: '話者',
        border: OutlineInputBorder(),
      ),
      items: const <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(
          value: fallbackSpeakerId,
          child: Text('Nemo | 男声2 (ID:10000)'),
        ),
      ],
      onChanged: (int? value) {
        if (value == null) return;
        updateAndSave(settings.copyWith(voicevoxSpeaker: value));
      },
    );
  }

  String _speakerMenuLabel(VoicevoxModelInfo model, int speakerId) {
    if (model.modelId == 'n0') {
      // TTS設定のプルダウンは横幅が限られるため、接頭辞を短くして
      // 話者名/ID（後半）が見切れにくい表示を優先する。
      // なお、規約同意と紐づく正式名は Credit や VoiceLibrary 側で保持する。
      final String? speakerName = _nemoSpeakerNames[speakerId];
      if (speakerName != null) {
        return 'Nemo | $speakerName (ID:$speakerId)';
      }
      return 'Nemo | Unknown (ID:$speakerId)';
    }
    return '${model.displayName} (ID:$speakerId)';
  }

  List<int> _orderedSpeakerIds(VoicevoxModelInfo model) {
    if (model.modelId != 'n0') {
      return model.speakerIds;
    }
    final List<int> ordered = List<int>.from(model.speakerIds);
    ordered.sort(_compareNemoSpeakerOrder);
    return ordered;
  }

  int _compareNemoSpeakerOrder(int a, int b) {
    final RegExp pattern = RegExp(r'^(男声|女声)(\d+)$');

    final Match? aMatch = pattern.firstMatch(_nemoSpeakerNames[a] ?? '');
    final Match? bMatch = pattern.firstMatch(_nemoSpeakerNames[b] ?? '');
    if (aMatch == null || bMatch == null) {
      return a.compareTo(b);
    }

    final String aType = aMatch.group(1)!;
    final String bType = bMatch.group(1)!;
    final int aTypeRank = aType == '女声' ? 0 : 1;
    final int bTypeRank = bType == '女声' ? 0 : 1;

    if (aTypeRank != bTypeRank) {
      return aTypeRank.compareTo(bTypeRank);
    }

    final int aIndex = int.parse(aMatch.group(2)!);
    final int bIndex = int.parse(bMatch.group(2)!);
    if (aIndex != bIndex) {
      return aIndex.compareTo(bIndex);
    }
    return a.compareTo(b);
  }

  bool _isNemoPresetVisible(AppSettings settings) {
    final int speakerId = settings.voicevoxSpeaker;
    if (_nemoSpeakerNames.containsKey(speakerId)) {
      return true;
    }
    return _nemoSpeakerIds.contains(speakerId);
  }

  bool _matchesNemoPreset(
    AppSettings settings, {
    required double speed,
    required double pitch,
    required double intonation,
    required double volume,
  }) {
    const double epsilon = 0.0001;
    return (settings.voicevoxSpeed - speed).abs() <= epsilon &&
        (settings.voicevoxPitch - pitch).abs() <= epsilon &&
        (settings.voicevoxIntonation - intonation).abs() <= epsilon &&
        (settings.voicevoxVolume - volume).abs() <= epsilon;
  }

  _NemoStylePreset _currentNemoStyleValue(AppSettings settings) {
    if (_matchesNemoPreset(
      settings,
      speed: _energeticPresetSpeed,
      pitch: _energeticPresetPitch,
      intonation: _energeticPresetIntonation,
      volume: _energeticPresetVolume,
    )) {
      return _NemoStylePreset.energetic;
    }
    if (_matchesNemoPreset(
      settings,
      speed: _calmPresetSpeed,
      pitch: _calmPresetPitch,
      intonation: _calmPresetIntonation,
      volume: _calmPresetVolume,
    )) {
      return _NemoStylePreset.calm;
    }
    return _NemoStylePreset.standard;
  }

  void _applyNemoStyle(AppSettings settings, _NemoStylePreset styleValue) {
    switch (styleValue) {
      case _NemoStylePreset.energetic:
        _applyVoicevoxPreset(
          settings,
          speed: _energeticPresetSpeed,
          pitch: _energeticPresetPitch,
          intonation: _energeticPresetIntonation,
          volume: _energeticPresetVolume,
        );
        return;
      case _NemoStylePreset.calm:
        _applyVoicevoxPreset(
          settings,
          speed: _calmPresetSpeed,
          pitch: _calmPresetPitch,
          intonation: _calmPresetIntonation,
          volume: _calmPresetVolume,
        );
        return;
      case _NemoStylePreset.standard:
        _applyVoicevoxPreset(
          settings,
          speed: _standardPresetSpeed,
          pitch: _standardPresetPitch,
          intonation: _standardPresetIntonation,
          volume: _standardPresetVolume,
        );
        return;
    }
  }

  Widget _buildNemoStyleDropdown(AppSettings settings) {
    return DropdownButtonFormField<_NemoStylePreset>(
      key: const Key('voicevox-style-dropdown'),
      value: _currentNemoStyleValue(settings),
      decoration: const InputDecoration(
        labelText: 'スタイル',
        border: OutlineInputBorder(),
      ),
      items: const <DropdownMenuItem<_NemoStylePreset>>[
        DropdownMenuItem<_NemoStylePreset>(
          value: _NemoStylePreset.standard,
          child: Text('標準'),
        ),
        DropdownMenuItem<_NemoStylePreset>(
          value: _NemoStylePreset.energetic,
          child: Text('元気'),
        ),
        DropdownMenuItem<_NemoStylePreset>(
          value: _NemoStylePreset.calm,
          child: Text('落ち着き'),
        ),
      ],
      onChanged: _isLoadingModel
          ? null
          : (_NemoStylePreset? value) {
              if (value == null) return;
              _applyNemoStyle(settings, value);
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings? settings = this.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('読み上げ設定')),
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
                          settings.copyWith(autoReadEnabled: value),
                        );
                      },
                    ),
                    SwitchListTile(
                      key: const Key('read-user-name-switch'),
                      title: const Text('名前を読み上げる'),
                      subtitle: const Text('ONにすると「名前、コメント」の形式で読み上げます'),
                      contentPadding: EdgeInsets.zero,
                      value: settings.readUserName,
                      onChanged: (bool value) {
                        updateAndSave(settings.copyWith(readUserName: value));
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
                                  settingsStore: widget.settingsStore,
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
                    if (_isNemoPresetVisible(settings)) ...[
                      const SizedBox(height: 8),
                      _buildNemoStyleDropdown(settings),
                    ],
                    const SizedBox(height: 16),
                    _buildPerformanceSection(settings),
                    const SizedBox(height: 16),
                    Text(
                      '声の調整',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (settings.voicevoxSynthesisMode ==
                        SynthesisMode.audioQuery) ...[
                      SettingsDoubleSliderField(
                        key: const Key('voicevox-speed-slider'),
                        label: '話速',
                        min: 0.5,
                        max: 2.0,
                        divisions: 15,
                        value: settings.voicevoxSpeed,
                        onChanged: (double value) {
                          updateAndSave(
                            settings.copyWith(voicevoxSpeed: value),
                          );
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
                          updateAndSave(
                            settings.copyWith(voicevoxPitch: value),
                          );
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
                    ],
                    SettingsDoubleSliderField(
                      key: const Key('voicevox-volume-slider'),
                      label: '音量',
                      min: 0.0,
                      max: 2.0,
                      divisions: 20,
                      value: settings.voicevoxVolume,
                      onChanged: (double value) {
                        updateAndSave(
                          settings.copyWith(voicevoxVolume: value),
                        );
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
                          settings.copyWith(suppressDuplicate: value),
                        );
                      },
                    ),
                    TextFormField(
                      key: const Key('ng-words-field'),
                      controller: _ngWordsController,
                      focusNode: _ngWordsFocusNode,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'NGワード（正規表現）',
                        hintText: '例: ^8+\$',
                        border: const OutlineInputBorder(),
                        errorText: _ngWordsError,
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
                        await loadSettings();
                        if (this.settings != null) {
                          _pushSettingsToEngine(this.settings!);
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
