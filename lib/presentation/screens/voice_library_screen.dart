import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/voicevox_model_info.dart';

class VoiceLibraryScreen extends StatefulWidget {
  const VoiceLibraryScreen({
    super.key,
    required this.platform,
    required this.settingsStore,
  });

  final CommentSpeechPlatform platform;
  final SettingsStore settingsStore;

  @override
  State<VoiceLibraryScreen> createState() => _VoiceLibraryScreenState();
}

class _VoiceLibraryScreenState extends State<VoiceLibraryScreen> {
  late final VoicevoxModelManager _manager;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _manager = VoicevoxModelManager(widget.platform);
    _manager.startListening();
    _loadModels();
  }

  Future<void> _loadModels() async {
    try {
      await _manager.refreshModels();
      if (mounted) setState(() => _loadError = false);
    } on Object {
      if (mounted) setState(() => _loadError = true);
    }
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('話者ライブラリ'),
      ),
      body: ValueListenableBuilder<List<VoicevoxModelInfo>>(
        valueListenable: _manager.models,
        builder: (context, models, _) {
          if (_loadError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('話者の読み込みに失敗しました'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loadModels,
                    child: const Text('再試行'),
                  ),
                ],
              ),
            );
          }
          if (models.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<Map<String, double>>(
            valueListenable: _manager.downloadProgress,
            builder: (context, progress, _) {
              return ListView.builder(
                key: const Key('voice-library-list'),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: models.length,
                itemBuilder: (context, index) {
                  final model = models[index];
                  final modelProgress = progress[model.modelId];
                  return _VoiceModelCard(
                    key: Key('voice-model-card-${model.modelId}'),
                    model: model,
                    progress: modelProgress,
                    onDownload: () => _onDownload(model),
                    onDelete: () => _onDelete(model),
                    onCancel: () => _onCancel(model),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _onDownload(VoicevoxModelInfo model) async {
    // Check terms acceptance before downloading.
    final AppSettings settings = await widget.settingsStore.load();
    if (!settings.voicevoxTermsAccepted) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _VoicevoxTermsDialog(),
      );
      if (accepted != true) return;
      // Persist acceptance.
      final updated = settings.copyWith(voicevoxTermsAccepted: true);
      await widget.settingsStore.save(updated);
    }
    if (!mounted) return;
    try {
      debugPrint(
        '[VoiceLibrary] download start: modelId=${model.modelId}, name=${model.displayName}',
      );
      await _manager.downloadModel(model.modelId);
      debugPrint('[VoiceLibrary] download completed: modelId=${model.modelId}');
      await _ensureEngineReadyForModelLoad();
      // Automatically load the model into the engine after download.
      await _manager.loadModel(model.modelId);
      debugPrint(
        '[VoiceLibrary] loadModel success after download: modelId=${model.modelId}',
      );
    } on Object catch (e) {
      debugPrint(
          '[VoiceLibrary] download/load FAILED: modelId=${model.modelId} error=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ダウンロードに失敗しました: $e')),
      );
    }
  }

  Future<void> _ensureEngineReadyForModelLoad() async {
    final SpeechRuntimeStatus status = await widget.platform.getStatus();
    debugPrint(
        '[VoiceLibrary] ensureEngineReady: currentState=${status.engineState}');
    if (status.engineState == 'READY') {
      debugPrint('[VoiceLibrary] ensureEngineReady: already READY');
      return;
    }
    debugPrint('[VoiceLibrary] ensureEngineReady: calling initialize()');
    await widget.platform.initialize();
    debugPrint('[VoiceLibrary] ensureEngineReady: initialize() completed');
  }

  Future<void> _onDelete(VoicevoxModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('モデルの削除'),
        content: Text('${model.displayName} を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.deleteModel(model.modelId);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました: $e')),
      );
    }
  }

  Future<void> _onCancel(VoicevoxModelInfo model) async {
    try {
      await _manager.cancelDownload(model.modelId);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('キャンセルに失敗しました: $e')),
      );
    }
  }
}

class _VoiceModelCard extends StatelessWidget {
  const _VoiceModelCard({
    super.key,
    required this.model,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
  });

  final VoicevoxModelInfo model;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _buildStatusBadge(context),
              ],
            ),
            const SizedBox(height: 8),
            if (model.downloadState == ModelDownloadState.downloading &&
                progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text(
                '${(progress! * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (model.downloadState == ModelDownloadState.error)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ダウンロードに失敗しました',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.red),
                ),
              ),
            const SizedBox(height: 8),
            _buildAction(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    if (model.isBundled) {
      return _Badge(label: '内蔵', color: Colors.green);
    }
    switch (model.downloadState) {
      case ModelDownloadState.downloaded:
        return _Badge(label: 'ダウンロード済', color: Colors.blue);
      case ModelDownloadState.downloading:
        return _Badge(label: 'ダウンロード中', color: Colors.orange);
      case ModelDownloadState.error:
        return _Badge(label: 'エラー', color: Colors.red);
      case ModelDownloadState.notDownloaded:
        return Text(
          model.fileSizeDisplay,
          style: Theme.of(context).textTheme.bodySmall,
        );
    }
  }

  Widget _buildAction(BuildContext context) {
    if (model.isBundled) {
      return const SizedBox.shrink();
    }
    switch (model.downloadState) {
      case ModelDownloadState.notDownloaded:
      case ModelDownloadState.error:
        return Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: Key('download-btn-${model.modelId}'),
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: const Text('ダウンロード'),
          ),
        );
      case ModelDownloadState.downloaded:
        return Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: Key('delete-btn-${model.modelId}'),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('削除'),
          ),
        );
      case ModelDownloadState.downloading:
        return Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: Key('cancel-btn-${model.modelId}'),
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('キャンセル'),
          ),
        );
    }
  }
}

/// VOICEVOX 利用規約の同意ダイアログ。
///
/// 規約全文をスクロール表示し、末尾まで読んだ後に 3 秒のクールダウンを
/// 設けてから「同意する」ボタンを有効化する。
class _VoicevoxTermsDialog extends StatefulWidget {
  const _VoicevoxTermsDialog();

  @override
  State<_VoicevoxTermsDialog> createState() => _VoicevoxTermsDialogState();
}

class _VoicevoxTermsDialogState extends State<_VoicevoxTermsDialog> {
  final ScrollController _scrollController = ScrollController();
  String? _termsText;
  Widget? _termsContentCache;
  bool _hasScrolledToEnd = false;
  int _cooldownSeconds = 3;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    try {
      final text = await rootBundle.loadString(
        'android/app/src/main/assets/voicevox_models/TERMS.txt',
      );
      if (mounted) setState(() => _termsText = text);
      // After content is loaded and rendered, check if scrolling is needed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkScrollNeeded();
      });
    } on Object catch (e) {
      developer.log(
        'Failed to load TERMS.txt: $e',
        name: 'VoicevoxTermsDialog',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('規約の読み込みに失敗しました')),
        );
        Navigator.of(context).pop(false);
      }
    }
  }

  void _checkScrollNeeded() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) {
      // Content fits without scrolling – treat as fully read.
      setState(() => _hasScrolledToEnd = true);
      _startCooldown();
    }
  }

  void _onScroll() {
    if (_hasScrolledToEnd) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 20) {
      setState(() => _hasScrolledToEnd = true);
      _startCooldown();
    }
  }

  void _startCooldown() {
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          timer.cancel();
        }
      });
    });
  }

  bool get _canAccept => _hasScrolledToEnd && _cooldownSeconds <= 0;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('VOICEVOX 利用規約'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '以下の利用規約をご確認ください',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _termsText == null
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: _termsContentCache ??=
                            _buildTermsContent(context),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            if (!_canAccept)
              Text(
                _hasScrolledToEnd
                    ? 'あと $_cooldownSeconds 秒...'
                    : '規約を最後までお読みください',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _canAccept ? () => Navigator.of(context).pop(true) : null,
          child: const Text('同意する'),
        ),
      ],
    );
  }

  Widget _buildTermsContent(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _termsText!.split('\n');
    final spans = <InlineSpan>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line == '## 禁止事項') {
        // Section header – bold + colored.
        spans.add(TextSpan(
          text: '\n禁止事項\n',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.error,
          ),
        ));
      } else if (line.contains('公序良俗に反する行為')) {
        spans.add(TextSpan(
          text: '$line\n',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.error,
          ),
        ));
      } else if (line.startsWith('# ')) {
        spans.add(TextSpan(
          text: '\n${line.substring(2)}\n',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (line.startsWith('## ')) {
        spans.add(TextSpan(
          text: '\n${line.substring(3)}\n',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ));
      } else if (line == '---') {
        spans.add(const TextSpan(text: '\n────────────────────\n'));
      } else {
        spans.add(TextSpan(text: '$line\n'));
      }
    }

    // Supplementary text at the end.
    spans.add(const TextSpan(text: '\n'));
    spans.add(TextSpan(
      text: '────────────────────\n\n',
      style: theme.textTheme.bodySmall,
    ));
    spans.add(TextSpan(
      text: '補足事項\n',
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    ));
    spans.add(TextSpan(
      text: '・読み上げ内容はユーザーの責任のもとでご利用ください。'
          'ライブ配信ではコメント投稿者が内容を制御するため、'
          '不適切な内容が読み上げられる可能性があります。\n'
          '・NGワードフィルター機能を活用することで、'
          '不適切な読み上げを防止できます。\n',
      style: theme.textTheme.bodyMedium,
    ));

    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodyMedium,
        children: spans,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
