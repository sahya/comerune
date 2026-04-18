import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/comment_post/comment_post_controller.dart';
import 'application/foreground_service/foreground_service_controller.dart';
import 'application/migration/app_migration_runner.dart';
import 'application/onboarding/onboarding_store.dart';
import 'application/settings/settings_store.dart';
import 'application/settings/shared_preferences_adapter.dart';
import 'application/upgrade/upgrade_initializer.dart';
import 'application/statistics/statistics_store.dart';
import 'application/timeline/timeline_store.dart';
import 'data/auth/user_session_store.dart';
import 'data/comment/live_comment_repository.dart';
import 'data/comment_log/comment_log_writer.dart';
import 'data/connection/program_info_resolver.dart';
import 'data/broadcast/broadcast_control_repository.dart';
import 'data/follow/follow_program_repository.dart';
import 'data/follow/my_program_repository.dart';
import 'data/foreground_service/foreground_service_manager.dart';
import 'data/connection/web_socket_channel_legacy_web_socket.dart';
import 'data/user/user_attribute_store.dart';
import 'data/user/user_name_resolver.dart';
import 'domain/connection/connection_clients.dart' as reconnect;
import 'domain/connection/connection_supervisor.dart';
import 'domain/connection/legacy_comment_client.dart' as legacy_impl;
import 'domain/connection/ndgr_client.dart' as ndgr_impl;
import 'domain/connection/session_ws_client.dart' as session_impl;
import 'domain/models/app_message.dart';
import 'domain/models/app_settings.dart';
import 'domain/models/user_name_resolution.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/select/select_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SharedPreferencesLike prefsAdapter = SharedPreferencesAdapter(prefs);

  // Clear ephemeral keys (transient runtime state) on APK update.
  // Runs before migrations so that stale ephemeral values do not
  // interfere with data transformations.
  final UpgradeInitializer upgradeInitializer = UpgradeInitializer(
    prefs: prefsAdapter,
  );
  await upgradeInitializer.run();

  final SettingsStore settingsStore = SharedPreferencesSettingsStore(
    prefs: prefsAdapter,
  );
  final AppSettings initialSettings = await settingsStore.load();
  final UserSessionStore userSessionStore = SecureUserSessionStore(
    prefs: prefs,
  );

  final Directory appDocDir = await getApplicationDocumentsDirectory();
  final Directory tempDir = await getTemporaryDirectory();
  final CommentLogWriter commentLogWriter = FileCommentLogWriter(
    directory: Directory('${appDocDir.path}/comment_logs'),
    tempDirectory: Directory('${tempDir.path}/comment_logs'),
  );
  final UserAttributeStore userAttributeStore =
      SharedPreferencesUserAttributeStore(prefs: prefsAdapter);
  // Run one-time migration tasks when the app version changes.
  // Awaited so that migrations complete before the app reads settings or
  // user data that a migration might alter.
  final AppMigrationRunner migrationRunner = AppMigrationRunner(
    prefs: prefsAdapter,
  );
  await migrationRunner.run();

  // Remove user attribute entries not accessed for over 1 year.
  unawaited(userAttributeStore.cleanup());

  final OnboardingStore onboardingStore = SharedPreferencesOnboardingStore(
    prefs: prefsAdapter,
  );

  ForegroundServiceManager? foregroundServiceManager;
  if (Platform.isAndroid) {
    foregroundServiceManager = ForegroundServiceManager();
    foregroundServiceManager.init();
  }

  runApp(
    ComeruneApp(
      settingsStore: settingsStore,
      initialSettings: initialSettings,
      userSessionStore: userSessionStore,
      commentLogWriter: commentLogWriter,
      userAttributeStore: userAttributeStore,
      foregroundServiceManager: foregroundServiceManager,
      onboardingStore: onboardingStore,
    ),
  );
}

class ComeruneApp extends StatefulWidget {
  const ComeruneApp({
    super.key,
    required this.settingsStore,
    required this.initialSettings,
    required this.userSessionStore,
    this.commentLogWriter,
    this.userAttributeStore,
    this.foregroundServiceManager,
    required this.onboardingStore,
  });

  final SettingsStore settingsStore;
  final AppSettings initialSettings;
  final UserSessionStore userSessionStore;
  final CommentLogWriter? commentLogWriter;
  final UserAttributeStore? userAttributeStore;
  final ForegroundServiceManager? foregroundServiceManager;
  final OnboardingStore onboardingStore;

  @override
  State<ComeruneApp> createState() => _ComeruneAppState();
}

class _ComeruneAppState extends State<ComeruneApp> {
  late final TimelineStore _timelineStore;
  late final StatisticsStore _statisticsStore;
  late final _SessionWsClientAdapter _sessionWsClient;
  late final _NdgrClientAdapter _ndgrClient;
  late final _LegacyCommentClientAdapter _legacyCommentClient;
  late final ConnectionSupervisor _connectionSupervisor;
  late final StreamSubscription<AppMessage> _ndgrMessageSubscription;
  late final StreamSubscription<AppMessage> _legacyMessageSubscription;
  late final StreamSubscription<int?> _ndgrViewerCountSubscription;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String _currentLv = '';
  int _ndgrHistoryCount = 100;
  final ValueNotifier<String?> _programTitleNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<String?> _broadcasterNameNotifier =
      ValueNotifier<String?>(null);
  final ValueNotifier<String?> _supplierUserIdNotifier = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<DateTime?> _beginAtNotifier = ValueNotifier<DateTime?>(
    null,
  );
  // Issue #465: separate from _beginAtNotifier so the vpos reference can
  // differ from the display-time reference (N Air uses
  // programSchedule.vposBaseTime for vpos calculation, which can drift
  // from beginAt on extended / rehearsal broadcasts).
  final ValueNotifier<DateTime?> _vposBaseAtNotifier = ValueNotifier<DateTime?>(
    null,
  );
  late final ValueNotifier<AppThemeMode> _themeModeNotifier;
  late final UserNameResolver _userNameResolver;
  late final FollowProgramRepository _followProgramRepository;
  late final MyProgramRepository _myProgramRepository;
  late final BroadcastControlRepository _broadcastControlRepository;
  late final LiveCommentRepository _liveCommentRepository;
  late final CommentPostController _commentPostController;
  ForegroundServiceController? _foregroundServiceController;

  @override
  void initState() {
    super.initState();
    if (!widget.onboardingStore.isCompleted()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final NavigatorState? navigator = _navigatorKey.currentState;
        if (navigator != null) {
          showOnboardingDialog(
            context: navigator.context,
            onboardingStore: widget.onboardingStore,
          );
        }
      });
    }
    _ndgrHistoryCount =
        widget.initialSettings.pastCommentFetchCount.historyCount;
    _themeModeNotifier = ValueNotifier<AppThemeMode>(
      widget.initialSettings.themeMode,
    )..addListener(_onThemeModeChanged);

    _userNameResolver = UserNameResolver();
    _followProgramRepository = FollowProgramRepository();
    _myProgramRepository = MyProgramRepository();
    _broadcastControlRepository = BroadcastControlRepository();
    _liveCommentRepository = LiveCommentRepository();
    _commentPostController = CommentPostController(
      liveCommentRepository: _liveCommentRepository,
      myProgramRepository: _myProgramRepository,
    );
    _timelineStore = TimelineStore(capacity: _ndgrHistoryCount);
    _statisticsStore = StatisticsStore();
    _sessionWsClient = _SessionWsClientAdapter(
      lvProvider: () => _currentLv,
      userSessionProvider: () => widget.userSessionStore.load(),
      programInfoResolver: ProgramInfoResolver(),
      onProgramTitleResolved: (String title) {
        _programTitleNotifier.value = title;
      },
      onSupplierUserIdResolved: (String userId) {
        _supplierUserIdNotifier.value = userId;
        _userNameResolver.requestResolve(userId);
      },
      onBroadcasterNameResolved: (String? userId, String name) {
        _broadcasterNameNotifier.value = name;
        if (userId != null) {
          _userNameResolver.seedCache(userId, name);
        }
      },
      onBeginAtResolved: (DateTime beginAt) {
        _beginAtNotifier.value = beginAt;
      },
      onVposBaseAtResolved: (DateTime vposBaseAt) {
        _vposBaseAtNotifier.value = vposBaseAt;
      },
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

    if (widget.foregroundServiceManager != null) {
      _foregroundServiceController = ForegroundServiceController(
        foregroundServiceManager: widget.foregroundServiceManager!,
        connectionSupervisor: _connectionSupervisor,
        programTitleNotifier: _programTitleNotifier,
      );
    }

    _ndgrMessageSubscription = _ndgrClient.messages.listen((
      AppMessage message,
    ) {
      _timelineStore.add(message);
      _statisticsStore.recordComment(message);
    });
    _legacyMessageSubscription = _legacyCommentClient.messages.listen((
      AppMessage message,
    ) {
      _timelineStore.add(message);
      _statisticsStore.recordComment(message);
    });
    _ndgrViewerCountSubscription = _ndgrClient.viewerCounts.listen(
      _statisticsStore.updateViewerCount,
    );
  }

  @override
  void dispose() {
    _foregroundServiceController?.dispose();
    unawaited(_ndgrMessageSubscription.cancel());
    unawaited(_legacyMessageSubscription.cancel());
    unawaited(_ndgrViewerCountSubscription.cancel());
    _connectionSupervisor.dispose();
    unawaited(_sessionWsClient.dispose());
    unawaited(_ndgrClient.dispose());
    unawaited(_legacyCommentClient.dispose());
    _timelineStore.dispose();
    _statisticsStore.dispose();
    _userNameResolver.dispose();
    // Dispose the CommentPostController before its dependencies so any
    // in-flight postComment / ensureBroadcasterStatus future sees the
    // disposed flag before we close the underlying HttpClients.
    _commentPostController.dispose();
    _followProgramRepository.dispose();
    _myProgramRepository.dispose();
    _broadcastControlRepository.dispose();
    _liveCommentRepository.dispose();
    _programTitleNotifier.dispose();
    _broadcasterNameNotifier.dispose();
    _supplierUserIdNotifier.dispose();
    _beginAtNotifier.dispose();
    _vposBaseAtNotifier.dispose();
    _themeModeNotifier
      ..removeListener(_onThemeModeChanged)
      ..dispose();
    super.dispose();
  }

  void _onThemeModeChanged() {
    setState(() {});
  }

  Future<void> _prepareConnection(String lv, AppSettings settings) async {
    _currentLv = lv;
    _programTitleNotifier.value = null;
    _broadcasterNameNotifier.value = null;
    _supplierUserIdNotifier.value = null;
    _beginAtNotifier.value = null;
    _vposBaseAtNotifier.value = null;
    _ndgrHistoryCount = settings.pastCommentFetchCount.historyCount;
    _timelineStore.setCapacity(_ndgrHistoryCount);
    _statisticsStore.reset();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeMode currentMode = _themeModeNotifier.value;
    return WithForegroundTask(
      child: MaterialApp(
        title: 'comerune',
        theme: AppTheme.themeDataFor(currentMode),
        darkTheme: currentMode == AppThemeMode.system
            ? AppTheme.themeDataFor(AppThemeMode.dark)
            : null,
        themeMode: currentMode == AppThemeMode.system
            ? ThemeMode.system
            : ThemeMode.light,
        navigatorKey: _navigatorKey,
        home: SelectScreen(
          connectionSupervisor: _connectionSupervisor,
          timelineStore: _timelineStore,
          statisticsStore: _statisticsStore,
          settingsStore: widget.settingsStore,
          initialSettings: widget.initialSettings,
          onPrepareConnection: _prepareConnection,
          userSessionStore: widget.userSessionStore,
          programTitleNotifier: _programTitleNotifier,
          userNameResolution: UserNameResolution(
            resolve: _userNameResolver.getCachedName,
            requestResolve: _userNameResolver.requestResolve,
            listenable: _userNameResolver,
          ),
          broadcasterNameNotifier: _broadcasterNameNotifier,
          supplierUserIdNotifier: _supplierUserIdNotifier,
          beginAtNotifier: _beginAtNotifier,
          vposBaseAtNotifier: _vposBaseAtNotifier,
          commentLogWriter: widget.commentLogWriter,
          themeModeNotifier: _themeModeNotifier,
          followProgramRepository: _followProgramRepository,
          myProgramRepository: _myProgramRepository,
          broadcastControlRepository: _broadcastControlRepository,
          userAttributeStore: widget.userAttributeStore,
          commentPostController: _commentPostController,
        ),
      ),
    );
  }
}

class _SessionWsClientAdapter implements reconnect.SessionWsClient {
  _SessionWsClientAdapter({
    required String Function() lvProvider,
    required Future<String> Function() userSessionProvider,
    required ProgramInfoResolver programInfoResolver,
    void Function(String title)? onProgramTitleResolved,
    void Function(String userId)? onSupplierUserIdResolved,
    void Function(String? userId, String name)? onBroadcasterNameResolved,
    void Function(DateTime beginAt)? onBeginAtResolved,
    void Function(DateTime vposBaseAt)? onVposBaseAtResolved,
  }) : _lvProvider = lvProvider,
       _userSessionProvider = userSessionProvider,
       _programInfoResolver = programInfoResolver,
       _onProgramTitleResolved = onProgramTitleResolved,
       _onSupplierUserIdResolved = onSupplierUserIdResolved,
       _onBroadcasterNameResolved = onBroadcasterNameResolved,
       _onBeginAtResolved = onBeginAtResolved,
       _onVposBaseAtResolved = onVposBaseAtResolved;

  final String Function() _lvProvider;
  final Future<String> Function() _userSessionProvider;
  final ProgramInfoResolver _programInfoResolver;
  final void Function(String title)? _onProgramTitleResolved;
  final void Function(String userId)? _onSupplierUserIdResolved;
  final void Function(String? userId, String name)? _onBroadcasterNameResolved;
  final void Function(DateTime beginAt)? _onBeginAtResolved;
  final void Function(DateTime vposBaseAt)? _onVposBaseAtResolved;
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

    // Try N Air approach: programinfo API → viewUri directly.
    // Even if viewUri resolution fails (e.g. rooms missing), the exception
    // may carry the program title so we emit it for the fallback path.
    // We attempt this even without user_session — the API may return the
    // title (and possibly viewUri) for public broadcasts without auth.
    final String userSession = await _userSessionProvider();
    try {
      final ProgramInfo programInfo = await _programInfoResolver.resolve(
        lv: lv,
        userSession: userSession,
      );
      // Notify callbacks in dependency order:
      //   1. title — no dependencies, shown first in the UI header.
      //   2. beginAt — no dependencies, enables elapsed-time display
      //      as soon as comments start arriving.
      //   3. vposBaseAt — no dependencies; authoritative reference for
      //      comment vpos (Issue #465). Emitted adjacent to beginAt so
      //      the comment-post pipeline sees both at once and does not
      //      fall back to beginAt for a frame when both are available.
      //   4. broadcasterName — emitted even when supplierUserId is absent.
      //      If supplierUserId exists, this also seeds the name cache so
      //      the subsequent supplierUserId callback can skip a redundant
      //      HTTP resolve.
      //   5. supplierUserId — triggers name resolution; the cache is
      //      already warm if broadcasterName was available.
      if (programInfo.title != null) {
        _onProgramTitleResolved?.call(programInfo.title!);
      }
      if (programInfo.beginAt != null) {
        _onBeginAtResolved?.call(programInfo.beginAt!);
      }
      if (programInfo.vposBaseAt != null) {
        _onVposBaseAtResolved?.call(programInfo.vposBaseAt!);
      }
      if (programInfo.broadcasterName != null) {
        _onBroadcasterNameResolved?.call(
          programInfo.supplierUserId,
          programInfo.broadcasterName!,
        );
      }
      if (programInfo.supplierUserId != null) {
        _onSupplierUserIdResolved?.call(programInfo.supplierUserId!);
      }
      log(
        'Resolved NDGR endpoint via programinfo API',
        name: 'SessionWsClientAdapter',
      );
      return reconnect.SessionEndpoints(ndgrViewApiUri: programInfo.viewUri);
    } on ProgramInfoResolveException catch (error) {
      if (error.title != null) {
        _onProgramTitleResolved?.call(error.title!);
      }
      log(
        'programinfo resolution failed, falling back to WebSocket: $error',
        name: 'SessionWsClientAdapter',
      );
    } on Object catch (error) {
      log(
        'Unexpected error during programinfo resolution, '
        'falling back to WebSocket: $error',
        name: 'SessionWsClientAdapter',
      );
    }

    // Fallback: traditional WebSocket handshake flow
    final session_impl.SessionWsClient client = session_impl.SessionWsClient(
      lv: lv,
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
        _completeEndpointError(completer, failure, stackTrace: stackTrace);
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
    _programInfoResolver.dispose();
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
          final reconnect.SessionWsConnectException
          failure = reconnect.SessionWsConnectException(
            reconnect.SessionWsConnectFailureKind.endpointParseFailed,
            cause:
                'Invalid NDGR endpoint URI: ${event.ndgrViewUri ?? '(empty)'}',
          );
          _recordSessionFailure(failure);
          _completeEndpointError(completer, failure);
          break;
        }
        if (!completer.isCompleted) {
          completer.complete(reconnect.SessionEndpoints(ndgrViewApiUri: uri));
        }
        break;
      case session_impl.SessionWsEventType.legacyEndpointResolved:
        final Uri? uri = Uri.tryParse(event.legacyWebSocketUrl ?? '');
        if (uri == null) {
          final reconnect.SessionWsConnectException
          failure = reconnect.SessionWsConnectException(
            reconnect.SessionWsConnectFailureKind.endpointParseFailed,
            cause:
                'Invalid legacy endpoint URI: ${event.legacyWebSocketUrl ?? '(empty)'}',
          );
          _recordSessionFailure(failure);
          _completeEndpointError(completer, failure);
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
        _completeEndpointError(completer, failure);
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
        _completeEndpointError(completer, failure);
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
          _completeEndpointError(
            completer,
            failure,
            stackTrace: event.stackTrace,
          );
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
          cause:
              cause ??
              _defaultCauseForKind(
                reconnect.SessionWsConnectFailureKind.endpointResolveTimeout,
              ),
        );
      case session_impl.SessionWsErrorCode.connectFailed:
      case session_impl.SessionWsErrorCode.keepaliveResponseFailed:
        return reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.connectFailed,
          cause:
              cause ??
              _defaultCauseForKind(
                reconnect.SessionWsConnectFailureKind.connectFailed,
              ),
        );
      case session_impl.SessionWsErrorCode.unknownBroadcastEndEvent:
        return reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.broadcastEnded,
          cause:
              cause ??
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
  }) : _client = client,
       _historyCountProvider = historyCountProvider {
    _clientEventsSubscription = _client.events.listen(
      _handleClientEvent,
      onError: (_, _) {
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
  final StreamController<int?> _viewerCountController =
      StreamController<int?>.broadcast();
  late final StreamSubscription<ndgr_impl.NdgrClientEvent>
  _clientEventsSubscription;

  Future<void>? _activeConnectFuture;
  Completer<void>? _pendingStartupCompleter;
  bool _disconnectRequested = false;

  Stream<AppMessage> get messages => _messagesController.stream;
  Stream<int?> get viewerCounts => _viewerCountController.stream;

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
    await _viewerCountController.close();
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
      case ndgr_impl.NdgrClientEventType.statistics:
        if (!_viewerCountController.isClosed) {
          _viewerCountController.add(event.viewerCount);
        }
        break;
      case ndgr_impl.NdgrClientEventType.broadcastEnded:
        if (!_eventsController.isClosed) {
          _eventsController.add(
            const reconnect.NdgrEvent(reconnect.NdgrEventType.broadcastEnded),
          );
        }
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
