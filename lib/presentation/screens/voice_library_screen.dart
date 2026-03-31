import 'package:flutter/material.dart';

import '../../comment_speech/comment_speech.dart';
import '../../domain/models/voicevox_model_info.dart';

class VoiceLibraryScreen extends StatefulWidget {
  const VoiceLibraryScreen({super.key, required this.platform});

  final CommentSpeechPlatform platform;

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
    try {
      await _manager.downloadModel(model.modelId);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ダウンロードに失敗しました: $e')),
      );
      return;
    }
    // ダウンロード成功後、モデルのロードを試みる（失敗しても問題ない）
    try {
      await _manager.loadModel(model.modelId);
    } on Object catch (e) {
      // エンジン未初期化等でロード失敗しても、ダウンロードは成功しているので問題ない
      // 次回エンジン初期化時に自動ロードされる
      debugPrint('[VoiceLibrary] loadModel after download skipped: $e');
    }
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
