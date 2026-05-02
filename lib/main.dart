import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/auth/oauth_auth_controller.dart';
import 'application/auth/oauth_auth_scope.dart';
import 'application/comment_post/comment_post_controller.dart';
import 'application/filter/broadcaster_ng_migrator.dart';
import 'application/foreground_service/foreground_service_controller.dart';
import 'application/migration/app_migration_runner.dart';
import 'application/onboarding/onboarding_store.dart';
import 'application/settings/settings_store.dart';
import 'application/settings/shared_preferences_adapter.dart';
import 'application/speech/speech_availability_notifier.dart';
import 'application/upgrade/upgrade_initializer.dart';
import 'application/statistics/statistics_store.dart';
import 'application/timeline/timeline_store.dart';
import 'data/auth/oauth_bff/oauth_bff_auth_service.dart';
import 'data/auth/oauth_bff/oauth_bff_client.dart';
import 'data/auth/oauth_bff/oauth_bff_config.dart';
import 'data/auth/oauth_bff/oauth_state_generator.dart';
import 'data/auth/oauth_bff/oauth_state_store.dart';
import 'data/auth/oauth_bff/oauth_token_store.dart';
import 'data/auth/user_session_store.dart';
import 'data/comment/live_comment_repository.dart';
import 'data/comment_log/comment_log_writer.dart';
import 'data/connection/program_info_resolver.dart';
import 'data/filter/broadcaster_ng_store.dart';
import 'data/broadcast/broadcast_control_repository.dart';
import 'data/follow/follow_program_repository.dart';
import 'data/follow/my_program_repository.dart';
import 'data/foreground_service/foreground_service_manager.dart';
import 'data/niconico/broadcaster_embed_resolver.dart';
import 'data/connection/web_socket_channel_legacy_web_socket.dart';
import 'data/user/file_user_attribute_store.dart';
import 'data/user/user_attribute_store.dart';
import 'data/user/user_attribute_store_migrator.dart';
import 'data/user/user_name_resolver.dart';
import 'application/timeshift_fetch/timeshift_fetch_controller.dart';
import 'domain/connection/connection_clients.dart' as reconnect;
import 'domain/connection/connection_supervisor.dart';
import 'domain/connection/legacy_comment_client.dart' as legacy_impl;
import 'domain/connection/ndgr_client.dart' as ndgr_impl;
import 'domain/connection/ndgr_timeshift_client.dart';
import 'domain/connection/session_ws_client.dart' as session_impl;
import 'domain/models/app_message.dart';
import 'domain/models/app_settings.dart';
import 'domain/models/user_name_resolution.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/select/select_screen.dart';
import 'presentation/strings/app_strings.dart';
import 'presentation/theme/app_theme.dart';

/// Feature flag: タイムシフト（過去放送）コメント取得の有効化。
///
/// Issue #639 / #654 / #173 のフォローアップ。`programinfo` レスポンスから
/// 真の `viewUri` を取得する経路が未確立のため、`fetchInitial` を呼ぶと
/// 内部で 4xx / 5xx を踏んで生ログエラーへ落ちる。暫定対応として本フラグを
/// `false` に固定し、検出時はユーザ向けに「未対応」ダイアログを 1 度だけ
/// 提示する no-op に差し替える。
///
/// 取得経路の調査・実装が完了したら本フラグを `true` に戻し、
/// `_tryStartTimeshiftInitial` の no-op 分岐を削除して
/// `fetchInitial(viewApiUri)` を再配線する。`AppStrings.timeshift.unsupported*`
/// と関連 widget テストもそのタイミングで除去対象になる。
const bool kTimeshiftFetchEnabled = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route Flutter framework errors (assertions, build errors) to Logcat
  // using debugPrint so they appear under the `flutter` tag consistently.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint(
      '[FlutterError] ${details.exceptionAsString()}\n'
      '${details.stack}',
    );
  };

  // Catch uncaught async errors (e.g. from microtasks, Future callbacks)
  // that don't go through FlutterError.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher.onError] $error\n$stack');
    return false; // propagate to default handler
  };

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SharedPreferencesLike prefsAdapter = SharedPreferencesAdapter(prefs);

  // Clear ephemeral keys (transient runtime state) on APK update.
  // Runs before migrations so that stale ephemeral values do not
  // interfere with data transformations.
  //
  // Note: in-memory caches in `CommentPostController` /
  // `MyProgramRepository` (broadcaster status, tool-fallback null) are
  // NOT cleared here because Android kills the process on APK upgrade,
  // so the controllers below are constructed with empty caches by
  // definition. The runtime invalidation hooks live at the events that
  // can flip broadcaster status mid-session — `_endBroadcastFromMenu`
  // in `comment_screen` — see #752 for the broader rationale.
  final UpgradeInitializer upgradeInitializer = UpgradeInitializer(
    prefs: prefsAdapter,
  );
  await upgradeInitializer.run();

  final Directory appDocDir = await getApplicationDocumentsDirectory();
  final Directory tempDir = await getTemporaryDirectory();
  final SettingsStore settingsStore = SharedPreferencesSettingsStore(
    prefs: prefsAdapter,
    tempDirectory: tempDir,
  );
  final AppSettings initialSettings = await settingsStore.load();
  final UserSessionStore userSessionStore = SecureUserSessionStore(
    prefs: prefs,
  );

  final CommentLogWriter commentLogWriter = FileCommentLogWriter(
    directory: Directory('${appDocDir.path}/comment_logs'),
    tempDirectory: Directory('${tempDir.path}/comment_logs'),
  );
  // File-based user attribute store. Each write calls fsync via
  // `File.writeAsString(flush: true)`, and SelectScreen flushes pending
  // writes on lifecycle pause.  This replaces SharedPreferences which
  // the pub.dev docs advise against using for critical data, and gives
  // a cleaner per-broadcaster file layout for future extensibility.
  final FileUserAttributeStore fileUserAttributeStore = FileUserAttributeStore(
    root: Directory('${appDocDir.path}/user_attributes'),
  );
  // One-shot migration from legacy SharedPreferences storage. No-op after
  // the first successful run (tracked via the `usercolor.migratedToFile`
  // marker key).
  await UserAttributeStoreMigrator(
    prefs: prefsAdapter,
    fileStore: fileUserAttributeStore,
  ).run();
  final UserAttributeStore userAttributeStore = fileUserAttributeStore;

  // Per-broadcaster NG store (Issue #727). Models the same template +
  // per-broadcaster duplication pattern used for user attributes, so the
  // user's existing global NG settings remain effective for newly-seen
  // broadcasters while still allowing per-broadcaster divergence.
  //
  // The migrator seeds the new layout once per install. The seed list of
  // broadcaster IDs is read from the legacy `usercolor._index` key in
  // SharedPreferences — this is the most accurate "broadcasters the user
  // has interacted with" signal available at startup without forcing the
  // file-based user attribute store to expose its index publicly.
  // Failures inside the migrator are logged and do not block startup.
  final BroadcasterNgStore broadcasterNgStore =
      SharedPreferencesBroadcasterNgStore(prefs: prefsAdapter);
  await BroadcasterNgMigrator.migrateIfNeeded(
    prefs: prefsAdapter,
    store: broadcasterNgStore,
    knownBroadcasterIds:
        SharedPreferencesUserAttributeStore.readKnownBroadcasterIdsFromPrefs(
          prefsAdapter,
        ),
  );

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

  // OAuth + App Links + BFF login orchestrator. Constructed once at app
  // startup so the App Links listener it attaches in initState lives for
  // the app lifetime — callbacks delivered while the user is anywhere in
  // the app must not get lost.
  //
  // The underlying config is read from --dart-define values
  // (NICONICO_OAUTH_CLIENT_ID / OAUTH_BFF_HOST / OAUTH_AUTHORIZE_ENDPOINT).
  // When any are missing, OAuthAuthController.isFullyConfigured returns
  // false and UI screens hide the OAuth login entry point — the
  // controller is still safe to construct in that state.
  final OAuthBffConfig oauthConfig = OAuthBffConfig.production();
  final OAuthAuthController oauthAuthController = OAuthAuthController(
    service: OAuthBffAuthService(
      config: oauthConfig,
      stateGenerator: SecureOAuthStateGenerator(),
      stateStore: SecureOAuthStateStore(),
      tokenStore: SecureOAuthTokenStore(),
      bffClient: OAuthBffClient(tokenEndpoint: oauthConfig.bffTokenEndpoint),
    ),
  );

  runApp(
    ComeruneApp(
      settingsStore: settingsStore,
      initialSettings: initialSettings,
      userSessionStore: userSessionStore,
      commentLogWriter: commentLogWriter,
      userAttributeStore: userAttributeStore,
      broadcasterNgStore: broadcasterNgStore,
      foregroundServiceManager: foregroundServiceManager,
      onboardingStore: onboardingStore,
      oauthAuthController: oauthAuthController,
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
    this.broadcasterNgStore,
    this.foregroundServiceManager,
    required this.onboardingStore,
    required this.oauthAuthController,
  });

  final SettingsStore settingsStore;
  final AppSettings initialSettings;
  final UserSessionStore userSessionStore;
  final CommentLogWriter? commentLogWriter;
  final UserAttributeStore? userAttributeStore;
  final BroadcasterNgStore? broadcasterNgStore;
  final ForegroundServiceManager? foregroundServiceManager;
  final OnboardingStore onboardingStore;
  final OAuthAuthController oauthAuthController;

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
  // Issue #639 / #654: 同一 lv で再接続が走るたびに「未対応」ダイアログを
  // 重ねて出さないよう、最後に提示した lv を記録する。
  // `kTimeshiftFetchEnabled` を true に戻す際は本フィールドも併せて削除する。
  String? _lastTimeshiftUnsupportedDialogLv;
  // initState で initialSettings.pastCommentFetchCount.historyCount に
  // 上書きされるため値そのものは一時的なもの。AppSettings.defaults と
  // 整合を取るため 500 を初期値としている。
  int _ndgrHistoryCount = 500;
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
  // Issue #739: cross-component view of the "broadcast-end grace" toggle.
  // Owned by main so [_foregroundServiceController] can read the latest
  // value at the moment of `ConnectionStatus.ended` even after the user
  // changes the setting in the TTS settings screen.
  late final ValueNotifier<bool> _playRemainingAfterEndedNotifier;
  // Issue #694: cross-screen Android TTS availability source. Lives for the
  // lifetime of the app so the comment screen and the TTS settings screen
  // share the same view of the latest check result.
  final SpeechAvailabilityNotifier _androidTtsAvailability =
      SpeechAvailabilityNotifier();
  late final UserNameResolver _userNameResolver;
  late final BroadcasterEmbedResolver _broadcasterEmbedResolver;
  late final FollowProgramRepository _followProgramRepository;
  late final MyProgramRepository _myProgramRepository;
  late final BroadcastControlRepository _broadcastControlRepository;
  late final LiveCommentRepository _liveCommentRepository;
  late final CommentPostController _commentPostController;
  late final NdgrTimeshiftClient _timeshiftClient;
  late final TimeshiftFetchController _timeshiftFetchController;
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

    _playRemainingAfterEndedNotifier = ValueNotifier<bool>(
      widget.initialSettings.playRemainingAfterEnded,
    );

    _userNameResolver = UserNameResolver();
    _broadcasterEmbedResolver = BroadcasterEmbedResolver();
    _followProgramRepository = FollowProgramRepository();
    _myProgramRepository = MyProgramRepository();
    _broadcastControlRepository = BroadcastControlRepository();
    _liveCommentRepository = LiveCommentRepository();
    _commentPostController = CommentPostController(
      liveCommentRepository: _liveCommentRepository,
      myProgramRepository: _myProgramRepository,
    );
    _timelineStore = TimelineStore(
      capacity: widget.initialSettings.pastCommentFetchCount.displayCapacity,
    );
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
      // Issue #639 cause 4: programinfo が「ended」を返した放送
      // （タイムシフト）では、過去コメントを NDGR HTTP 経由で
      // 取得するよう TimeshiftFetchController に viewApiUri を
      // 渡して初回取得を開始する。同じ URL で二重起動を避けるため
      // 既に実行中/完了している場合はスキップする。
      onTimeshiftDetected: (Uri viewApiUri) {
        unawaited(_tryStartTimeshiftInitial(viewApiUri));
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

    _timeshiftClient = NdgrTimeshiftClient();
    _timeshiftFetchController = TimeshiftFetchController(
      client: _timeshiftClient,
      onMessages: (List<AppMessage> messages) {
        _timelineStore.addAll(messages);
      },
    );

    if (widget.foregroundServiceManager != null) {
      _foregroundServiceController = ForegroundServiceController(
        foregroundServiceManager: widget.foregroundServiceManager!,
        connectionSupervisor: _connectionSupervisor,
        programTitleNotifier: _programTitleNotifier,
        // Issue #739: read the live "grace on broadcast-end" preference at
        // the moment the controller decides whether to grace.
        playRemainingAfterEnded: () => _playRemainingAfterEndedNotifier.value,
      );
    }

    _ndgrMessageSubscription = _ndgrClient.messages.listen((
      AppMessage message,
    ) {
      // Silent timestamp update — `_timelineStore.add` /
      // `_statisticsStore.recordComment` below already trigger a rebuild
      // of CommentScreen via the ListenableBuilder in select_screen, so
      // the StatusBar's `最終受信` text picks up the fresh value without
      // an extra supervisor-level notify (which would re-run wakelock /
      // auto-save plumbing per comment).
      _connectionSupervisor.recordReceivedAt(notify: false);
      _timelineStore.add(message);
      _statisticsStore.recordComment(message);
    });
    _legacyMessageSubscription = _legacyCommentClient.messages.listen((
      AppMessage message,
    ) {
      _connectionSupervisor.recordReceivedAt(notify: false);
      _timelineStore.add(message);
      _statisticsStore.recordComment(message);
    });
    _ndgrViewerCountSubscription = _ndgrClient.viewerCounts.listen(
      _statisticsStore.updateViewerCount,
    );

    // Subscribe to App Links so the OIDC callback delivered by Android
    // after the user returns from the browser is routed into the
    // OAuthBffAuthService. Idempotent inside the controller; safe even
    // if the OAuth login entry point is hidden (the flow simply never
    // gets triggered, and no callback arrives).
    unawaited(widget.oauthAuthController.attach());
  }

  /// Called when [_SessionWsClientAdapter] detects a timeshift (ended)
  /// broadcast from the programinfo response. Routes past-comment
  /// retrieval to [TimeshiftFetchController.fetchInitial] so the user
  /// does not have to trigger it manually (Issue #639 cause 4).
  ///
  /// Idempotent: if the controller is already fetching (or has progressed
  /// past idle in this session) the call is skipped. This prevents double
  /// initial-fetches when session resolution happens more than once
  /// (e.g. reconnect attempts) while the previous fetch is still running
  /// or already collected past comments.
  ///
  /// Issue #639 / #654 暫定対応: [kTimeshiftFetchEnabled] が `false` の間は
  /// `fetchInitial` を呼ばず、ユーザに「未対応（将来対応予定）」ダイアログを
  /// 1 度だけ提示する no-op として動作する。`viewApiUri` は将来の再有効化を
  /// 見越して引数として残してあり、フラグを true に戻すだけで本来の経路に
  /// 復帰できる。生ログエラーへの誤遷移防止が主目的のため、ダイアログ表示が
  /// 失敗してもアプリの他機能は影響を受けないよう副作用は最小に留める。
  Future<void> _tryStartTimeshiftInitial(Uri viewApiUri) async {
    if (!kTimeshiftFetchEnabled) {
      _showTimeshiftUnsupportedDialogIfNeeded();
      return;
    }
    if (_timeshiftFetchController.status != TimeshiftFetchStatus.idle) {
      return;
    }
    try {
      await _timeshiftFetchController.fetchInitial(viewApiUri);
    } on Object catch (error, stackTrace) {
      log(
        'Timeshift initial fetch failed',
        name: 'App',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 「タイムシフト未対応」ダイアログを同一 lv あたり 1 度だけ提示する。
  ///
  /// Issue #639 / #654 / #173 暫定対応。本来の取得経路が確立したら
  /// 呼び出し元の no-op 分岐ごと削除する。Navigator が未マウント等で
  /// ダイアログを出せない場合は副作用なく抜ける（`AGENTS.md` の
  /// 「Optional Reference Two-Stage Fallback」方針に準じ、内部構造を
  /// 露出しないログだけ残す）。
  void _showTimeshiftUnsupportedDialogIfNeeded() {
    final String lv = _currentLv;
    if (lv.isEmpty) {
      return;
    }
    if (_lastTimeshiftUnsupportedDialogLv == lv) {
      return;
    }
    _lastTimeshiftUnsupportedDialogLv = lv;

    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) {
      log(
        'Skipped timeshift-unsupported dialog (no navigator yet)',
        name: 'App',
      );
      return;
    }

    // ダイアログの非同期表示中に lv が切り替わっても問題ないよう、
    // 状態は引数経由で閉じ込める。表示失敗時は黙ってスキップ。
    unawaited(
      showDialog<void>(
        context: navigator.context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            key: const Key('timeshift-unsupported-dialog'),
            title: Text(AppStrings.timeshift.unsupportedDialogTitle),
            content: Text(AppStrings.timeshift.unsupportedDialogBody),
            actions: <Widget>[
              TextButton(
                key: const Key('timeshift-unsupported-dialog-confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(AppStrings.timeshift.unsupportedDialogConfirm),
              ),
            ],
          );
        },
      ).catchError((Object error, StackTrace stackTrace) {
        log(
          'Failed to present timeshift-unsupported dialog',
          name: 'App',
          error: error,
          stackTrace: stackTrace,
        );
      }),
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
    _broadcasterEmbedResolver.dispose();
    // Dispose the CommentPostController before its dependencies so any
    // in-flight postComment / ensureBroadcasterStatus future sees the
    // disposed flag before we close the underlying HttpClients.
    _commentPostController.dispose();
    _timeshiftFetchController.dispose();
    _timeshiftClient.dispose();
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
    _playRemainingAfterEndedNotifier.dispose();
    _androidTtsAvailability.dispose();
    // Detach the App Links listener and close the OAuth BFF http.Client.
    // dispose() returns a Future but State.dispose() is sync — the
    // teardown is fire-and-forget at app shutdown, which is safe because
    // the process is about to be torn down by Android.
    unawaited(widget.oauthAuthController.dispose());
    super.dispose();
  }

  void _onThemeModeChanged() {
    setState(() {});
  }

  Future<void> _prepareConnection(String lv, AppSettings settings) async {
    _currentLv = lv;
    // 異なる lv へ切り替わったタイミングで「未対応」ダイアログの提示履歴を
    // リセットし、次回の検出で再度ユーザに案内できるようにする。
    if (_lastTimeshiftUnsupportedDialogLv != null &&
        _lastTimeshiftUnsupportedDialogLv != lv) {
      _lastTimeshiftUnsupportedDialogLv = null;
    }
    _programTitleNotifier.value = null;
    _broadcasterNameNotifier.value = null;
    _supplierUserIdNotifier.value = null;
    _beginAtNotifier.value = null;
    _vposBaseAtNotifier.value = null;
    _ndgrHistoryCount = settings.pastCommentFetchCount.historyCount;
    // TimelineStore の capacity は _SelectScreen 側が接続開始 / 再接続の直前に
    // pastCommentFetchCount.displayCapacity で更新する。ここで二重に呼ぶと
    // 責務が分散するため、本メソッドでは NDGR 取得数と統計のリセットに専念する。
    _statisticsStore.reset();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeMode currentMode = _themeModeNotifier.value;
    return WithForegroundTask(
      child: OAuthAuthScope(
        controller: widget.oauthAuthController,
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
              seedCache: _userNameResolver.seedCache,
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
            broadcasterNgStore: widget.broadcasterNgStore,
            commentPostController: _commentPostController,
            timeshiftFetchController: _timeshiftFetchController,
            androidTtsAvailability: _androidTtsAvailability,
            broadcasterEmbedResolver: _broadcasterEmbedResolver,
            playRemainingAfterEndedSink: _playRemainingAfterEndedNotifier,
            // Issue #739: when the comment screen finishes draining its speech
            // queue inside the grace window, signal the FGS controller so its
            // parallel grace timer can end early too instead of waiting out
            // the full 30 s. No-op when the FGS controller is not configured.
            onSpeechQueueDrained:
                _foregroundServiceController?.notifyQueueDrained,
          ),
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
    void Function(Uri viewApiUri)? onTimeshiftDetected,
  }) : _lvProvider = lvProvider,
       _userSessionProvider = userSessionProvider,
       _programInfoResolver = programInfoResolver,
       _onProgramTitleResolved = onProgramTitleResolved,
       _onSupplierUserIdResolved = onSupplierUserIdResolved,
       _onBroadcasterNameResolved = onBroadcasterNameResolved,
       _onBeginAtResolved = onBeginAtResolved,
       _onVposBaseAtResolved = onVposBaseAtResolved,
       _onTimeshiftDetected = onTimeshiftDetected;

  final String Function() _lvProvider;
  final Future<String> Function() _userSessionProvider;
  final ProgramInfoResolver _programInfoResolver;
  final void Function(String title)? _onProgramTitleResolved;
  final void Function(String userId)? _onSupplierUserIdResolved;
  final void Function(String? userId, String name)? _onBroadcasterNameResolved;
  final void Function(DateTime beginAt)? _onBeginAtResolved;
  final void Function(DateTime vposBaseAt)? _onVposBaseAtResolved;
  final void Function(Uri viewApiUri)? _onTimeshiftDetected;
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
      // Issue #639 cause 2: for ended broadcasts (timeshift) notify the
      // caller so they can route fetching through the NDGR timeshift HTTP
      // flow.
      if (programInfo.isTimeshift) {
        _onTimeshiftDetected?.call(programInfo.viewUri);
      }
      log(
        'Resolved NDGR endpoint via programinfo API '
        '(status: ${programInfo.programStatus?.name ?? 'unknown'})',
        name: 'SessionWsClientAdapter',
      );
      // Issue #639 follow-up: when the broadcast is already ended,
      // short-circuit the live NDGR streaming path. Both
      // `NdgrClient` (live) and `NdgrTimeshiftClient` (HTTP) would
      // otherwise race on the same viewUri — independent HttpClient
      // instances, same host, same query shape — which risks:
      //   - server-side rate limits (HTTP 429) on duplicated fetches
      //   - contradictory UI state (`ndgrStreamFailed` snackbar while
      //     timeshift panel shows a different error classification)
      //   - wasted bandwidth for the ~N00 ms until the live path
      //     receives the ended signal on its first chunk
      // Throwing `broadcastEnded` routes ConnectionSupervisor directly
      // to `ConnectionStatus.ended` via `endBroadcast()` without
      // attempting to stream. The timeshift fetch started via
      // `onTimeshiftDetected` above continues independently.
      if (programInfo.isTimeshift) {
        throw const reconnect.SessionWsConnectException(
          reconnect.SessionWsConnectFailureKind.broadcastEnded,
        );
      }
      return reconnect.SessionEndpoints(ndgrViewApiUri: programInfo.viewUri);
    } on reconnect.SessionWsConnectException {
      // Re-throw our own signalling exception so it is not swallowed by
      // the broad fallback handlers below. ConnectionSupervisor maps
      // `broadcastEnded` into `endBroadcast()` directly.
      rethrow;
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
