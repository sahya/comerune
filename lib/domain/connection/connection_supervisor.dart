import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

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
  sessionWsTimeout,
  endpointResolveFailed,
  ndgrStreamFailed,
  legacyWsFailed,
  speechBouyomiFailed,
  speechVoicevoxFailed,
  userStopped,
  broadcastEnded,
}

enum WifiIndicatorColor { green, red }

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
      case ConnectionErrorCode.sessionWsTimeout:
        return 'SESSION_WS_TIMEOUT';
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
    SessionWsClient? sessionWsClient,
    NdgrClient? ndgrClient,
    LegacyCommentClient? legacyCommentClient,
    int maxReconnectAttempts = 9,
    int legacySameUrlFailureThreshold = 3,
    DelayExecutor? delayExecutor,
    JitterProvider? jitterProvider,
  }) : assert(
         (sessionWsClient == null &&
                 ndgrClient == null &&
                 legacyCommentClient == null) ||
             (sessionWsClient != null &&
                 ndgrClient != null &&
                 legacyCommentClient != null),
         'Provide all reconnect clients together or none.',
       ),
       _sessionWsClient = sessionWsClient,
       _ndgrClient = ndgrClient,
       _legacyCommentClient = legacyCommentClient,
       _maxReconnectAttempts = maxReconnectAttempts,
       _legacySameUrlFailureThreshold = legacySameUrlFailureThreshold,
       _delayExecutor = delayExecutor ?? _defaultDelayExecutor,
       _jitterProvider = jitterProvider ?? _defaultJitterProvider {
    if (_hasReconnectClients) {
      _sessionEventSubscription = _sessionWsClient!.events.listen(
        _onSessionWsEvent,
      );
      _ndgrEventSubscription = _ndgrClient!.events.listen(_onNdgrEvent);
      _legacyEventSubscription = _legacyCommentClient!.events.listen(
        _onLegacyEvent,
      );
    }
  }

  static const List<int> _backoffSeconds = <int>[1, 2, 4, 6, 8, 10, 15, 20, 30];
  static final math.Random _random = math.Random();

  static const Map<ConnectionStatus, Set<ConnectionStatus>>
  _allowedTransitions = <ConnectionStatus, Set<ConnectionStatus>>{
    ConnectionStatus.idle: <ConnectionStatus>{
      ConnectionStatus.connectingSessionWs,
    },
    ConnectionStatus.connectingSessionWs: <ConnectionStatus>{
      ConnectionStatus.resolvingEndpoints,
      // Integrated spec §6.2 extension: when session WS drops during
      // connect phase, move to reconnecting and retry.
      ConnectionStatus.reconnecting,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.resolvingEndpoints: <ConnectionStatus>{
      ConnectionStatus.streamingNdgr,
      ConnectionStatus.streamingLegacy,
      // Integrated spec §6.2 extension: when session WS drops during
      // endpoint resolution, move to reconnecting and retry.
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
      // Integrated spec §6.2(5): reconnecting may return directly to
      // streaming states when reusing the same endpoint.
      ConnectionStatus.streamingNdgr,
      ConnectionStatus.streamingLegacy,
      ConnectionStatus.stopped,
      ConnectionStatus.ended,
      ConnectionStatus.failed,
    },
    ConnectionStatus.stopped: <ConnectionStatus>{ConnectionStatus.idle},
    ConnectionStatus.ended: <ConnectionStatus>{ConnectionStatus.idle},
    ConnectionStatus.failed: <ConnectionStatus>{ConnectionStatus.idle},
  };

  static Future<void> _defaultDelayExecutor(Duration delay) {
    return Future<void>.delayed(delay);
  }

  static Duration _defaultJitterProvider(int _) {
    return Duration(milliseconds: _random.nextInt(1000));
  }

  final SessionWsClient? _sessionWsClient;
  final NdgrClient? _ndgrClient;
  final LegacyCommentClient? _legacyCommentClient;
  final int _maxReconnectAttempts;
  final int _legacySameUrlFailureThreshold;
  final DelayExecutor _delayExecutor;
  final JitterProvider _jitterProvider;

  StreamSubscription<SessionWsEvent>? _sessionEventSubscription;
  StreamSubscription<NdgrEvent>? _ndgrEventSubscription;
  StreamSubscription<LegacyCommentEvent>? _legacyEventSubscription;

  ConnectionStatus _status = ConnectionStatus.idle;
  int _reconnectCount = 0;
  int _legacyConsecutiveFailures = 0;
  bool _isReconnectLoopRunning = false;
  DateTime? _lastReceivedAt;
  ConnectionErrorCode? _lastError;
  String? _lastErrorDetail;
  Uri? _currentNdgrViewApiUri;
  NdgrResumeCursor? _lastNdgrResumeCursor;
  Uri? _currentLegacyWsUrl;

  bool get _hasReconnectClients =>
      _sessionWsClient != null &&
      _ndgrClient != null &&
      _legacyCommentClient != null;

  ConnectionStatus get status => _status;
  int get reconnectCount => _reconnectCount;
  DateTime? get lastReceivedAt => _lastReceivedAt;
  ConnectionErrorCode? get lastError => _lastError;
  String? get lastErrorDetail => _lastErrorDetail;
  WifiIndicatorColor get wifiIndicatorColor => _status.usesGreenWifiIcon
      ? WifiIndicatorColor.green
      : WifiIndicatorColor.red;

  /// Whether the supervisor can start (or restart) a connection.
  ///
  /// True for resting states: [ConnectionStatus.idle],
  /// [ConnectionStatus.stopped], [ConnectionStatus.ended], and
  /// [ConnectionStatus.failed].
  ///
  /// For non-idle resting states, [startConnection] resets to
  /// [ConnectionStatus.idle] first and then transitions to
  /// [ConnectionStatus.connectingSessionWs].
  bool get canStartConnection =>
      _status == ConnectionStatus.idle ||
      _status == ConnectionStatus.stopped ||
      _status == ConnectionStatus.ended ||
      _status == ConnectionStatus.failed;

  bool get canRetryFromTerminal =>
      _status == ConnectionStatus.ended || _status == ConnectionStatus.failed;

  Duration backoffDelayForAttempt(int attempt) {
    if (attempt <= 0) {
      throw ArgumentError.value(
        attempt,
        'attempt',
        'must be greater than zero',
      );
    }

    final int index = math.min(attempt - 1, _backoffSeconds.length - 1);
    final Duration base = Duration(seconds: _backoffSeconds[index]);
    final Duration jitter = _jitterProvider(attempt);
    return base + jitter;
  }

  bool startConnection() {
    if (!canStartConnection) {
      _logInvalidTransition(ConnectionStatus.connectingSessionWs);
      return false;
    }

    bool resetDuringPreStart = false;
    if (_status != ConnectionStatus.idle) {
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

    final bool started = _transitionTo(
      ConnectionStatus.connectingSessionWs,
      resetDiagnostics: !resetDuringPreStart,
    );
    if (!started) {
      return false;
    }

    if (_hasReconnectClients) {
      unawaited(_resolveEndpointsAndConnectAfterStart());
    }

    return true;
  }

  /// Retries from a terminal state ([ConnectionStatus.ended] or
  /// [ConnectionStatus.failed]).
  ///
  /// This validates terminal-state usage and delegates to
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

  Future<bool> onSessionWsDisconnected() {
    if (!_hasReconnectClients) {
      return Future<bool>.value(
        onStreamDisconnected(ConnectionErrorCode.sessionWsConnectFailed),
      );
    }

    return _attemptReconnect(
      errorCode: ConnectionErrorCode.sessionWsConnectFailed,
      reconnectOperation: _reconnectViaSessionWsOperation,
    );
  }

  Future<bool> onNdgrStreamStalled({NdgrResumeCursor? resumeCursor}) {
    if (resumeCursor != null) {
      _lastNdgrResumeCursor = resumeCursor;
    }

    if (!_hasReconnectClients) {
      return Future<bool>.value(
        onStreamDisconnected(ConnectionErrorCode.ndgrStreamFailed),
      );
    }

    return _attemptReconnect(
      errorCode: ConnectionErrorCode.ndgrStreamFailed,
      reconnectOperation: _reconnectToNdgrStreamOperation,
    );
  }

  Future<bool> onLegacyWsDisconnected() {
    if (!_hasReconnectClients) {
      return Future<bool>.value(
        onStreamDisconnected(ConnectionErrorCode.legacyWsFailed),
      );
    }

    return _attemptReconnect(
      errorCode: ConnectionErrorCode.legacyWsFailed,
      reconnectOperation: _reconnectLegacyWithFallbackOperation,
    );
  }

  bool stopByUser() {
    final bool transitioned = _transitionTo(
      ConnectionStatus.stopped,
      errorCode: ConnectionErrorCode.userStopped,
    );
    if (!transitioned) {
      return false;
    }

    if (_hasReconnectClients) {
      unawaited(_disconnectAllClients());
    }
    return true;
  }

  bool endBroadcast({String? errorDetail}) {
    final bool transitioned = _transitionTo(
      ConnectionStatus.ended,
      errorCode: ConnectionErrorCode.broadcastEnded,
      errorDetail: errorDetail,
    );
    if (!transitioned) {
      return false;
    }

    if (_hasReconnectClients) {
      unawaited(_disconnectAllClients());
    }
    return true;
  }

  bool fail(ConnectionErrorCode errorCode, {String? errorDetail}) {
    return _transitionTo(
      ConnectionStatus.failed,
      errorCode: errorCode,
      errorDetail: errorDetail,
    );
  }

  bool resetToIdle() {
    return _transitionTo(ConnectionStatus.idle);
  }

  void recordReceivedAt([DateTime? timestamp]) {
    _lastReceivedAt = timestamp ?? DateTime.now();
    notifyListeners();
  }

  void recordError(ConnectionErrorCode errorCode, {String? errorDetail}) {
    _lastError = errorCode;
    _lastErrorDetail = errorDetail;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sessionEventSubscription?.cancel());
    unawaited(_ndgrEventSubscription?.cancel());
    unawaited(_legacyEventSubscription?.cancel());
    super.dispose();
  }

  Future<void> _resolveEndpointsAndConnectAfterStart() async {
    try {
      await _resolveEndpointsAndConnect();
    } on _ConnectionFailure catch (failure) {
      if (failure.errorCode == ConnectionErrorCode.broadcastEnded) {
        endBroadcast(errorDetail: failure.errorDetail);
        return;
      }
      fail(failure.errorCode, errorDetail: failure.errorDetail);
    } catch (_) {
      fail(ConnectionErrorCode.sessionWsConnectFailed);
    }
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
        endBroadcast();
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
        unawaited(onNdgrStreamStalled(resumeCursor: event.resumeCursor));
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
    if (!_hasReconnectClients) {
      throw const _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    final SessionWsClient sessionWsClient = _sessionWsClient!;
    SessionEndpoints endpoints;
    try {
      endpoints = await sessionWsClient.connectAndResolveEndpoints();
    } on SessionWsConnectException catch (error) {
      throw _ConnectionFailure(
        _mapSessionWsConnectFailure(error.kind),
        errorDetail: error.cause?.toString(),
      );
    } catch (_) {
      throw const _ConnectionFailure(
        ConnectionErrorCode.sessionWsConnectFailed,
      );
    }

    final bool toResolving = _transitionTo(ConnectionStatus.resolvingEndpoints);
    if (!toResolving) {
      throw const _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    if (endpoints.ndgrViewApiUri != null) {
      _currentNdgrViewApiUri = endpoints.ndgrViewApiUri;
      _lastNdgrResumeCursor = null;
      _currentLegacyWsUrl = null;
      await _connectNdgr(endpoints.ndgrViewApiUri!);
      return;
    }

    if (endpoints.legacyWsUrl != null) {
      _currentLegacyWsUrl = endpoints.legacyWsUrl;
      _currentNdgrViewApiUri = null;
      _lastNdgrResumeCursor = null;
      await _connectLegacy(endpoints.legacyWsUrl!);
      return;
    }

    throw const _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
  }

  ConnectionErrorCode _mapSessionWsConnectFailure(
    SessionWsConnectFailureKind kind,
  ) {
    switch (kind) {
      case SessionWsConnectFailureKind.connectFailed:
        return ConnectionErrorCode.sessionWsConnectFailed;
      case SessionWsConnectFailureKind.endpointResolveTimeout:
        return ConnectionErrorCode.sessionWsTimeout;
      case SessionWsConnectFailureKind.endpointParseFailed:
        return ConnectionErrorCode.endpointResolveFailed;
      case SessionWsConnectFailureKind.broadcastEnded:
        return ConnectionErrorCode.broadcastEnded;
    }
  }

  Future<void> _connectNdgr(
    Uri viewApiUri, {
    NdgrResumeCursor? resumeCursor,
  }) async {
    final NdgrClient ndgrClient = _ndgrClient!;

    try {
      await ndgrClient.connect(viewApiUri, resumeCursor: resumeCursor);
    } catch (_) {
      throw const _ConnectionFailure(ConnectionErrorCode.ndgrStreamFailed);
    }

    final bool transitioned = _transitionTo(ConnectionStatus.streamingNdgr);
    if (!transitioned) {
      throw const _ConnectionFailure(ConnectionErrorCode.ndgrStreamFailed);
    }
    _legacyConsecutiveFailures = 0;
  }

  Future<void> _connectLegacy(Uri wsUrl) async {
    final LegacyCommentClient legacyCommentClient = _legacyCommentClient!;

    try {
      await legacyCommentClient.connect(wsUrl);
    } catch (_) {
      throw const _ConnectionFailure(ConnectionErrorCode.legacyWsFailed);
    }

    final bool transitioned = _transitionTo(ConnectionStatus.streamingLegacy);
    if (!transitioned) {
      throw const _ConnectionFailure(ConnectionErrorCode.legacyWsFailed);
    }
    _legacyConsecutiveFailures = 0;
  }

  Future<void> _reconnectViaSessionWsOperation(int _) async {
    await _disconnectAllClients();

    final bool toConnecting = _transitionTo(
      ConnectionStatus.connectingSessionWs,
    );
    if (!toConnecting) {
      throw const _ConnectionFailure(
        ConnectionErrorCode.sessionWsConnectFailed,
      );
    }

    await _resolveEndpointsAndConnect();
  }

  Future<void> _reconnectToNdgrStreamOperation(int _) async {
    final NdgrClient ndgrClient = _ndgrClient!;

    await _safeDisconnect(ndgrClient.disconnect, 'ndgr stream');

    final Uri? viewApiUri = _currentNdgrViewApiUri;
    if (viewApiUri == null) {
      throw const _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    await _connectNdgr(viewApiUri, resumeCursor: _lastNdgrResumeCursor);
  }

  Future<void> _reconnectLegacyWithFallbackOperation(int _) async {
    final Uri? legacyWsUrl = _currentLegacyWsUrl;
    if (legacyWsUrl == null) {
      throw const _ConnectionFailure(ConnectionErrorCode.endpointResolveFailed);
    }

    if (_legacyConsecutiveFailures >= _legacySameUrlFailureThreshold) {
      _legacyConsecutiveFailures = 0;
      await _reconnectViaSessionWsOperation(0);
      return;
    }

    final LegacyCommentClient legacyCommentClient = _legacyCommentClient!;
    await _safeDisconnect(legacyCommentClient.disconnect, 'legacy stream');

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
            errorDetail: _lastErrorDetail,
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
        _lastErrorDetail = null;
        notifyListeners();

        await _delayExecutor(backoffDelayForAttempt(_reconnectCount));
        if (_shouldSuppressReconnect()) {
          return false;
        }

        try {
          await reconnectOperation(_reconnectCount);
          return true;
        } on _ConnectionFailure catch (failure) {
          if (failure.errorCode == ConnectionErrorCode.broadcastEnded) {
            endBroadcast(errorDetail: failure.errorDetail);
            return false;
          }
          _lastError = failure.errorCode;
          _lastErrorDetail = failure.errorDetail;
          if (_status != ConnectionStatus.reconnecting) {
            _transitionTo(
              ConnectionStatus.reconnecting,
              errorCode: failure.errorCode,
              errorDetail: failure.errorDetail,
            );
          }
          notifyListeners();
        } catch (_) {
          _lastError = errorCode;
          _lastErrorDetail = null;
          if (_status != ConnectionStatus.reconnecting) {
            _transitionTo(
              ConnectionStatus.reconnecting,
              errorCode: errorCode,
              errorDetail: null,
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
    if (!_hasReconnectClients) {
      return;
    }

    await Future.wait<void>(<Future<void>>[
      _safeDisconnect(_sessionWsClient!.disconnect, 'session ws'),
      _safeDisconnect(_ndgrClient!.disconnect, 'ndgr stream'),
      _safeDisconnect(_legacyCommentClient!.disconnect, 'legacy stream'),
    ]);
  }

  Future<void> _safeDisconnect(
    Future<void> Function() disconnect,
    String clientName,
  ) async {
    try {
      await disconnect();
    } catch (error, stackTrace) {
      developer.log(
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
    String? errorDetail,
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
      _legacyConsecutiveFailures = 0;
      _lastReceivedAt = null;
      _lastError = null;
      _lastErrorDetail = null;
      _lastNdgrResumeCursor = null;
      _currentNdgrViewApiUri = null;
      _currentLegacyWsUrl = null;
    }

    if (incrementReconnectCount) {
      _reconnectCount += 1;
    }

    if (errorCode != null) {
      _lastError = errorCode;
      _lastErrorDetail = errorDetail;
    }

    _status = next;
    if (notify) {
      notifyListeners();
    }
    return true;
  }

  void _logInvalidTransition(ConnectionStatus next) {
    developer.log(
      'Ignoring invalid transition: ${_status.code} -> ${next.code}',
      name: 'ConnectionSupervisor',
    );
  }
}

class _ConnectionFailure implements Exception {
  const _ConnectionFailure(this.errorCode, {this.errorDetail});

  final ConnectionErrorCode errorCode;
  final String? errorDetail;
}
