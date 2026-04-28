import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../data/foreground_service/foreground_service_manager.dart';
import '../../domain/connection/connection_supervisor.dart';

/// Coordinates [ForegroundServiceManager] lifecycle with
/// [ConnectionSupervisor] state changes and program title updates.
///
/// This controller listens to connection status transitions and the program
/// title notifier, starting/stopping/updating the Android foreground service
/// notification accordingly.
///
/// Issue #739 — broadcast-end grace:
/// On `ConnectionStatus.ended`, when [playRemainingAfterEnded] returns
/// `true`, the FGS is kept alive for up to [graceDuration] (default 30 s) so
/// the speech queue can drain. `failed` / `stopped` are unaffected and stop
/// the FGS immediately as before.
class ForegroundServiceController {
  ForegroundServiceController({
    required ForegroundServiceManager foregroundServiceManager,
    required ConnectionSupervisor connectionSupervisor,
    required ValueNotifier<String?> programTitleNotifier,
    bool Function()? playRemainingAfterEnded,
    @visibleForTesting Duration graceDuration = const Duration(seconds: 30),
  }) : _manager = foregroundServiceManager,
       _connectionSupervisor = connectionSupervisor,
       _programTitleNotifier = programTitleNotifier,
       // Default getter returns true so a caller that does not pass a hook
       // gets the issue-#739 spec'd default behaviour ("on, 30 s grace").
       _playRemainingAfterEnded = playRemainingAfterEnded ?? (() => true),
       _graceDuration = graceDuration {
    _connectionSupervisor.addListener(_onConnectionStatusChanged);
    _programTitleNotifier.addListener(_onProgramTitleChanged);
  }

  final ForegroundServiceManager _manager;
  final ConnectionSupervisor _connectionSupervisor;
  final ValueNotifier<String?> _programTitleNotifier;
  final bool Function() _playRemainingAfterEnded;
  final Duration _graceDuration;
  ConnectionStatus? _lastStatus;
  Timer? _graceTimer;
  bool _isInGrace = false;
  bool _disposed = false;

  /// Whether the controller is currently waiting out a broadcast-end grace
  /// period. Exposed for tests and UI callers that want to react to grace
  /// transitions (e.g. show a "読み上げ完了待ち..." indicator).
  bool get isInGrace => _isInGrace;

  /// Returns `true` while the FGS is waiting out the grace timer.
  ///
  /// Allows external collaborators (e.g. CommentScreen) to observe grace
  /// state via this single source of truth instead of duplicating timer
  /// bookkeeping.
  @visibleForTesting
  Timer? get graceTimerForTesting => _graceTimer;

  void dispose() {
    _disposed = true;
    _cancelGraceTimer();
    _connectionSupervisor.removeListener(_onConnectionStatusChanged);
    _programTitleNotifier.removeListener(_onProgramTitleChanged);
    unawaited(_manager.stop());
  }

  /// Notify the controller that the speech queue has drained naturally
  /// during a grace period. Stops the FGS immediately if grace is in
  /// progress; otherwise a no-op.
  ///
  /// The CommentScreen (which observes `queueUpdated` events from the
  /// native engine) calls this when the in-flight queue size hits zero so
  /// the FGS does not linger for the full 30 s when there is nothing left
  /// to read.
  void notifyQueueDrained() {
    if (!_isInGrace) {
      return;
    }
    developer.log(
      'Grace period ended early: queue drained',
      name: 'ForegroundServiceController',
    );
    _completeGrace(reason: 'queue_drained');
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
        // Any reconnect / reconnect-attempt status cancels grace and pushes
        // the live notification text again.
        _cancelGraceTimer();
        final String title = _programTitleNotifier.value ?? 'comerune';
        final String text = _notificationTextForStatus(current);
        if (!_manager.isRunning) {
          unawaited(_manager.start(title: title, text: text));
        } else {
          unawaited(_manager.updateNotification(title: title, text: text));
        }
        break;
      case ConnectionStatus.ended:
        _onEnded();
        break;
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.failed:
        // Manual stop / hard failure: never grace, always stop now.
        _cancelGraceTimer();
        if (_manager.isRunning) {
          unawaited(_manager.stop());
        }
        break;
    }
  }

  void _onEnded() {
    final bool graceEnabled = _safePlayRemainingAfterEnded();
    if (!graceEnabled || !_manager.isRunning) {
      // Either the user opted out, or the FGS is already stopped — preserve
      // the pre-#739 behaviour and stop immediately.
      _cancelGraceTimer();
      if (_manager.isRunning) {
        unawaited(_manager.stop());
      }
      return;
    }
    _isInGrace = true;
    // Refresh the notification so users see the transitional "完了待ち" state.
    final String title = _programTitleNotifier.value ?? 'comerune';
    unawaited(
      _manager.updateNotification(
        title: title,
        text: _notificationTextForStatus(ConnectionStatus.ended),
      ),
    );
    _graceTimer?.cancel();
    _graceTimer = Timer(_graceDuration, () {
      developer.log(
        'Grace period elapsed (${_graceDuration.inSeconds}s): forcing FGS stop',
        name: 'ForegroundServiceController',
      );
      _completeGrace(reason: 'timeout');
    });
  }

  void _completeGrace({required String reason}) {
    _graceTimer?.cancel();
    _graceTimer = null;
    _isInGrace = false;
    if (_disposed) {
      return;
    }
    // Only stop the FGS if we are still in `ended`. If the user reconnected
    // or stopped manually in the interim, those branches handle their own
    // bookkeeping.
    if (_lastStatus != ConnectionStatus.ended) {
      return;
    }
    if (_manager.isRunning) {
      unawaited(_manager.stop());
    }
    developer.log(
      'Grace period completed: $reason',
      name: 'ForegroundServiceController',
    );
  }

  void _cancelGraceTimer() {
    if (_graceTimer == null && !_isInGrace) {
      return;
    }
    _graceTimer?.cancel();
    _graceTimer = null;
    _isInGrace = false;
  }

  bool _safePlayRemainingAfterEnded() {
    try {
      return _playRemainingAfterEnded();
    } on Object catch (e, stackTrace) {
      developer.log(
        'playRemainingAfterEnded callback threw; falling back to true',
        name: 'ForegroundServiceController',
        error: e,
        stackTrace: stackTrace,
      );
      return true;
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
      case ConnectionStatus.ended:
        // Issue #739: while the grace timer is running the FGS notification
        // is still visible — surface a transitional label so users see why
        // speech keeps going briefly after the broadcast ends.
        if (_isInGrace) {
          return '読み上げ完了待ち...';
        }
        return '';
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.failed:
        return '';
    }
  }
}
