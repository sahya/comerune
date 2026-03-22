import 'dart:async';
import 'dart:developer';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'connection_clients.dart';

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

extension ConnectionErrorCodeCode on ConnectionErrorCode {
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

typedef DelayExecutor = Future<void> Function(Duration delay);
typedef JitterProvider = Duration Function(int attempt);

class ConnectionSupervisor extends ChangeNotifier {
  ConnectionSupervisor({
    required SessionWsClient sessionWsClient,
    required NdgrClient ndgrClient,
    required LegacyCommentClient legacyCommentClient,
    int maxReconnectAttempts = 10,
    int legacySameUrlFailureThreshold = 3,
    DelayExecutor? delayExecutor,
    JitterProvider? jitterProvider,
  })  : _sessionWsClient = sessionWsClient,
        _ndgrClient = ndgrClient,
        _legacyCommentClient = legacyCommentClient,
        _maxReconnectAttempts = maxReconnectAttempts,
        _legacySameUrlFailureThreshold = legacySameUrlFailureThreshold,
        _delayExecutor = delayExecutor ?? _defaultDelayExecutor,
        _jitterProvider = jitterProvider ?? _defaultJitterProvider {
    _sessionEventSubscription = _sessionWsClient.events.listen(_onSessionWsEvent);
    _ndgrEventSubscription = _ndgrClient.events.listen(_onNdgrEvent);
    _legacyEventSubscription = _legacyCommentClient.events.listen(_onLegacyEvent);
  }

  static const List<int> _backoffSeconds = <int>[1, 2, 4, 8, 16, 30];

  static const Map<ConnectionStatus, Set<ConnectionStatus>> _allowedTransitions =
      <ConnectionStatus, Set<ConnectionStatus>>{
        ConnectionStatus.idle: <ConnectionStatus>{
          ConnectionStatus.connectingSessionWs,
        },
        ConnectionStatus.connectingSessionWs: <ConnectionStatus>{
          ConnectionStatus.resolvingEndpoints,
          ConnectionStatus.reconnecting,
          ConnectionStatus.stopped,
          ConnectionStatus.ended,
          ConnectionStatus.failed,
        },
        ConnectionStatus.resolvingEndpoints: <ConnectionStatus>{
          ConnectionStatus.streamingNdgr,
          ConnectionStatus.streamingLegacy,
          ConnectionStatus.reconnecting,
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

  static Future<void> _defaultDelayExecutor(Duration delay) {
    return Future<void>.delayed(delay);
  }

  static Duration _defaultJitterProvider(int _) {
    final Random random = Random();
    return Duration(milliseconds: random.nextInt(1000));
  }

  final SessionWsClient _sessionWsClient;
  final NdgrClient _ndgrClient;
  final LegacyCommentClient _legacyCommentClient;
  final int _maxReconnectAttempts;
  final int _legacySameUrlFailureThreshold;
  final DelayExecutor _delayExecutor;
  final JitterProvider _jitterProvider;
  late final StreamSubscription<SessionWsEvent> _sessionEventSubscription;
  late final StreamSubscription<NdgrEvent> _ndgrEventSubscription;
  late final StreamSubscription<LegacyCommentEvent> _legacyEventSubscription;

  ConnectionStatus _status = ConnectionStatus.idle;
  int _reconnectCount = 0;
  int _legacyConsecutiveFailures = 0;
  bool _isReconnectLoopRunning = false;
  DateTime? _lastReceivedAt;
  ConnectionErrorCode? _lastError;
  Uri? _currentNdgrViewApiUri;
  Uri? _currentLegacyWsUrl;

  ConnectionStatus get status => _status;
  int get reconnectCount => _reconnectCount;
  DateTime? get lastReceivedAt => _lastReceivedAt;
  ConnectionErrorCode? get lastError => _lastError;
  WifiIndicatorColor get wifiIndicatorColor =>
      _status.usesGreenWifiIcon ? WifiIndicatorColor.green : WifiIndicatorColor.red;

  bool get canStartConnection =>
      _status == ConnectionStatus.idle || _status == ConnectionStatus.stopped;

  bool get canRetryFromTerminal =>
      _status == ConnectionStatus.ended || _status == ConnectionStatus.failed;

  Duration backoffDelayForAttempt(int attempt) {
    if (attempt <= 0) {
      throw ArgumentError.value(attempt, 'attempt', 'must be greater than zero');
    }

    final int index = min(attempt - 1, _backoffSeconds.length - 1);
    final Duration base = Duration(seconds: _backoffSeconds[index]);
    final Duration jitter = _jitterProvider(attempt);
    return base + jitter;
  }

  Future<bool> startConnection() async {
    if (!canStartConnection) {
      _logInvalidTransition(ConnectionStatus.connectingSessionWs);
      return false;
    }

    if (_status == ConnectionStatus.stopped) {
      final bool resetToIdle = _transitionTo(ConnectionStatus.idle);
      if (!resetToIdle) {
        return false;
      }
    }

    final bool transitioned = _transitionTo(
      ConnectionStatus.connectingSessionWs,
      resetDiagnostics: true,
    );
    if (!transitioned) {
      return false;
    }

    try {
      await _resolveEndpointsAndConnect();
      return true;
    } on _ConnectionFailure catch (failure) {
      fail(failure.errorCode);
      return false;
    } catch (_) {
      fail(ConnectionErrorCode.sessionWsConnectFailed);
      return false;
    }
  }

  Future<bool> retryConnectionFromTerminal() async {
    if (!canRetryFromTerminal) {
      _logInvalidTransition(ConnectionStatus.connectingSessionWs);
      return false;
    }

    final bool resetToIdle = _transitionTo(ConnectionStatus.idle);
    if (!resetToIdle) {
      return false;
    }

    return startConnection();
  }

  Future<bool> onSessionWsDisconnected() {
    return _attemptReconnect(
      errorCode: ConnectionErrorCode.sessionWsConnectFailed,
      reconnectOperation: _reconnectViaSessionWs,
    );
  }

  Future<bool> onNdgrStreamStalled() {
    return _attemptReconnect(
      errorCode: ConnectionErrorCode.ndgrStreamFailed,
      reconnectOperation: _reconnectToNdgrStream,
    );
  }

  Future<bool> onLegacyWsDisconnected() {
    return _attemptReconnect(
      errorCode: ConnectionErrorCode.legacyWsFailed,
      reconnectOperation: _reconnectLegacyWithFallback,
    );
  }

  Future<bool> stopByUser() async {
    final bool transitioned = _transitionTo(
      ConnectionStatus.stopped,
      errorCode: ConnectionErrorCode.userStopped,
    );
    if (!transitioned) {
      return false;
    }

    await _disconnectAllClients();
    return true;
  }

  Future<bool> endBroadcast() async {
    final bool transitioned = _transitionTo(
      ConnectionStatus.ended,
      errorCode: ConnectionErrorCode.broadcastEnded,
    );
    if (!transitioned) {
      return false;
    }

    await _disconnectAllClients();
    return true;
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
    _lastError = errorCode;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sessionEventSubscription.cancel());
    unawaited(_ndgrEventSubscription.cancel());
    unawaited(_legacyEventSubscription.cancel());
    super.dispose();
  }

  void _onSessionWsEvent(SessionWsEvent event) {
    switch (event.type) {
      case SessionWsEventType.disconnected:
        if (_status == ConnectionStatus.idle ||
            _status == ConnectionStatus.stopped ||
            _status == ConnectionStatus.ended ||
            _status == ConnectionStatus.failed) {
          return;
        }
        unawaited(onSessionWsDisconnected());
        break;
      case SessionWsEventType.broadcastEnded:
        unawaited(endBroadcast());
        break;
    }
  }

  void _onNdgrEvent(NdgrEvent event) {
    if (_status != ConnectionStatus.streamingNdgr) {
      return;
    }
    switch (event.type) {
      case NdgrEventType.disconnected:
      case NdgrEventType.stalled:
        unawaited(onNdgrStreamStalled());
        break;
    }
  }

  void _onLegacyEvent(LegacyCommentEvent event) {
    if (_status != ConnectionStatus.streamingLegacy) {
      return;
    }
    switch (event.type) {
      case LegacyCommentEventType.disconnected:
        unawaited(onLegacyWsDisconnected());
        break;
    }
  }

  Future<void> _resolveEndpointsAndConnect() async {
    SessionEndpoints endpoints;
    try {
      endpoints = await _sessionWsClient.connectAndResolveEndpoints();
    } catch (_) {
      throw _ConnectionFailure(ConnectionErrorCode.sessionWsConnectFailed);
    }

    final bool toResolving = _transitionTo(ConnectionStatus.resolvingEndpoints);
    if (!toResolving) {
      throw _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    if (endpoints.ndgrViewApiUri != null) {
      _currentNdgrViewApiUri = endpoints.ndgrViewApiUri;
      _currentLegacyWsUrl = null;
      await _connectNdgr(endpoints.ndgrViewApiUri!);
      return;
    }

    if (endpoints.legacyWsUrl != null) {
      _currentLegacyWsUrl = endpoints.legacyWsUrl;
      _currentNdgrViewApiUri = null;
      await _connectLegacy(endpoints.legacyWsUrl!);
      return;
    }

    throw _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
  }

  Future<void> _connectNdgr(Uri viewApiUri) async {
    try {
      await _ndgrClient.connect(viewApiUri);
    } catch (_) {
      throw _ConnectionFailure(ConnectionErrorCode.ndgrStreamFailed);
    }

    final bool transitioned = _transitionTo(ConnectionStatus.streamingNdgr);
    if (!transitioned) {
      throw _ConnectionFailure(ConnectionErrorCode.ndgrStreamFailed);
    }
    _legacyConsecutiveFailures = 0;
  }

  Future<void> _connectLegacy(Uri wsUrl) async {
    try {
      await _legacyCommentClient.connect(wsUrl);
    } catch (_) {
      throw _ConnectionFailure(ConnectionErrorCode.legacyWsFailed);
    }

    final bool transitioned = _transitionTo(ConnectionStatus.streamingLegacy);
    if (!transitioned) {
      throw _ConnectionFailure(ConnectionErrorCode.legacyWsFailed);
    }
    _legacyConsecutiveFailures = 0;
  }

  Future<void> _reconnectViaSessionWs(int _) async {
    await _disconnectForSessionReconnect();

    final bool toConnecting = _transitionTo(ConnectionStatus.connectingSessionWs);
    if (!toConnecting) {
      throw _ConnectionFailure(ConnectionErrorCode.sessionWsConnectFailed);
    }
    await _resolveEndpointsAndConnect();
  }

  Future<void> _reconnectToNdgrStream(int _) async {
    await _safeDisconnect(
      _ndgrClient.disconnect,
      'ndgr stream',
    );

    final Uri? viewApiUri = _currentNdgrViewApiUri;
    if (viewApiUri == null) {
      throw _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }
    await _connectNdgr(viewApiUri);
  }

  Future<void> _reconnectLegacyWithFallback(int _) async {
    final Uri? legacyWsUrl = _currentLegacyWsUrl;
    if (legacyWsUrl == null) {
      throw _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    if (_legacyConsecutiveFailures >= _legacySameUrlFailureThreshold) {
      _legacyConsecutiveFailures = 0;
      await _reconnectViaSessionWs(0);
      return;
    }

    await _safeDisconnect(
      _legacyCommentClient.disconnect,
      'legacy stream',
    );

    try {
      await _connectLegacy(legacyWsUrl);
    } on _ConnectionFailure {
      _legacyConsecutiveFailures += 1;
      rethrow;
    }
  }

  Future<bool> _attemptReconnect({
    required ConnectionErrorCode errorCode,
    required Future<void> Function(int attempt) reconnectOperation,
  }) async {
    if (_shouldSuppressReconnect()) {
      return false;
    }

    if (_isReconnectLoopRunning) {
      return false;
    }

    final bool toReconnecting = _status == ConnectionStatus.reconnecting
        ? true
        : _transitionTo(
            ConnectionStatus.reconnecting,
            errorCode: errorCode,
          );
    if (!toReconnecting) {
      return false;
    }

    _isReconnectLoopRunning = true;

    try {
      while (!_shouldSuppressReconnect()) {
        if (_reconnectCount >= _maxReconnectAttempts) {
          fail(errorCode);
          return false;
        }

        _reconnectCount += 1;
        _lastError = errorCode;
        notifyListeners();

        await _delayExecutor(backoffDelayForAttempt(_reconnectCount));
        if (_shouldSuppressReconnect()) {
          return false;
        }

        try {
          await reconnectOperation(_reconnectCount);
          return true;
        } on _ConnectionFailure catch (failure) {
          _lastError = failure.errorCode;
          if (_status != ConnectionStatus.reconnecting) {
            _transitionTo(
              ConnectionStatus.reconnecting,
              errorCode: failure.errorCode,
            );
          }
          notifyListeners();
        } catch (_) {
          _lastError = errorCode;
          if (_status != ConnectionStatus.reconnecting) {
            _transitionTo(
              ConnectionStatus.reconnecting,
              errorCode: errorCode,
            );
          }
          notifyListeners();
        }
      }

      return false;
    } finally {
      _isReconnectLoopRunning = false;
    }
  }

  Future<void> _disconnectAllClients() async {
    await Future.wait<void>(<Future<void>>[
      _safeDisconnect(
        _sessionWsClient.disconnect,
        'session ws',
      ),
      _safeDisconnect(
        _ndgrClient.disconnect,
        'ndgr stream',
      ),
      _safeDisconnect(
        _legacyCommentClient.disconnect,
        'legacy stream',
      ),
    ]);
  }

  Future<void> _disconnectForSessionReconnect() async {
    await Future.wait<void>(<Future<void>>[
      _safeDisconnect(
        _sessionWsClient.disconnect,
        'session ws',
      ),
      _safeDisconnect(
        _ndgrClient.disconnect,
        'ndgr stream',
      ),
      _safeDisconnect(
        _legacyCommentClient.disconnect,
        'legacy stream',
      ),
    ]);
  }

  Future<void> _safeDisconnect(
    Future<void> Function() disconnect,
    String clientName,
  ) async {
    try {
      await disconnect();
    } catch (error, stackTrace) {
      log(
        'Failed to disconnect $clientName during reconnect: $error',
        name: 'ConnectionSupervisor',
        stackTrace: stackTrace,
      );
    }
  }

  bool _shouldSuppressReconnect() =>
      _status == ConnectionStatus.stopped || _status == ConnectionStatus.ended;

  bool _transitionTo(
    ConnectionStatus next, {
    ConnectionErrorCode? errorCode,
    bool resetDiagnostics = false,
  }) {
    final Set<ConnectionStatus> allowed =
        _allowedTransitions[_status] ?? const <ConnectionStatus>{};
    if (!allowed.contains(next)) {
      _logInvalidTransition(next);
      return false;
    }

    if (resetDiagnostics) {
      _reconnectCount = 0;
      _legacyConsecutiveFailures = 0;
      _lastReceivedAt = null;
      _lastError = null;
    }

    if (errorCode != null) {
      _lastError = errorCode;
    }

    _status = next;
    notifyListeners();
    return true;
  }

  void _logInvalidTransition(ConnectionStatus next) {
    log(
      'Ignoring invalid transition: ${_status.code} -> ${next.code}',
      name: 'ConnectionSupervisor',
    );
  }
}

class _ConnectionFailure implements Exception {
  const _ConnectionFailure(this.errorCode);

  final ConnectionErrorCode errorCode;
}
