import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/foreground_service/foreground_service_manager.dart';
import '../../domain/connection/connection_supervisor.dart';

/// Coordinates [ForegroundServiceManager] lifecycle with
/// [ConnectionSupervisor] state changes and program title updates.
///
/// This controller listens to connection status transitions and the program
/// title notifier, starting/stopping/updating the Android foreground service
/// notification accordingly.
class ForegroundServiceController {
  ForegroundServiceController({
    required ForegroundServiceManager foregroundServiceManager,
    required ConnectionSupervisor connectionSupervisor,
    required ValueNotifier<String?> programTitleNotifier,
  })  : _manager = foregroundServiceManager,
        _connectionSupervisor = connectionSupervisor,
        _programTitleNotifier = programTitleNotifier {
    _connectionSupervisor.addListener(_onConnectionStatusChanged);
    _programTitleNotifier.addListener(_onProgramTitleChanged);
  }

  final ForegroundServiceManager _manager;
  final ConnectionSupervisor _connectionSupervisor;
  final ValueNotifier<String?> _programTitleNotifier;
  ConnectionStatus? _lastStatus;

  void dispose() {
    _connectionSupervisor.removeListener(_onConnectionStatusChanged);
    _programTitleNotifier.removeListener(_onProgramTitleChanged);
    unawaited(_manager.stop());
  }

  void _onConnectionStatusChanged() {
    final ConnectionStatus current = _connectionSupervisor.status;
    if (current == _lastStatus) {
      return;
    }
    _lastStatus = current;

    switch (current) {
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        final String title = _programTitleNotifier.value ?? 'comerune';
        final String text = _notificationTextForStatus(current);
        if (!_manager.isRunning) {
          unawaited(_manager.start(title: title, text: text));
        } else {
          unawaited(_manager.updateNotification(title: title, text: text));
        }
        break;
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        if (_manager.isRunning) {
          unawaited(_manager.stop());
        }
        break;
    }
  }

  void _onProgramTitleChanged() {
    if (!_manager.isRunning) {
      return;
    }
    final String title = _programTitleNotifier.value ?? 'comerune';
    final ConnectionStatus current = _connectionSupervisor.status;
    unawaited(
      _manager.updateNotification(
        title: title,
        text: _notificationTextForStatus(current),
      ),
    );
  }

  String _notificationTextForStatus(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
        return '接続中...';
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
        return 'コメント受信中';
      case ConnectionStatus.reconnecting:
        return '再接続中...';
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        return '';
    }
  }
}
