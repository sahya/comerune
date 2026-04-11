import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/voicevox_model_info.dart';
import 'comment_speech_platform.dart';
import 'models/speech_event.dart';

/// Manages VOICEVOX voice models: listing, downloading, and deleting.
class VoicevoxModelManager {
  VoicevoxModelManager(this._platform);

  final CommentSpeechPlatform _platform;

  final ValueNotifier<List<VoicevoxModelInfo>> models = ValueNotifier([]);
  final ValueNotifier<Map<String, double>> downloadProgress = ValueNotifier({});

  StreamSubscription<SpeechEvent>? _eventSub;

  void startListening() {
    _eventSub = _platform.events.listen(_onEvent);
  }

  void _onEvent(SpeechEvent event) {
    switch (event.type) {
      case SpeechEventType.modelDownloadStarted:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _updateModelState(modelId, ModelDownloadState.downloading);
          // Only initialize progress if not already tracking this model.
          // The optimistic update in downloadModel() may have already set
          // progress, and a modelDownloadProgress event could arrive before
          // this event—resetting to 0.0 would discard real progress.
          if (!downloadProgress.value.containsKey(modelId)) {
            downloadProgress.value = {...downloadProgress.value, modelId: 0.0};
          }
        }
      case SpeechEventType.modelDownloadProgress:
        final modelId = event.payload['modelId'] as String?;
        final downloaded = event.payload['bytesDownloaded'] as int? ?? 0;
        final total = event.payload['totalBytes'] as int? ?? 1;
        if (modelId != null && total > 0) {
          downloadProgress.value = {
            ...downloadProgress.value,
            modelId: (downloaded / total).clamp(0.0, 1.0),
          };
        }
      case SpeechEventType.modelDownloadCompleted:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _updateModelState(modelId, ModelDownloadState.downloaded);
          _removeProgress(modelId);
        }
      case SpeechEventType.modelDownloadFailed:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _markDownloadFailed(modelId);
        }
      case SpeechEventType.modelDeleted:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _updateModelState(modelId, ModelDownloadState.notDownloaded);
        }
    }
  }

  void _updateModelState(String modelId, ModelDownloadState state) {
    final current = List<VoicevoxModelInfo>.from(models.value);
    final index = current.indexWhere((m) => m.modelId == modelId);
    if (index >= 0) {
      current[index] = current[index].copyWith(downloadState: state);
      models.value = current;
    }
  }

  void _removeProgress(String modelId) {
    final progress = Map<String, double>.from(downloadProgress.value);
    progress.remove(modelId);
    downloadProgress.value = progress;
  }

  void _markDownloadFailed(String modelId) {
    _updateModelState(modelId, ModelDownloadState.error);
    _removeProgress(modelId);
  }

  Future<void> refreshModels() async {
    final rawList = await _platform.getAvailableModels();
    models.value = rawList.map((m) => VoicevoxModelInfo.fromMap(m)).toList();
  }

  Future<void> downloadModel(String modelId) async {
    // Immediately reflect the downloading state so the UI shows
    // a progress bar right away, before the native side finishes
    // preparing the dictionary.
    _updateModelState(modelId, ModelDownloadState.downloading);
    downloadProgress.value = {...downloadProgress.value, modelId: 0.0};
    try {
      await _platform.downloadModel(modelId);
    } on Object {
      // Clean up optimistic state when the platform call itself fails.
      // Native-side failures also emit modelDownloadFailed, but this
      // ensures cleanup even if the event is delayed or lost.
      _markDownloadFailed(modelId);
      rethrow;
    }
  }

  Future<void> deleteModel(String modelId) async {
    await _platform.deleteModel(modelId);
  }

  Future<void> loadModel(String modelId) async {
    await _platform.loadModel(modelId);
  }

  Future<void> cancelDownload(String modelId) async {
    await _platform.cancelDownload(modelId);
  }

  void dispose() {
    _eventSub?.cancel();
    models.dispose();
    downloadProgress.dispose();
  }
}
