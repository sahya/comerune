import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/settings/settings_store.dart';
import 'application/settings/shared_preferences_adapter.dart';
import 'application/timeline/timeline_store.dart';
import 'data/auth/access_token_store.dart';
import 'data/connection/web_socket_channel_legacy_web_socket.dart';
import 'data/connection/ws_endpoint_resolver.dart';
import 'domain/connection/connection_clients.dart' as reconnect;
import 'domain/connection/connection_supervisor.dart';
import 'domain/connection/legacy_comment_client.dart' as legacy_impl;
import 'domain/connection/ndgr_client.dart' as ndgr_impl;
import 'domain/connection/session_ws_client.dart' as session_impl;
import 'domain/models/app_message.dart';
import 'domain/models/app_settings.dart';
import 'presentation/select/select_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsStore settingsStore = SharedPreferencesSettingsStore(
    prefs: SharedPreferencesAdapter(prefs),
  );
  final AppSettings initialSettings = await settingsStore.load();
  final AccessTokenStore accessTokenStore =
      SharedPreferencesAccessTokenStore(prefs);

  runApp(
    ComeruneApp(
      settingsStore: settingsStore,
      initialSettings: initialSettings,
      accessTokenStore: accessTokenStore,
    ),
  );
}

class ComeruneApp extends StatefulWidget {
  const ComeruneApp({
    super.key,
    required this.settingsStore,
    required this.initialSettings,
    required this.accessTokenStore,
  });

  final SettingsStore settingsStore;
  final AppSettings initialSettings;
  final AccessTokenStore accessTokenStore;

  @override
  State<ComeruneApp> createState() => _ComeruneAppState();
}

class _ComeruneAppState extends State<ComeruneApp> {
  late final TimelineStore _timelineStore;
  late final _SessionWsClientAdapter _sessionWsClient;
  late final _NdgrClientAdapter _ndgrClient;
  late final _LegacyCommentClientAdapter _legacyCommentClient;
  late final ConnectionSupervisor _connectionSupervisor;
  late final StreamSubscription<AppMessage> _ndgrMessageSubscription;
  late final StreamSubscription<AppMessage> _legacyMessageSubscription;

  String _currentLv = '';
  String _currentAccessToken = '';
  int _ndgrHistoryCount = 100;

  @override
  void initState() {
    super.initState();
    _ndgrHistoryCount = _historyCountFrom(
      widget.initialSettings.pastCommentFetchCount,
    );

    _timelineStore = TimelineStore(capacity: _ndgrHistoryCount);
    _sessionWsClient = _SessionWsClientAdapter(
      lvProvider: () => _currentLv,
      accessTokenProvider: () => _currentAccessToken,
      wsEndpointResolver: WsEndpointResolver(),
    );
    _ndgrClient = _NdgrClientAdapter(
      client: ndgr_impl.NdgrClient(),
      historyCountProvider: () => _ndgrHistoryCount,
    );
    _legacyCommentClient = _LegacyCommentClientAdapter(
      client: legacy_impl.LegacyCommentClient(
        webSocketConnector: WebSocketChannelLegacyWebSocket.connect,
      ),
    );

    _connectionSupervisor = ConnectionSupervisor(
      sessionWsClient: _sessionWsClient,
      ndgrClient: _ndgrClient,
      legacyCommentClient: _legacyCommentClient,
    );

    _ndgrMessageSubscription = _ndgrClient.messages.listen(_timelineStore.add);
    _legacyMessageSubscription = _legacyCommentClient.messages.listen(
      _timelineStore.add,
    );
  }

  @override
  void dispose() {
    unawaited(_ndgrMessageSubscription.cancel());
    unawaited(_legacyMessageSubscription.cancel());
    _connectionSupervisor.dispose();
    unawaited(_sessionWsClient.dispose());
    unawaited(_ndgrClient.dispose());
    unawaited(_legacyCommentClient.dispose());
    _timelineStore.dispose();
    super.dispose();
  }

  Future<void> _prepareConnection(String lv, AppSettings settings) async {
    _currentLv = lv;
    _currentAccessToken = await widget.accessTokenStore.load();
    _ndgrHistoryCount = _historyCountFrom(settings.pastCommentFetchCount);
    _timelineStore.setCapacity(_ndgrHistoryCount);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'comerune',
      home: SelectScreen(
        connectionSupervisor: _connectionSupervisor,
        timelineStore: _timelineStore,
        settingsStore: widget.settingsStore,
        initialSettings: widget.initialSettings,
        onPrepareConnection: _prepareConnection,
        accessTokenStore: widget.accessTokenStore,
      ),
    );
  }
}

int _historyCountFrom(PastCommentFetchCount value) {
  switch (value) {
    case PastCommentFetchCount.count100:
      return 100;
    case PastCommentFetchCount.count500:
      return 500;
    case PastCommentFetchCount.count1000:
      return 1000;
    case PastCommentFetchCount.all:
      return 10000;
  }
}

class _SessionWsClientAdapter implements reconnect.SessionWsClient {
  _SessionWsClientAdapter({
    required String Function() lvProvider,
    required String Function() accessTokenProvider,
    required WsEndpointResolver wsEndpointResolver,
  })  : _lvProvider = lvProvider,
        _accessTokenProvider = accessTokenProvider,
        _wsEndpointResolver = wsEndpointResolver;

  final String Function() _lvProvider;
  final String Function() _accessTokenProvider;
  final WsEndpointResolver _wsEndpointResolver;
  final StreamController<reconnect.SessionWsEvent> _eventsController =
      StreamController<reconnect.SessionWsEvent>.broadcast();

  session_impl.SessionWsClient? _activeClient;
  StreamSubscription<session_impl.SessionWsEvent>? _activeSubscription;
  Completer<reconnect.SessionEndpoints>? _pendingEndpointsCompleter;
  reconnect.SessionWsConnectException? _lastSessionFailure;

  @override
  Stream<reconnect.SessionWsEvent> get events => _eventsController.stream;

  @override
  Future<reconnect.SessionEndpoints> connectAndResolveEndpoints() async {
    await disconnect();

    final String lv = _lvProvider();
    if (lv.isEmpty) {
      throw StateError('lv is empty');
    }

    Uri? wsEndpointUri;
    final String accessToken = _accessTokenProvider();
    if (accessToken.isNotEmpty) {
      try {
        wsEndpointUri = await _wsEndpointResolver.resolve(
          lv: lv,
          accessToken: accessToken,
        );
      } on WsEndpointResolveException catch (error) {
        log(
          'WS endpoint resolution failed, falling back to direct URL: $error',
          name: 'SessionWsClientAdapter',
        );
      } on Object catch (error) {
        log(
          'Unexpected error during WS endpoint resolution, '
          'falling back to direct URL: $error',
          name: 'SessionWsClientAdapter',
        );
      }
    }

    final session_impl.SessionWsClient client = session_impl.SessionWsClient(
      lv: lv,
      wsEndpointUri: wsEndpointUri,
    );
    final Completer<reconnect.SessionEndpoints> completer =
        Completer<reconnect.SessionEndpoints>();

    _activeClient = client;
    _pendingEndpointsCompleter = completer;
    _lastSessionFailure = null;
    _activeSubscription = client.events.listen(
      (session_impl.SessionWsEvent event) {
        _handleClientEvent(event, completer);
      },
      onError: (Object error, StackTrace stackTrace) {
        final reconnect.SessionWsConnectException failure =
            reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.connectFailed,
          cause: error,
        );
        _recordSessionFailure(failure);
        _completeEndpointError(
          completer,
          failure,
          stackTrace: stackTrace,
        );
      },
    );

    await client.connect();
    return completer.future;
  }

  @override
  Future<void> disconnect() async {
    final StreamSubscription<session_impl.SessionWsEvent>? subscription =
        _activeSubscription;
    _activeSubscription = null;
    await subscription?.cancel();

    final Completer<reconnect.SessionEndpoints>? completer =
        _pendingEndpointsCompleter;
    _pendingEndpointsCompleter = null;
    final reconnect.SessionWsConnectException? lastFailure =
        _lastSessionFailure;
    _lastSessionFailure = null;
    if (completer != null && !completer.isCompleted) {
      _completeEndpointError(
        completer,
        lastFailure ??
            const reconnect.SessionWsConnectException(
              reconnect.SessionWsConnectFailureKind.connectFailed,
              cause: 'Session WS disconnected before endpoint resolution',
            ),
      );
    }

    final session_impl.SessionWsClient? client = _activeClient;
    _activeClient = null;
    if (client != null) {
      await client.dispose();
    }
  }

  Future<void> dispose() async {
    await disconnect();
    _wsEndpointResolver.dispose();
    await _eventsController.close();
  }

  void _handleClientEvent(
    session_impl.SessionWsEvent event,
    Completer<reconnect.SessionEndpoints> completer,
  ) {
    switch (event.type) {
      case session_impl.SessionWsEventType.connected:
      case session_impl.SessionWsEventType.debugLog:
        break;
      case session_impl.SessionWsEventType.ndgrEndpointResolved:
        final Uri? uri = Uri.tryParse(event.ndgrViewUri ?? '');
        if (uri == null) {
          final reconnect.SessionWsConnectException failure =
              reconnect.SessionWsConnectException(
            reconnect.SessionWsConnectFailureKind.endpointParseFailed,
            cause:
                'Invalid NDGR endpoint URI: ${event.ndgrViewUri ?? '(empty)'}',
          );
          _recordSessionFailure(failure);
          _completeEndpointError(
            completer,
            failure,
          );
          break;
        }
        if (!completer.isCompleted) {
          completer.complete(reconnect.SessionEndpoints(ndgrViewApiUri: uri));
        }
        break;
      case session_impl.SessionWsEventType.legacyEndpointResolved:
        final Uri? uri = Uri.tryParse(event.legacyWebSocketUrl ?? '');
        if (uri == null) {
          final reconnect.SessionWsConnectException failure =
              reconnect.SessionWsConnectException(
            reconnect.SessionWsConnectFailureKind.endpointParseFailed,
            cause:
                'Invalid legacy endpoint URI: ${event.legacyWebSocketUrl ?? '(empty)'}',
          );
          _recordSessionFailure(failure);
          _completeEndpointError(
            completer,
            failure,
          );
          break;
        }
        if (!completer.isCompleted) {
          completer.complete(reconnect.SessionEndpoints(legacyWsUrl: uri));
        }
        break;
      case session_impl.SessionWsEventType.disconnected:
        final reconnect.SessionWsConnectException failure = _failureFromEvent(
          event,
          fallbackKind: reconnect.SessionWsConnectFailureKind.connectFailed,
        );
        _recordSessionFailure(failure);
        _completeEndpointError(
          completer,
          failure,
        );
        _emitSessionEvent(
          const reconnect.SessionWsEvent(
            reconnect.SessionWsEventType.disconnected,
          ),
        );
        break;
      case session_impl.SessionWsEventType.broadcastEnded:
        final reconnect.SessionWsConnectException failure = _failureFromEvent(
          event,
          fallbackKind: reconnect.SessionWsConnectFailureKind.broadcastEnded,
        );
        _recordSessionFailure(failure);
        _completeEndpointError(
          completer,
          failure,
        );
        _emitSessionEvent(
          const reconnect.SessionWsEvent(
            reconnect.SessionWsEventType.broadcastEnded,
          ),
        );
        break;
      case session_impl.SessionWsEventType.failed:
      case session_impl.SessionWsEventType.error:
        final reconnect.SessionWsConnectException failure = _failureFromEvent(
          event,
          fallbackKind: reconnect.SessionWsConnectFailureKind.connectFailed,
        );
        _recordSessionFailure(failure);
        if (completer.isCompleted) {
          _emitSessionEvent(
            const reconnect.SessionWsEvent(
              reconnect.SessionWsEventType.disconnected,
            ),
          );
        } else {
          _completeEndpointError(completer, failure,
              stackTrace: event.stackTrace);
        }
        break;
    }
  }

  void _completeEndpointError(
    Completer<reconnect.SessionEndpoints> completer,
    Object error, {
    StackTrace? stackTrace,
  }) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  void _emitSessionEvent(reconnect.SessionWsEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  void _recordSessionFailure(reconnect.SessionWsConnectException failure) {
    _lastSessionFailure = failure;
  }

  reconnect.SessionWsConnectException _failureFromEvent(
    session_impl.SessionWsEvent event, {
    required reconnect.SessionWsConnectFailureKind fallbackKind,
  }) {
    return _mapSessionErrorCodeToConnectException(
      event.errorCode,
      fallbackKind: fallbackKind,
      cause: _eventCause(event),
    );
  }

  Object? _eventCause(session_impl.SessionWsEvent event) {
    final session_impl.SessionWsErrorDetail? errorDetail = event.errorDetail;
    if (errorDetail != null) {
      return errorDetail.cause ?? errorDetail.toString();
    }

    return event.error ?? event.debugMessage;
  }

  reconnect.SessionWsConnectException _mapSessionErrorCodeToConnectException(
    session_impl.SessionWsErrorCode? errorCode, {
    required reconnect.SessionWsConnectFailureKind fallbackKind,
    Object? cause,
  }) {
    switch (errorCode) {
      case session_impl.SessionWsErrorCode.endpointResolveFailed:
        return reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.endpointResolveTimeout,
          cause: cause ??
              _defaultCauseForKind(
                reconnect.SessionWsConnectFailureKind.endpointResolveTimeout,
              ),
        );
      case session_impl.SessionWsErrorCode.connectFailed:
      case session_impl.SessionWsErrorCode.keepaliveResponseFailed:
        return reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.connectFailed,
          cause: cause ??
              _defaultCauseForKind(
                reconnect.SessionWsConnectFailureKind.connectFailed,
              ),
        );
      case session_impl.SessionWsErrorCode.unknownBroadcastEndEvent:
        return reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.broadcastEnded,
          cause: cause ??
              _defaultCauseForKind(
                reconnect.SessionWsConnectFailureKind.broadcastEnded,
              ),
        );
      case null:
        return reconnect.SessionWsConnectException(
          fallbackKind,
          cause: cause ?? _defaultCauseForKind(fallbackKind),
        );
    }
  }

  String _defaultCauseForKind(reconnect.SessionWsConnectFailureKind kind) {
    switch (kind) {
      case reconnect.SessionWsConnectFailureKind.connectFailed:
        return 'Session WS connection failed';
      case reconnect.SessionWsConnectFailureKind.endpointResolveTimeout:
        return 'Session endpoint resolution timed out';
      case reconnect.SessionWsConnectFailureKind.endpointParseFailed:
        return 'Session endpoint format was invalid';
      case reconnect.SessionWsConnectFailureKind.broadcastEnded:
        return 'Broadcast ended while resolving endpoints';
    }
  }
}

class _NdgrClientAdapter implements reconnect.NdgrClient {
  _NdgrClientAdapter({
    required ndgr_impl.NdgrClient client,
    required int Function() historyCountProvider,
  })  : _client = client,
        _historyCountProvider = historyCountProvider {
    _clientEventsSubscription = _client.events.listen(
      _handleClientEvent,
      onError: (_, __) {
        _emitDisconnected();
      },
    );
  }

  final ndgr_impl.NdgrClient _client;
  final int Function() _historyCountProvider;
  final StreamController<reconnect.NdgrEvent> _eventsController =
      StreamController<reconnect.NdgrEvent>.broadcast();
  final StreamController<AppMessage> _messagesController =
      StreamController<AppMessage>.broadcast();
  late final StreamSubscription<ndgr_impl.NdgrClientEvent>
      _clientEventsSubscription;

  Future<void>? _activeConnectFuture;
  Completer<void>? _pendingStartupCompleter;
  bool _disconnectRequested = false;

  Stream<AppMessage> get messages => _messagesController.stream;

  @override
  Stream<reconnect.NdgrEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(
    Uri viewApiUri, {
    reconnect.NdgrResumeCursor? resumeCursor,
  }) async {
    await disconnect();

    final ndgr_impl.NdgrAt at = _resumeCursorToAt(resumeCursor);
    final int historyCount = _historyCountProvider();
    final Completer<void> startupCompleter = Completer<void>();

    _disconnectRequested = false;
    _pendingStartupCompleter = startupCompleter;
    _activeConnectFuture = _runConnect(
      viewApiUri,
      historyCount: historyCount,
      at: at,
    );
    unawaited(_activeConnectFuture);
    await startupCompleter.future;
  }

  @override
  Future<void> disconnect() async {
    _disconnectRequested = true;
    _completeStartupErrorIfPending(
      StateError('NDGR disconnected before streaming started'),
    );
    await _client.stop();

    final Future<void>? activeConnectFuture = _activeConnectFuture;
    if (activeConnectFuture != null) {
      await activeConnectFuture;
    }
    _activeConnectFuture = null;
    _disconnectRequested = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _clientEventsSubscription.cancel();
    _client.dispose();
    await _eventsController.close();
    await _messagesController.close();
  }

  Future<void> _runConnect(
    Uri viewApiUri, {
    required int historyCount,
    required ndgr_impl.NdgrAt at,
  }) async {
    try {
      await _client.connect(viewApiUri, historyCount: historyCount, at: at);
    } catch (_) {
      _completeStartupErrorIfPending(StateError('Failed to start NDGR stream'));
      _emitDisconnected();
      return;
    }

    _completeStartupErrorIfPending(
      StateError('NDGR stream disconnected before startup completed'),
    );
    _emitDisconnected();
  }

  void _handleClientEvent(ndgr_impl.NdgrClientEvent event) {
    switch (event.type) {
      case ndgr_impl.NdgrClientEventType.connected:
        _completeStartupIfPending();
        break;
      case ndgr_impl.NdgrClientEventType.message:
        _completeStartupIfPending();
        final AppMessage? message = event.message;
        if (message == null || _messagesController.isClosed) {
          return;
        }
        _messagesController.add(message);
        break;
      case ndgr_impl.NdgrClientEventType.stalled:
        _completeStartupIfPending();
        if (_eventsController.isClosed) {
          return;
        }
        final String? at = _client.lastNextAt?.asQueryValue();
        _eventsController.add(
          reconnect.NdgrEvent(
            reconnect.NdgrEventType.stalled,
            resumeCursor: reconnect.NdgrResumeCursor(at: at, next: at),
          ),
        );
        break;
    }
  }

  ndgr_impl.NdgrAt _resumeCursorToAt(reconnect.NdgrResumeCursor? resumeCursor) {
    final String? rawAt = resumeCursor?.at ?? resumeCursor?.next;
    if (rawAt == null || rawAt.isEmpty || rawAt == 'now') {
      return ndgr_impl.NdgrAt.now;
    }

    final int? parsed = int.tryParse(rawAt);
    if (parsed == null || parsed < 0) {
      return ndgr_impl.NdgrAt.now;
    }

    return ndgr_impl.NdgrAt.timestamp(parsed);
  }

  void _emitDisconnected() {
    if (_disconnectRequested || _eventsController.isClosed) {
      return;
    }

    _eventsController.add(
      const reconnect.NdgrEvent(reconnect.NdgrEventType.disconnected),
    );
  }

  void _completeStartupIfPending() {
    final Completer<void>? completer = _pendingStartupCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
    _pendingStartupCompleter = null;
  }

  void _completeStartupErrorIfPending(Object error) {
    final Completer<void>? completer = _pendingStartupCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.completeError(error);
    _pendingStartupCompleter = null;
  }
}

class _LegacyCommentClientAdapter implements reconnect.LegacyCommentClient {
  _LegacyCommentClientAdapter({required legacy_impl.LegacyCommentClient client})
      : _client = client {
    _messageSubscription = _client.messages.listen((AppMessage message) {
      if (_messagesController.isClosed) {
        return;
      }
      _messagesController.add(message);
    });

    _errorSubscription = _client.errors.listen((_) {
      if (_isDisconnecting || _eventsController.isClosed) {
        return;
      }
      _eventsController.add(
        const reconnect.LegacyCommentEvent(
          reconnect.LegacyCommentEventType.disconnected,
        ),
      );
    });
  }

  final legacy_impl.LegacyCommentClient _client;
  final StreamController<reconnect.LegacyCommentEvent> _eventsController =
      StreamController<reconnect.LegacyCommentEvent>.broadcast();
  final StreamController<AppMessage> _messagesController =
      StreamController<AppMessage>.broadcast();
  late final StreamSubscription<AppMessage> _messageSubscription;
  late final StreamSubscription<legacy_impl.LegacyCommentClientError>
      _errorSubscription;

  bool _isDisconnecting = false;

  Stream<AppMessage> get messages => _messagesController.stream;

  @override
  Stream<reconnect.LegacyCommentEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(Uri wsUrl) async {
    await disconnect();
    await _client.connect(wsUrl.toString());
  }

  @override
  Future<void> disconnect() async {
    _isDisconnecting = true;
    try {
      await _client.disconnect();
    } finally {
      _isDisconnecting = false;
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageSubscription.cancel();
    await _errorSubscription.cancel();
    await _client.dispose();
    await _eventsController.close();
    await _messagesController.close();
  }
}
