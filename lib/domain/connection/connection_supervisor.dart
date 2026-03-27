import 'dart:developer';

import 'package:flutter/foundation.dart';

enum ConnectionStatus {
  idle,
  connectingSessionWs,
  resolvingEndpoints,
  streamingNdgr,
  streamingLegacy,
  reconnecting,
  stopped,
  ended,
  failed,
}

enum ConnectionErrorCode {
  lvParseFailed,
  sessionWsConnectFailed,
  endpointResolveFailed,
  ndgrStreamFailed,
  legacyWsFailed,
  speechBouyomiFailed,
  speechVoicevoxFailed,
  userStopped,
  broadcastEnded,
}

enum WifiIndicatorColor {
  green,
  red,
}

extension ConnectionStatusCode on ConnectionStatus {
  String get code {
    switch (this) {
      case ConnectionStatus.idle:
        return 'IDLE';
      case ConnectionStatus.connectingSessionWs:
        return 'CONNECTING_SESSION_WS';
      case ConnectionStatus.resolvingEndpoints:
        return 'RESOLVING_ENDPOINTS';
      case ConnectionStatus.streamingNdgr:
        return 'STREAMING_NDGR';
      case ConnectionStatus.streamingLegacy:
        return 'STREAMING_LEGACY';
      case ConnectionStatus.reconnecting:
        return 'RECONNECTING';
      case ConnectionStatus.stopped:
        return 'STOPPED';
      case ConnectionStatus.ended:
        return 'ENDED';
      case ConnectionStatus.failed:
        return 'FAILED';
    }
  }

  bool get usesGreenWifiIcon {
    switch (this) {
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        return true;
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        return false;
    }
  }
}

extension ConnectionErrorCodeExtension on ConnectionErrorCode {
  String get code {
    switch (this) {
      case ConnectionErrorCode.lvParseFailed:
        return 'LV_PARSE_FAILED';
      case ConnectionErrorCode.sessionWsConnectFailed:
        return 'SESSION_WS_CONNECT_FAILED';
      case ConnectionErrorCode.endpointResolveFailed:
        return 'ENDPOINT_RESOLVE_FAILED';
      case ConnectionErrorCode.ndgrStreamFailed:
        return 'NDGR_STREAM_FAILED';
      case ConnectionErrorCode.legacyWsFailed:
        return 'LEGACY_WS_FAILED';
      case ConnectionErrorCode.speechBouyomiFailed:
        return 'SPEECH_BOUYOMI_FAILED';
      case ConnectionErrorCode.speechVoicevoxFailed:
        return 'SPEECH_VOICEVOX_FAILED';
      case ConnectionErrorCode.userStopped:
        return 'USER_STOPPED';
      case ConnectionErrorCode.broadcastEnded:
        return 'BROADCAST_ENDED';
    }
  }
}

class ConnectionSupervisor extends ChangeNotifier {
  static const Map<ConnectionStatus, Set<ConnectionStatus>>
      _allowedTransitions = <ConnectionStatus, Set<ConnectionStatus>>{
    ConnectionStatus.idle: <ConnectionStatus>{
      ConnectionStatus.connectingSessionWs,
    },
    ConnectionStatus.connectingSessionWs: <ConnectionStatus>{
      ConnectionStatus.resolvingEndpoints,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.resolvingEndpoints: <ConnectionStatus>{
      ConnectionStatus.streamingNdgr,
      ConnectionStatus.streamingLegacy,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.streamingNdgr: <ConnectionStatus>{
      ConnectionStatus.reconnecting,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.streamingLegacy: <ConnectionStatus>{
      ConnectionStatus.reconnecting,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    // Integrated spec §6.2(5) explicitly allows reconnecting to return
    // directly to STREAMING_* when reusing the same endpoint.
    ConnectionStatus.reconnecting: <ConnectionStatus>{
      ConnectionStatus.connectingSessionWs,
      ConnectionStatus.streamingNdgr,
      ConnectionStatus.streamingLegacy,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.stopped: <ConnectionStatus>{
      ConnectionStatus.idle,
    },
    ConnectionStatus.ended: <ConnectionStatus>{
      ConnectionStatus.idle,
    },
    ConnectionStatus.failed: <ConnectionStatus>{
      ConnectionStatus.idle,
    },
  };

  ConnectionStatus _status = ConnectionStatus.idle;
  int _reconnectCount = 0;
  DateTime? _lastReceivedAt;
  ConnectionErrorCode? _lastError;

  ConnectionStatus get status => _status;
  int get reconnectCount => _reconnectCount;
  DateTime? get lastReceivedAt => _lastReceivedAt;
  ConnectionErrorCode? get lastError => _lastError;
  WifiIndicatorColor get wifiIndicatorColor => _status.usesGreenWifiIcon
      ? WifiIndicatorColor.green
      : WifiIndicatorColor.red;

  /// Whether the supervisor can start (or restart) a connection.
  ///
  /// True for all resting states: [ConnectionStatus.idle],
  /// [ConnectionStatus.stopped], [ConnectionStatus.ended], and
  /// [ConnectionStatus.failed].
  ///
  /// For non-idle resting states, [startConnection] performs an internal
  /// reset to [ConnectionStatus.idle] and then transitions to
  /// [ConnectionStatus.connectingSessionWs].
  bool get canStartConnection =>
      _status == ConnectionStatus.idle ||
      _status == ConnectionStatus.stopped ||
      _status == ConnectionStatus.ended ||
      _status == ConnectionStatus.failed;

  bool get canRetryFromTerminal =>
      _status == ConnectionStatus.ended || _status == ConnectionStatus.failed;

  bool startConnection() {
    if (!canStartConnection) {
      _logInvalidTransition(ConnectionStatus.connectingSessionWs);
      return false;
    }

    bool resetDuringPreStart = false;
    if (_status != ConnectionStatus.idle) {
      // Hide intermediate IDLE from observers to avoid UI flicker.
      final bool resetToIdle = _transitionTo(
        ConnectionStatus.idle,
        resetDiagnostics: true,
        notify: false,
      );
      if (!resetToIdle) {
        return false;
      }
      resetDuringPreStart = true;
    }

    return _transitionTo(
      ConnectionStatus.connectingSessionWs,
      resetDiagnostics: !resetDuringPreStart,
    );
  }

  /// Retries from a terminal state ([ConnectionStatus.ended] or
  /// [ConnectionStatus.failed]).
  ///
  /// This method validates terminal-state usage and then delegates to
  /// [startConnection].
  bool retryConnectionFromTerminal() {
    if (!canRetryFromTerminal) {
      _logInvalidTransition(ConnectionStatus.connectingSessionWs);
      return false;
    }
    return startConnection();
  }

  bool onSessionWsConnected() {
    return _transitionTo(ConnectionStatus.resolvingEndpoints);
  }

  bool onNdgrEndpointResolved() {
    return _transitionTo(ConnectionStatus.streamingNdgr);
  }

  bool onLegacyEndpointResolved() {
    return _transitionTo(ConnectionStatus.streamingLegacy);
  }

  bool onStreamDisconnected(ConnectionErrorCode errorCode) {
    return _transitionTo(
      ConnectionStatus.reconnecting,
      errorCode: errorCode,
      incrementReconnectCount: true,
    );
  }

  bool reconnectViaSessionWs() {
    return _transitionTo(ConnectionStatus.connectingSessionWs);
  }

  bool reconnectToNdgrStream() {
    return _transitionTo(ConnectionStatus.streamingNdgr);
  }

  bool reconnectToLegacyStream() {
    return _transitionTo(ConnectionStatus.streamingLegacy);
  }

  bool stopByUser() {
    return _transitionTo(
      ConnectionStatus.stopped,
      errorCode: ConnectionErrorCode.userStopped,
    );
  }

  bool endBroadcast() {
    return _transitionTo(
      ConnectionStatus.ended,
      errorCode: ConnectionErrorCode.broadcastEnded,
    );
  }

  bool fail(ConnectionErrorCode errorCode) {
    return _transitionTo(
      ConnectionStatus.failed,
      errorCode: errorCode,
    );
  }

  bool resetToIdle() {
    return _transitionTo(ConnectionStatus.idle);
  }

  void recordReceivedAt([DateTime? timestamp]) {
    _lastReceivedAt = timestamp ?? DateTime.now();
    notifyListeners();
  }

  void recordError(ConnectionErrorCode errorCode) {
    // Used for non-transition error updates (e.g. parse/speech failures).
    _lastError = errorCode;
    notifyListeners();
  }

  bool _transitionTo(
    ConnectionStatus next, {
    ConnectionErrorCode? errorCode,
    bool incrementReconnectCount = false,
    bool resetDiagnostics = false,
    bool notify = true,
  }) {
    final Set<ConnectionStatus> allowed =
        _allowedTransitions[_status] ?? const <ConnectionStatus>{};
    if (!allowed.contains(next)) {
      _logInvalidTransition(next);
      return false;
    }

    if (resetDiagnostics) {
      _reconnectCount = 0;
      _lastReceivedAt = null;
      _lastError = null;
    }

    if (incrementReconnectCount) {
      _reconnectCount += 1;
    }

    if (errorCode != null) {
      _lastError = errorCode;
    }

    _status = next;
    if (notify) {
      notifyListeners();
    }
    return true;
  }

  void _logInvalidTransition(ConnectionStatus next) {
    log(
      'Ignoring invalid transition: ${_status.code} -> ${next.code}',
      name: 'ConnectionSupervisor',
    );
  }
}
