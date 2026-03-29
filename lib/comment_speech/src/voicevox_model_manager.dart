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
          downloadProgress.value = {...downloadProgress.value, modelId: 0.0};
        }
      case SpeechEventType.modelDownloadProgress:
        final modelId = event.payload['modelId'] as String?;
        final downloaded = event.payload['bytesDownloaded'] as int? ?? 0;
        final total = event.payload['totalBytes'] as int? ?? 1;
        if (modelId != null && total > 0) {
          downloadProgress.value = {
            ...downloadProgress.value,
            modelId: downloaded / total,
          };
        }
      case SpeechEventType.modelDownloadCompleted:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _updateModelState(modelId, ModelDownloadState.downloaded);
          final progress = Map<String, double>.from(downloadProgress.value);
          progress.remove(modelId);
          downloadProgress.value = progress;
        }
      case SpeechEventType.modelDownloadFailed:
        final modelId = event.payload['modelId'] as String?;
        if (modelId != null) {
          _updateModelState(modelId, ModelDownloadState.error);
          final progress = Map<String, double>.from(downloadProgress.value);
          progress.remove(modelId);
          downloadProgress.value = progress;
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

  Future<void> refreshModels() async {
    final rawList = await _platform.getAvailableModels();
    models.value = rawList.map((m) => VoicevoxModelInfo.fromMap(m)).toList();
  }

  Future<void> downloadModel(String modelId) async {
    await _platform.downloadModel(modelId);
  }

  Future<void> deleteModel(String modelId) async {
    await _platform.deleteModel(modelId);
  }

  Future<void> loadModel(String modelId) async {
    await _platform.loadModel(modelId);
  }

  void dispose() {
    _eventSub?.cancel();
    models.dispose();
    downloadProgress.dispose();
  }
}
