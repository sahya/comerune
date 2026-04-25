import 'dart:async';

import 'package:flutter/material.dart';

import 'comment_speech_platform.dart';
import 'models/speech_event.dart';

/// Download state for VOICEVOX model setup.
enum VoicevoxSetupState {
  /// Not started yet.
  idle,

  /// Downloading assets (OpenJTalk dict + VVM model).
  downloading,

  /// Initializing the native engine after download.
  initializing,

  /// Ready to use.
  ready,

  /// An error occurred during download or initialization.
  error,
}

/// Manages the first-time VOICEVOX asset download and engine initialization.
///
/// Listens to [CommentSpeechPlatform.events] for download progress and
/// exposes state via [ValueNotifier]s for the UI to observe.
class VoicevoxSetupHelper {
  VoicevoxSetupHelper(this._platform);

  final CommentSpeechPlatform _platform;

  final ValueNotifier<VoicevoxSetupState> state = ValueNotifier(
    VoicevoxSetupState.idle,
  );
  final ValueNotifier<String> statusMessage = ValueNotifier('');
  final ValueNotifier<double> progress = ValueNotifier(0.0);
  final ValueNotifier<String?> errorMessage = ValueNotifier(null);

  StreamSubscription<SpeechEvent>? _eventSub;

  /// Tracks whether [dispose] has been called. Guards every [ValueNotifier]
  /// write so that late-arriving async completions (e.g. [_platform.initialize]
  /// resolving after the owning widget is disposed) do not throw
  /// "A ValueNotifier was used after being disposed."
  bool _disposed = false;

  /// Whether this helper has been disposed. Exposed for tests and defensive
  /// callers; the helper itself also guards internally.
  bool get isDisposed => _disposed;

  /// Start the setup process: subscribe to events, then call initialize.
  Future<void> start() async {
    if (_disposed) return;
    _setState(VoicevoxSetupState.downloading);
    _setStatusMessage('VOICEVOXモデルを準備しています...');
    _setProgress(0.0);
    _setErrorMessage(null);

    _eventSub = _platform.events.listen(_onEvent);

    try {
      await _platform.initialize();
      _setState(VoicevoxSetupState.ready);
      _setStatusMessage('準備完了');
      _setProgress(1.0);
    } catch (e) {
      _setState(VoicevoxSetupState.error);
      _setErrorMessage(e.toString());
      _setStatusMessage('セットアップに失敗しました');
    }
  }

  void _onEvent(SpeechEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case SpeechEventType.downloadStarted:
        _setState(VoicevoxSetupState.downloading);
        final fileName = event.payload['fileName'] as String? ?? '';
        _setStatusMessage('$fileNameをダウンロード中...');
        _setProgress(0.0);
      case SpeechEventType.downloadProgress:
        final downloaded = event.payload['bytesDownloaded'] as int? ?? 0;
        final total = event.payload['totalBytes'] as int? ?? 1;
        if (total > 0) {
          _setProgress(downloaded / total);
        }
        final mb = (downloaded / 1024 / 1024).toStringAsFixed(1);
        _setStatusMessage('ダウンロード中... ${mb}MB');
      case SpeechEventType.downloadCompleted:
        _setState(VoicevoxSetupState.initializing);
        _setStatusMessage('エンジンを初期化中...');
        _setProgress(1.0);
      case SpeechEventType.engineStateChanged:
        final engineState = event.payload['state'] as String? ?? '';
        if (engineState == 'READY') {
          _setState(VoicevoxSetupState.ready);
          _setStatusMessage('準備完了');
        } else if (engineState == 'ERROR') {
          _setState(VoicevoxSetupState.error);
          _setStatusMessage('エンジン初期化に失敗しました');
        }
    }
  }

  void _setState(VoicevoxSetupState value) {
    if (_disposed) return;
    state.value = value;
  }

  void _setStatusMessage(String value) {
    if (_disposed) return;
    statusMessage.value = value;
  }

  void _setProgress(double value) {
    if (_disposed) return;
    progress.value = value;
  }

  void _setErrorMessage(String? value) {
    if (_disposed) return;
    errorMessage.value = value;
  }

  void dispose() {
    if (_disposed) return;
    // Flip the guard first so any in-flight async continuations bail out
    // before touching the notifiers we are about to dispose below.
    _disposed = true;
    _eventSub?.cancel();
    _eventSub = null;
    state.dispose();
    statusMessage.dispose();
    progress.dispose();
    errorMessage.dispose();
  }
}

/// A widget that shows VOICEVOX download/setup progress.
///
/// Usage:
/// ```dart
/// VoicevoxSetupDialog.show(context, platform);
/// ```
class VoicevoxSetupDialog extends StatefulWidget {
  const VoicevoxSetupDialog({
    super.key,
    required this.platform,
    this.onComplete,
  });

  final CommentSpeechPlatform platform;
  final VoidCallback? onComplete;

  /// Show the setup dialog. Returns when setup is complete or cancelled.
  static Future<bool> show(
    BuildContext context,
    CommentSpeechPlatform platform,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VoicevoxSetupDialog(platform: platform),
    );
    return result ?? false;
  }

  @override
  State<VoicevoxSetupDialog> createState() => _VoicevoxSetupDialogState();
}

class _VoicevoxSetupDialogState extends State<VoicevoxSetupDialog> {
  late final VoicevoxSetupHelper _helper;

  @override
  void initState() {
    super.initState();
    _helper = VoicevoxSetupHelper(widget.platform);
    _helper.state.addListener(_onStateChanged);
    _helper.start();
  }

  @override
  void dispose() {
    _helper.state.removeListener(_onStateChanged);
    _helper.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    setState(() {});
    if (_helper.state.value == VoicevoxSetupState.ready) {
      widget.onComplete?.call();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('VOICEVOX セットアップ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_helper.state.value == VoicevoxSetupState.error) ...[
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              _helper.statusMessage.value,
              style: const TextStyle(color: Colors.red),
            ),
            if (_helper.errorMessage.value != null) ...[
              const SizedBox(height: 8),
              Text(
                _helper.errorMessage.value!,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else ...[
            if (_helper.state.value == VoicevoxSetupState.downloading)
              const Icon(Icons.download, color: Colors.blue, size: 48)
            else if (_helper.state.value == VoicevoxSetupState.initializing)
              const Icon(Icons.settings, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(_helper.statusMessage.value),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _helper.state.value == VoicevoxSetupState.initializing
                  ? null // indeterminate
                  : _helper.progress.value,
            ),
            const SizedBox(height: 8),
            Text(_progressText(), style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        if (_helper.state.value == VoicevoxSetupState.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('閉じる'),
          ),
          TextButton(
            onPressed: () {
              _helper.start();
            },
            child: const Text('再試行'),
          ),
        ],
      ],
    );
  }

  String _progressText() {
    final p = _helper.progress.value;
    if (_helper.state.value == VoicevoxSetupState.initializing) {
      return 'エンジンを起動しています...';
    }
    if (p <= 0) return '接続中...';
    return '${(p * 100).toStringAsFixed(0)}%';
  }
}
