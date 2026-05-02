import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_logging.dart';
import '../../application/comment_post/comment_post_controller.dart';
import '../../application/timeshift_fetch/timeshift_fetch_controller.dart';
import '../../application/settings/settings_store.dart';
import '../../application/speech/speech_availability_notifier.dart';
import '../../application/statistics/statistics_store.dart';
import '../../application/timeline/timeline_store.dart';
import '../../data/auth/user_session_store.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../data/broadcast/broadcast_control_repository.dart';
import '../../data/filter/broadcaster_ng_store.dart';
import '../../data/follow/favorite_user_live_checker.dart';
import '../../data/niconico/broadcaster_embed_resolver.dart';
import '../../domain/models/follow_program.dart';
import '../../data/follow/follow_program_repository.dart';
import '../../data/follow/my_program_repository.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/models/ng_word_rule.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/matchers/ng_matcher.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../../domain/utils/lv_parser.dart';
import '../../domain/utils/nico_icon_url.dart';
import '../../comment_speech/comment_speech.dart'
    show MethodChannelCommentSpeech, SpeechSettings;
import '../screens/comment_screen.dart';
import '../screens/comment_screen_config.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';

void _debugLogLazy(String Function() messageBuilder) {
  appDebugLogLazy(messageBuilder);
}

void _errorLog(String message, {Object? error, StackTrace? stackTrace}) {
  appErrorLog(
    name: 'SelectScreen',
    message: message,
    error: error,
    stackTrace: stackTrace,
  );
}

// Issue #727: [BroadcasterNgSnapshot] is the in-memory tagged variant of
// the per-broadcaster NG payload. The shape is now defined in the data
// layer ([BroadcasterNgPayload] / [BroadcasterNgSnapshot] in
// `broadcaster_ng_store.dart`) so the testable helper
// [computeContentFilterInputs] below — and its tests — can reference the
// same record shape without depending on this widget file.

/// Convenience getter to avoid spelling out the empty record at every
/// call-site. Returns a fresh value each time; the constituent fields
/// themselves are still const collections so the cost is negligible.
//
// const-record-with-collections compat: the analyzer (Dart 3.x) does not
// accept a top-level `const BroadcasterNgSnapshot empty = (...)` even
// though every constituent field is itself const, so we keep the getter
// form. Revisit if the const-record story improves in a future SDK.
BroadcasterNgSnapshot get _emptyBroadcasterNgSnapshot => (
  broadcasterId: null,
  ngUserIds: const <String>{},
  rules: const <NgWordRule>[],
);

/// Pure logic for [_SelectScreenState._resolveContentFilter], extracted as
/// a top-level function so it can be unit-tested without spinning up a
/// full widget tree.
///
/// See [_SelectScreenState._resolveContentFilter] for the resolution
/// rules and the rationale for the legacy union (Issue #727 PR1).
@visibleForTesting
({Set<String> ngUserIds, List<String> ngWords}) computeContentFilterInputs({
  required AppSettings settings,
  required String? currentBroadcasterId,
  required BroadcasterNgSnapshot snapshot,
  required bool hasStore,
}) {
  // Per-broadcaster path: store is wired AND we are connected AND the
  // in-memory snapshot reflects the currently-active broadcaster (i.e.
  // not a stale load from a previous broadcaster).
  final bool perBroadcasterActive =
      hasStore &&
      currentBroadcasterId != null &&
      snapshot.broadcasterId == currentBroadcasterId;
  if (perBroadcasterActive) {
    // Issue #727 MUST FIX 1: union legacy fields into the snapshot so
    // edits from the not-yet-retargeted NgUserListScreen /
    // NgWordListScreen do not silently disappear while a broadcaster is
    // connected. Both sides go through `enabledNgWordPatterns` /
    // lower-cased dedup so the shape stays consistent.
    // TODO(#727): remove legacy union once PR2 lands.
    final Set<String> mergedUserIds = <String>{
      ...snapshot.ngUserIds,
      ...settings.ngUserIdSet,
    };
    // Use a LinkedHashSet so the patterns remain deterministic for
    // tests while still de-duplicating across the two sources.
    final Set<String> mergedWordSet = <String>{
      ...enabledNgWordPatterns(snapshot.rules),
      ...settings.ngWordList,
    };
    return (ngUserIds: mergedUserIds, ngWords: mergedWordSet.toList());
  }
  // TODO(#727): remove together with PR2 once NG list screens write
  // through BroadcasterNgStore.
  return (ngUserIds: settings.ngUserIdSet, ngWords: settings.ngWordList);
}

class SelectScreen extends StatefulWidget {
  const SelectScreen({
    required this.connectionSupervisor,
    this.timelineStore,
    this.statisticsStore,
    this.settingsStore,
    this.initialSettings = AppSettings.defaults,
    this.onPrepareConnection,
    this.userSessionStore,
    this.programTitleNotifier,
    this.userNameResolution,
    this.broadcasterNameNotifier,
    this.supplierUserIdNotifier,
    this.beginAtNotifier,
    this.vposBaseAtNotifier,
    this.commentLogWriter,
    this.themeModeNotifier,
    this.followProgramRepository,
    this.myProgramRepository,
    this.broadcastControlRepository,
    this.favoriteUserLiveChecker,
    this.userAttributeStore,
    this.broadcasterNgStore,
    this.commentPostController,
    this.timeshiftFetchController,
    this.androidTtsAvailability,
    this.broadcasterEmbedResolver,
    this.playRemainingAfterEndedSink,
    this.onSpeechQueueDrained,
    super.key,
  });

  final ConnectionSupervisor connectionSupervisor;
  final TimelineStore? timelineStore;
  final StatisticsStore? statisticsStore;
  final SettingsStore? settingsStore;
  final AppSettings initialSettings;
  final UserSessionStore? userSessionStore;
  final CommentLogWriter? commentLogWriter;
  final Future<void> Function(String lv, AppSettings settings)?
  onPrepareConnection;
  final ValueNotifier<String?>? programTitleNotifier;
  final UserNameResolution? userNameResolution;
  final ValueNotifier<String?>? broadcasterNameNotifier;
  final ValueNotifier<String?>? supplierUserIdNotifier;
  final ValueNotifier<DateTime?>? beginAtNotifier;

  /// Notifier carrying `programSchedule.vposBaseTime` (Issue #465). When
  /// present this is the authoritative reference for computing comment
  /// `vpos`; when absent or null the existing [beginAtNotifier] fallback
  /// preserves the pre-Issue-#465 behaviour.
  final ValueNotifier<DateTime?>? vposBaseAtNotifier;
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final FollowProgramRepository? followProgramRepository;
  final MyProgramRepository? myProgramRepository;
  final BroadcastControlRepository? broadcastControlRepository;
  final FavoriteUserLiveChecker? favoriteUserLiveChecker;
  final UserAttributeStore? userAttributeStore;

  /// Issue #727: per-broadcaster NG store. When null, the screen falls back
  /// to the legacy global NG fields on [AppSettings] so existing tests and
  /// embedding scenarios that do not wire a store keep working.
  final BroadcasterNgStore? broadcasterNgStore;
  final CommentPostController? commentPostController;
  final TimeshiftFetchController? timeshiftFetchController;

  /// Issue #694: optional cross-screen Android TTS availability notifier.
  /// When provided, the comment screen's AppBar status icon and the TTS
  /// settings screen share the same view of the latest check result so
  /// failures detected in one place propagate to the other.
  final SpeechAvailabilityNotifier? androidTtsAvailability;

  /// Resolves the broadcaster's numeric user ID from the public watch HTML
  /// when LV-direct-input is used (Issue #681 Phase 2). Optional: callers
  /// that do not provide one fall back to the legacy accumulate-and-flush
  /// behaviour driven by `programinfo.supplierUserId`.
  final BroadcasterEmbedResolver? broadcasterEmbedResolver;

  /// Issue #739: optional sink kept in sync with
  /// [AppSettings.playRemainingAfterEnded] whenever the local settings
  /// notifier changes. The owner (e.g. main) reads this value from the
  /// foreground service controller at the moment of `ConnectionStatus.ended`.
  ///
  /// Optional: when `null`, the controller falls back to the default value
  /// passed at construction time and live setting changes are not
  /// reflected. Provided to avoid forcing every test harness to wire up
  /// the notifier.
  final ValueNotifier<bool>? playRemainingAfterEndedSink;

  /// Issue #739: forwarded to [CommentSpeechConfig.onSpeechQueueDrained].
  /// Called when the comment screen's speech grace ends so the parallel FGS
  /// grace can terminate early. Optional — null in test harnesses.
  final VoidCallback? onSpeechQueueDrained;

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _controller;
  late final ValueNotifier<AppSettings> _settingsNotifier;
  late ConnectionStatus _previousStatus;
  ConnectionMethod? _connectionMethod;
  String? _lastConnectedLv;
  String? _followBroadcasterName;
  String? _followBroadcasterIconUrl;
  DateTime? _followBeginAt;
  final ValueNotifier<bool?> _loginStateNotifier = ValueNotifier<bool?>(null);
  List<FollowProgram> _followPrograms = const <FollowProgram>[];
  FollowProgram? _myProgram;
  Timer? _followRefreshTimer;
  late FavoriteUserLiveChecker _favoriteUserLiveChecker;
  bool _ownsFavoriteUserLiveChecker = false;
  Map<String, FollowProgram> _favoriteOnAirMap =
      const <String, FollowProgram>{};
  Timer? _favoriteRefreshTimer;
  final ValueNotifier<
    ({Map<String, int> colors, Map<String, String> nicknames})
  >
  _userAttrNotifier =
      ValueNotifier<({Map<String, int> colors, Map<String, String> nicknames})>(
        (colors: const <String, int>{}, nicknames: const <String, String>{}),
      );
  String? _currentBroadcasterId;

  /// Issue #727: per-broadcaster NG snapshot used to build
  /// [ContentFilterConfig]. Mirrors the [_userAttrNotifier] pattern so the
  /// existing ListenableBuilder rebuild flow drives filter updates.
  ///
  /// The `broadcasterId` tag travels with the snapshot itself so a stale
  /// async load that completes after the user has reconnected to a
  /// different broadcaster can be detected by comparing the tag against
  /// [_currentBroadcasterId] — there is no longer a separate "loaded for"
  /// field that could drift out of sync with the snapshot value.
  ///
  /// Initial value is empty (broadcasterId == null); a real snapshot is
  /// populated by `_loadBroadcasterNgState`. When
  /// [SelectScreen.broadcasterNgStore] is null the notifier stays empty
  /// and the legacy global fields on `AppSettings` provide the filter
  /// input via [_resolveContentFilter].
  final ValueNotifier<BroadcasterNgSnapshot> _broadcasterNgNotifier =
      ValueNotifier<BroadcasterNgSnapshot>(_emptyBroadcasterNgSnapshot);

  /// Issue #727 SHOULD FIX 2: monotonic generation counter for the
  /// optimistic NG-toggle rollback guard. Each call to [_toggleNgUser]
  /// increments this counter and captures the new value; the deferred
  /// rollback only fires if the counter has not advanced in the meantime
  /// (i.e. no later toggle has superseded this optimistic update).
  ///
  /// Replaces the previous `identical(_broadcasterNgNotifier.value, next)`
  /// check, which relied on Dart record identity stability — not a
  /// guaranteed property of records.
  int _toggleNgGeneration = 0;
  final MethodChannelCommentSpeech _speechPlatform =
      MethodChannelCommentSpeech();
  int _broadcastEndedNotificationSequence = 0;
  // Per-engine pre-mute volumes. Either being non-null means "muted".
  // Stored separately so that switching engines while muted does not lose
  // the other engine's pre-mute value (Issue #697).
  double? _preMuteVolume;
  double? _preMuteAndroidTtsVolume;

  static const Duration _followRefreshInterval = Duration(seconds: 60);
  static const Duration _favoriteRefreshIntervalForeground = Duration(
    seconds: 15,
  );
  static const Duration _favoriteRefreshIntervalBackground = Duration(
    seconds: 120,
  );
  bool _isInForeground = true;
  // True while CommentScreen is somewhere on top of SelectScreen in the
  // navigation stack — including any further screens pushed from
  // CommentScreen (TtsSettingsScreen, CommentDisplaySettingsScreen,
  // etc.). The favorite-user list is not visible during this time, so we
  // throttle the live-status polling cadence to the longer background
  // interval to reduce traffic and server load. If more screens ever
  // need the same treatment, consider migrating to a RouteAware /
  // RouteObserver based mechanism instead of adding more flags.
  bool _isCommentScreenActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setFavoriteUserLiveChecker(widget.favoriteUserLiveChecker);
    _controller = TextEditingController();
    _settingsNotifier = ValueNotifier<AppSettings>(widget.initialSettings);
    // Issue #739: keep the optional grace-toggle sink in sync with the
    // local settings notifier so that the foreground service controller
    // reads the latest value from the moment the user toggles the
    // setting, without us needing to re-create that controller.
    _settingsNotifier.addListener(_syncPlayRemainingAfterEndedSink);
    _syncPlayRemainingAfterEndedSink();
    _previousStatus = widget.connectionSupervisor.status;
    widget.connectionSupervisor.addListener(_onSupervisorChanged);
    widget.supplierUserIdNotifier?.addListener(_onSupplierUserIdChanged);
    // If the supplier user ID is already known (e.g. widget rebuilt while
    // connected), load user attributes immediately so that
    // _currentBroadcasterId is set before the user can open settings.
    final String? initialSupplierId = widget.supplierUserIdNotifier?.value;
    if (initialSupplierId != null) {
      unawaited(_loadUserAttributes(initialSupplierId));
    }
    if (widget.settingsStore != null) {
      unawaited(_reloadSettingsFromStore());
    }
    unawaited(_refreshLoginState());
    unawaited(_fetchAllPrograms());
    unawaited(_fetchFavoriteUserStatusAndSchedule());
    _requestFavoriteUserNameResolution();
  }

  @override
  void didUpdateWidget(covariant SelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionSupervisor != widget.connectionSupervisor) {
      oldWidget.connectionSupervisor.removeListener(_onSupervisorChanged);
      widget.connectionSupervisor.addListener(_onSupervisorChanged);
      _previousStatus = widget.connectionSupervisor.status;
    }

    if (oldWidget.supplierUserIdNotifier != widget.supplierUserIdNotifier) {
      oldWidget.supplierUserIdNotifier?.removeListener(
        _onSupplierUserIdChanged,
      );
      widget.supplierUserIdNotifier?.addListener(_onSupplierUserIdChanged);
    }

    if (oldWidget.favoriteUserLiveChecker != widget.favoriteUserLiveChecker) {
      _setFavoriteUserLiveChecker(widget.favoriteUserLiveChecker);
    }

    if (oldWidget.initialSettings != widget.initialSettings &&
        _settingsNotifier.value == oldWidget.initialSettings) {
      _settingsNotifier.value = widget.initialSettings;
    }

    if (oldWidget.settingsStore != widget.settingsStore &&
        widget.settingsStore != null) {
      unawaited(_reloadSettingsFromStore());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _followRefreshTimer?.cancel();
    _favoriteRefreshTimer?.cancel();
    if (_ownsFavoriteUserLiveChecker) {
      _favoriteUserLiveChecker.dispose();
    }
    widget.connectionSupervisor.removeListener(_onSupervisorChanged);
    widget.supplierUserIdNotifier?.removeListener(_onSupplierUserIdChanged);
    // Flush pending user attribute writes as a defensive measure in case
    // the widget is disposed without going through the lifecycle
    // (inactive/paused/detached) handler — e.g. during tests or future
    // refactors.  Fire-and-forget is acceptable here because the widget
    // is on its way out and we cannot await in dispose().
    unawaited(_flushPendingUserAttributeWrites());
    _loginStateNotifier.dispose();
    _userAttrNotifier.dispose();
    _broadcasterNgNotifier.dispose();
    _settingsNotifier.removeListener(_syncPlayRemainingAfterEndedSink);
    _settingsNotifier.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool wasForeground = _isInForeground;
    _isInForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingUserAttributeWrites());
    }
    if (!wasForeground && _isInForeground) {
      if (_isCommentScreenActive) {
        // Comment screen is the visible surface; the favorite list is not
        // shown, so skip the immediate fetch and just keep the throttled
        // cadence.
        _scheduleFavoriteRefresh();
      } else {
        // Returning to foreground: invalidate cache and trigger an immediate
        // check so the user sees up-to-date status right away.
        _refreshFavoritesNowAndReschedule();
      }
    } else if (wasForeground && !_isInForeground) {
      // Moving to background: reschedule with the longer interval.
      _scheduleFavoriteRefresh();
    }
  }

  void _setFavoriteUserLiveChecker(FavoriteUserLiveChecker? checker) {
    if (_ownsFavoriteUserLiveChecker) {
      _favoriteUserLiveChecker.dispose();
    }
    _ownsFavoriteUserLiveChecker = checker == null;
    _favoriteUserLiveChecker = checker ?? FavoriteUserLiveChecker();
  }

  static const ({Map<String, int> colors, Map<String, String> nicknames})
  _emptyUserAttributes = (
    colors: <String, int>{},
    nicknames: <String, String>{},
  );

  void _clearInMemoryUserAttributes() {
    _userAttrNotifier.value = _emptyUserAttributes;
    // Issue #727: reset the per-broadcaster NG snapshot too so that
    // disconnecting / switching broadcasters does not leak the previous
    // broadcaster's filtered IDs into the next session's filter config.
    // Setting broadcasterId back to null also marks the snapshot as
    // "not yet loaded" for any in-flight `_resolveContentFilter` reader.
    _broadcasterNgNotifier.value = _emptyBroadcasterNgSnapshot;
  }

  Future<void> _flushPendingUserAttributeWrites() async {
    final UserAttributeStore? store = widget.userAttributeStore;
    if (store == null) {
      return;
    }
    try {
      await store.flushPendingWrites();
    } on Object catch (error, stackTrace) {
      appErrorLog(
        name: 'SelectScreen',
        message: 'Failed to flush pending user attribute writes',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _onSupervisorChanged() {
    final ConnectionStatus status = widget.connectionSupervisor.status;
    switch (status) {
      case ConnectionStatus.streamingNdgr:
        _connectionMethod = ConnectionMethod.ndgr;
        break;
      case ConnectionStatus.streamingLegacy:
        _connectionMethod = ConnectionMethod.legacy;
        break;
      case ConnectionStatus.connectingSessionWs:
        if (_isTerminalLike(_previousStatus)) {
          _connectionMethod = null;
        }
        break;
      case ConnectionStatus.idle:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.reconnecting:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        break;
    }

    if (_previousStatus != ConnectionStatus.ended &&
        status == ConnectionStatus.ended) {
      _addBroadcastEndedNotification();
    }

    _previousStatus = status;
    setState(() {});
  }

  void _addBroadcastEndedNotification() {
    final TimelineStore? store = widget.timelineStore;
    if (store == null) {
      return;
    }

    final DateTime now = DateTime.now();
    store.add(
      AppMessage(
        id: buildBroadcastEndedNotificationId(
          epochMilliseconds: now.millisecondsSinceEpoch,
          sequence: _broadcastEndedNotificationSequence++,
        ),
        timestamp: now,
        content: '放送が終了しました',
        type: AppMessageType.notification,
      ),
    );
  }

  bool get _isConnectionInProgress =>
      !widget.connectionSupervisor.canStartConnection;

  void _onSubmit(String _) {
    _followBroadcasterName = null;
    _followBroadcasterIconUrl = null;
    _followBeginAt = null;
    unawaited(_connect(connectSource: 'submit'));
  }

  Future<void> _connect({
    required String connectSource,
    String? preferredBroadcasterId,
  }) async {
    final String rawInput = _controller.text;
    if (rawInput.trim().isEmpty) {
      _debugLogLazy(
        () => '[SelectScreen] connect skipped(source=$connectSource): empty',
      );
      return;
    }

    if (!widget.connectionSupervisor.canStartConnection) {
      _debugLogLazy(
        () =>
            '[SelectScreen] connect skipped(source=$connectSource): status=${widget.connectionSupervisor.status.code}',
      );
      if (mounted) {
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('現在接続中です。停止してから再試行してください')),
          );
      }
      return;
    }

    FocusScope.of(context).unfocus();

    final String? lv = LvParser.extract(rawInput);
    if (lv == null) {
      _debugLogLazy(
        () =>
            '[SelectScreen] connect skipped(source=$connectSource): lv parse failed from "$rawInput"',
      );
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('放送IDが見つかりません')));
      return;
    }

    final AppSettings settings = _settingsNotifier.value;
    if (_lastConnectedLv != null && _lastConnectedLv != lv) {
      widget.timelineStore?.clear();
      _clearInMemoryUserAttributes();
    }
    widget.timelineStore?.setCapacity(
      settings.pastCommentFetchCount.displayCapacity,
    );
    await widget.onPrepareConnection?.call(lv, settings);
    _currentBroadcasterId = null;
    // Pre-bind supplier ID if already known (Issue #681 Phase 1). When only
    // the lv is known we do NOT load here — loading under `lv` creates an
    // orphan file and pollutes the merge. _onSupplierUserIdChanged will
    // flush accumulated in-memory changes to the correct file once
    // resolved.
    if (preferredBroadcasterId != null) {
      widget.supplierUserIdNotifier?.value = preferredBroadcasterId;
      unawaited(_loadUserAttributes(preferredBroadcasterId));
    } else {
      // Issue #681 Phase 2: LV-direct-input has no follow-list metadata, so
      // attempt to resolve the broadcaster's numeric user ID from the
      // public watch-page embedded data in parallel with the WebSocket
      // handshake. This gives user broadcasts (where programinfo's
      // supplierUserId is sometimes missing) a chance to bind to the
      // correct file before _onSupplierUserIdChanged would otherwise need
      // to migrate from the lv-keyed orphan path.
      unawaited(_tryResolveBroadcasterFromEmbed(lv));
    }

    final bool started = widget.connectionSupervisor.startConnection();
    _debugLogLazy(
      () =>
          '[SelectScreen] startConnection(source=$connectSource, lv=$lv) => $started',
    );

    if (!started || !mounted) {
      if (!started && mounted) {
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('接続状態が変化したため再試行してください')));
      }
      return;
    }

    _lastConnectedLv = lv;

    _isCommentScreenActive = true;
    _scheduleFavoriteRefresh();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext routeContext) =>
              _buildCommentScreen(routeContext, lv),
        ),
      );
    } finally {
      _isCommentScreenActive = false;
    }

    if (mounted) {
      unawaited(_fetchAllPrograms());
      // Returning to the connection list: invalidate cache and trigger an
      // immediate favorite-status check so any state changes during the
      // throttled window become visible right away. Then resume the
      // foreground cadence.
      _refreshFavoritesNowAndReschedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSettingsAccess = widget.settingsStore != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('comerune'),
        actions: <Widget>[
          if (hasSettingsAccess)
            IconButton(
              key: const Key('select_screen_settings_button'),
              icon: const Icon(Icons.settings),
              tooltip: '設定',
              onPressed: () => _openSettings(context, widget.userSessionStore),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (hasSettingsAccess)
            ValueListenableBuilder<bool?>(
              valueListenable: _loginStateNotifier,
              builder: (BuildContext context, bool? isLoggedIn, Widget? _) {
                return _LoginStatusBanner(
                  isLoggedIn: isLoggedIn,
                  themeMode: _settingsNotifier.value.themeMode,
                  onTapLogin: () =>
                      _openSettings(context, widget.userSessionStore),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  key: const Key('select_screen_input'),
                  controller: _controller,
                  enabled: !_isConnectionInProgress,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _onSubmit,
                  decoration: const InputDecoration(hintText: 'lv番号またはURLを入力'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder:
                        (
                          BuildContext context,
                          TextEditingValue value,
                          Widget? _,
                        ) {
                          final bool canConnect =
                              value.text.trim().isNotEmpty &&
                              widget.connectionSupervisor.canStartConnection;
                          return ElevatedButton(
                            key: const Key('select_screen_connect_button'),
                            onPressed: canConnect
                                ? () {
                                    _followBroadcasterName = null;
                                    _followBroadcasterIconUrl = null;
                                    _followBeginAt = null;
                                    unawaited(
                                      _connect(connectSource: 'manual-button'),
                                    );
                                  }
                                : null,
                            child: const Text('接続開始'),
                          );
                        },
                  ),
                ),
              ],
            ),
          ),
          if (_myProgram != null)
            _MyBroadcastSection(
              program: _myProgram!,
              enabled: !_isConnectionInProgress,
              onTap: () => _connectToProgram(_myProgram!),
            ),
          Expanded(
            child: _CombinedProgramList(
              followPrograms: _followPrograms,
              favoriteOnAirMap: _favoriteOnAirMap,
              enabled: !_isConnectionInProgress,
              onFollowTap: _connectToProgram,
              onFavoriteTap: _connectToFavoriteProgram,
              onRefresh: _refreshAll,
              onFavoriteRefresh: _fetchFavoriteUserStatus,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentScreen(BuildContext routeContext, String lv) {
    final List<Listenable> listenables = <Listenable>[
      widget.connectionSupervisor,
      _settingsNotifier,
      _userAttrNotifier,
      _broadcasterNgNotifier,
      if (widget.timelineStore != null) widget.timelineStore!,
      if (widget.statisticsStore != null) widget.statisticsStore!,
      if (widget.programTitleNotifier != null) widget.programTitleNotifier!,
      if (widget.userNameResolution?.listenable != null)
        widget.userNameResolution!.listenable,
      if (widget.broadcasterNameNotifier != null)
        widget.broadcasterNameNotifier!,
      if (widget.supplierUserIdNotifier != null) widget.supplierUserIdNotifier!,
      if (widget.beginAtNotifier != null) widget.beginAtNotifier!,
      if (widget.vposBaseAtNotifier != null) widget.vposBaseAtNotifier!,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (BuildContext context, Widget? _) {
        final List<AppMessage> messages =
            widget.timelineStore?.messages ?? const <AppMessage>[];
        final bool nameResolutionEnabled =
            _settingsNotifier.value.resolveUserName;
        final String? supplierUserId = widget.supplierUserIdNotifier?.value;
        // Resolve broadcaster name from cache regardless of the per-comment
        // name resolution setting, so the broadcaster name is always
        // displayed when available (seeded by programinfo API via
        // seedCache).
        final String? cachedBroadcasterName = supplierUserId != null
            ? widget.userNameResolution?.resolve(supplierUserId)
            : null;
        final String? broadcasterName =
            cachedBroadcasterName ??
            widget.broadcasterNameNotifier?.value ??
            _followBroadcasterName;
        final String? broadcasterIconUrl =
            _followBroadcasterIconUrl ??
            _buildIconUrlFromUserId(supplierUserId);
        final DateTime? beginAt = _resolveCommentBeginAt();

        return CommentScreen(
          programInfo: CommentProgramInfo(
            lv: lv,
            programTitle: widget.programTitleNotifier?.value,
            broadcasterName: broadcasterName,
            broadcasterUserId: supplierUserId,
            broadcasterIconUrl: broadcasterIconUrl,
            beginAt: beginAt,
            // vposBaseAt is sourced only from programinfo (there is no
            // follow-list equivalent), so unlike beginAt it does not need
            // a dual-source _resolveCommentBeginAt-style helper.
            vposBaseAt: widget.vposBaseAtNotifier?.value,
            connectionMethod: _connectionMethod,
          ),
          connectionSupervisor: widget.connectionSupervisor,
          messages: messages,
          callbacks: CommentCallbacks(
            onStopAllConnections: _stopAllConnections,
            onReconnectSameLv: _reconnectSameLv,
            onDifferentLvConnected: _onDifferentLvConnected,
            onOpenSettings: widget.settingsStore == null
                ? null
                : () => _openSettings(routeContext, widget.userSessionStore),
            onToggleNgUser: _toggleNgUser,
            onUserColorChanged: widget.userAttributeStore != null
                ? _onUserColorChanged
                : null,
            onUserColorRemoved: widget.userAttributeStore != null
                ? _onUserColorRemoved
                : null,
            onNicknameChanged: widget.userAttributeStore != null
                ? _onNicknameChanged
                : null,
            onNicknameRemoved: widget.userAttributeStore != null
                ? _onNicknameRemoved
                : null,
            onDictionaryRulesChanged: _onDictionaryRulesChanged,
            onSpeechMuteToggled: widget.settingsStore != null
                ? _toggleSpeechMute
                : null,
            onSortOrderChanged: _onSortOrderChanged,
          ),
          debugMode: _settingsNotifier.value.debugMode,
          showUserName: _settingsNotifier.value.showUserName,
          commentFontSize: _settingsNotifier.value.commentFontSize,
          userNameResolution: nameResolutionEnabled
              ? widget.userNameResolution
              : null,
          commentTwoLineEnabled: _settingsNotifier.value.commentTwoLineEnabled,
          commentTwoLineMetaFontPercent:
              _settingsNotifier.value.commentTwoLineMetaFontPercent,
          commentZebraStripingEnabled:
              _settingsNotifier.value.commentZebraStripingEnabled,
          commentSortOrder: _settingsNotifier.value.commentSortOrder,
          showCommentNo: _settingsNotifier.value.showCommentNo,
          userColorMap: _userAttrNotifier.value.colors,
          onUserColorChanged: widget.userAttributeStore != null
              ? _onUserColorChanged
              : null,
          onUserColorRemoved: widget.userAttributeStore != null
              ? _onUserColorRemoved
              : null,
          userNicknameMap: _userAttrNotifier.value.nicknames,
          onNicknameChanged: widget.userAttributeStore != null
              ? _onNicknameChanged
              : null,
          onNicknameRemoved: widget.userAttributeStore != null
              ? _onNicknameRemoved
              : null,
          autoNicknameRegistration:
              _settingsNotifier.value.autoNicknameRegistration,
          themeMode: _settingsNotifier.value.themeMode,
          statistics: CommentStatisticsConfig(
            enabled: _settingsNotifier.value.statisticsEnabled,
            viewerCommentEnabled:
                _settingsNotifier.value.statisticsViewerCommentEnabled,
            activeUserEnabled:
                _settingsNotifier.value.statisticsActiveUserEnabled,
            highlightPickupEnabled:
                _settingsNotifier.value.highlightPickupEnabled,
            viewerCount: widget.statisticsStore?.viewerCount,
            totalCommentCount: widget.statisticsStore?.totalCommentCount ?? 0,
            activeUserCount: widget.statisticsStore?.activeUserCount ?? 0,
          ),
          // Issue #727: route NG filter input through the per-broadcaster
          // store when one is wired and a snapshot is loaded for the
          // active broadcaster. Falls back to the legacy global fields
          // otherwise so unconnected users / minimally-wired hosts still
          // get the user's pre-migration NG configuration.
          contentFilter: _buildContentFilterConfig(),
          messageTypeVisibility: MessageTypeVisibilityConfig(
            showOperatorComment: _settingsNotifier.value.showOperatorComment,
            showSystemMessage: _settingsNotifier.value.showSystemMessage,
            showEmotion: _settingsNotifier.value.showEmotion,
            showGiftComment: _settingsNotifier.value.showGiftComment,
            showNicoadComment: _settingsNotifier.value.showNicoadComment,
          ),
          logConfig: CommentLogConfig(
            commentLogWriter: widget.commentLogWriter,
            autoSaveCommentLog: _settingsNotifier.value.autoSaveCommentLog,
            autoSaveCommentLogPath:
                _settingsNotifier.value.autoSaveCommentLogPath,
          ),
          speechConfig: CommentSpeechConfig(
            speechPlatform: _speechPlatform,
            speechSettings: _buildSpeechSettings(),
            readUserName: _settingsNotifier.value.readUserName,
            readGiftComment: _settingsNotifier.value.readGiftComment,
            readNicoadComment: _settingsNotifier.value.readNicoadComment,
            settingsStore: widget.settingsStore,
            isSpeechMuted: _isSpeechMuted,
            androidTtsAvailability: widget.androidTtsAvailability,
            playRemainingAfterEnded:
                _settingsNotifier.value.playRemainingAfterEnded,
            onSpeechQueueDrained: widget.onSpeechQueueDrained,
            // Issue #758: bg poll timer reads the latest snapshot directly
            // from the store (widget.messages stops updating in bg because
            // frame scheduling is paused).
            timelineStore: widget.timelineStore,
          ),
          commentPostController: widget.commentPostController,
          userSessionLoader: widget.userSessionStore?.load,
          timeshiftFetchController: widget.timeshiftFetchController,
          // Plumbed through so the comment screen's AppBar overflow
          // "配信を終了" entry can call the same niconico segment API used
          // by the slide-to-end control on the program list (#750). The
          // comment screen gates the menu entry on `_isBroadcaster`, so
          // viewers never see a wired-but-non-applicable repository.
          broadcastControlRepository: widget.broadcastControlRepository,
        );
      },
    );
  }

  SpeechSettings _buildSpeechSettings() {
    final AppSettings s = _settingsNotifier.value;
    _debugLogLazy(
      () =>
          '[SelectScreen] buildSpeechSettings: engine=${s.speechEngine}, speaker=${s.voicevoxSpeaker}, speed=${s.voicevoxSpeed}',
    );
    return s.toSpeechSettings();
  }

  Future<void> _stopAllConnections() async {
    widget.connectionSupervisor.stopByUser();
  }

  Future<void> _reconnectSameLv() async {
    final String? lv = _lastConnectedLv;
    if (lv == null) {
      return;
    }

    final AppSettings settings = _settingsNotifier.value;
    widget.timelineStore?.setCapacity(
      settings.pastCommentFetchCount.displayCapacity,
    );
    await widget.onPrepareConnection?.call(lv, settings);
    // Same broadcaster — do NOT clear `_userAttrNotifier`. The in-memory
    // colors/nicknames must survive the reconnect so they remain visible.
    // Reset `_currentBroadcasterId` to force a reload pass once the supplier
    // ID is re-observed, but use the already-known supplier ID (not `lv`)
    // as the load key so we never create an orphan `lv*.json` file.
    final String? knownSupplierId = widget.supplierUserIdNotifier?.value;
    _currentBroadcasterId = null;
    if (knownSupplierId != null) {
      unawaited(_loadUserAttributes(knownSupplierId));
    }

    final bool retried = widget.connectionSupervisor
        .retryConnectionFromTerminal();
    if (!retried && widget.connectionSupervisor.canStartConnection) {
      widget.connectionSupervisor.startConnection();
    }
  }

  Future<void> _onDifferentLvConnected(String previousLv, String nextLv) {
    if (previousLv != nextLv) {
      widget.timelineStore?.clear();
      _currentBroadcasterId = null;
      _clearInMemoryUserAttributes();
    }
    _lastConnectedLv = nextLv;
    return Future<void>.value();
  }

  /// Best-effort attempt to bind `supplierUserIdNotifier` from the niconico
  /// watch-page embedded data when only an `lv` is known (Issue #681
  /// Phase 2). Never throws; any failure leaves the legacy accumulate-and-
  /// flush path untouched.
  Future<void> _tryResolveBroadcasterFromEmbed(String lv) async {
    final BroadcasterEmbedResolver? resolver = widget.broadcasterEmbedResolver;
    if (resolver == null) {
      return;
    }
    final BroadcasterEmbedInfo? info = await resolver.resolve(lv);
    if (!mounted || info == null) {
      return;
    }
    // Reject the result when the user has switched to a different lv in
    // the meantime — applying it would mis-key user attributes for the
    // newly-connected broadcaster.
    if (_lastConnectedLv != lv) {
      return;
    }
    final ValueNotifier<String?>? notifier = widget.supplierUserIdNotifier;
    if (notifier == null) {
      return;
    }
    // If a real supplier ID has already arrived (e.g. programinfo resolved
    // first), prefer that source of truth. Setting the same value here
    // would be a harmless no-op but checking explicitly also avoids the
    // ambiguous case where embed and programinfo somehow disagree.
    if (notifier.value != null) {
      // _onSupplierUserIdChanged will (or has already) loaded attributes
      // under the existing supplier ID. Still seed the broadcaster name
      // cache so the comment header can avoid a nickname-API round-trip.
      _seedBroadcasterName(info);
      return;
    }
    notifier.value = info.userId;
    _seedBroadcasterName(info);
  }

  void _seedBroadcasterName(BroadcasterEmbedInfo info) {
    final String? name = info.name;
    if (name == null || name.isEmpty) {
      return;
    }
    widget.userNameResolution?.seedCache?.call(info.userId, name);
  }

  void _onSupplierUserIdChanged() {
    final String? supplierUserId = widget.supplierUserIdNotifier?.value;
    _debugLogLazy(
      () =>
          '[SelectScreen] _onSupplierUserIdChanged: '
          'supplierUserId=$supplierUserId, '
          '_currentBroadcasterId=$_currentBroadcasterId',
    );
    if (supplierUserId != null && supplierUserId != _currentBroadcasterId) {
      _debugLogLazy(
        () =>
            '[SelectScreen] _onSupplierUserIdChanged: '
            'calling _loadUserAttributes($supplierUserId)',
      );
      unawaited(_loadUserAttributes(supplierUserId));
    }
  }

  void _requestFavoriteUserNameResolution() {
    final void Function(String)? request =
        widget.userNameResolution?.requestResolve;
    if (request == null) {
      return;
    }
    for (final String userId in _settingsNotifier.value.favoriteUserIdSet) {
      request(userId);
    }
  }

  /// Loads user attributes from persistent storage and updates the notifier.
  ///
  /// When [mergeInMemory] is true (the default), the loaded data is merged
  /// with the current in-memory state so that unsaved changes accumulated
  /// before the broadcaster ID was known are preserved.  Pass `false` when
  /// the caller knows the disk data is authoritative (e.g. after returning
  /// from the settings screen where the user may have edited nicknames
  /// directly).
  Future<void> _loadUserAttributes(
    String? broadcasterId, {
    bool mergeInMemory = true,
  }) async {
    if (broadcasterId == null ||
        broadcasterId == _currentBroadcasterId ||
        widget.userAttributeStore == null) {
      _debugLogLazy(
        () =>
            '[SelectScreen] _loadUserAttributes: SKIPPED '
            '(broadcasterId=$broadcasterId, '
            '_currentBroadcasterId=$_currentBroadcasterId, '
            'storeNull=${widget.userAttributeStore == null})',
      );
      return;
    }
    _debugLogLazy(
      () =>
          '[SelectScreen] _loadUserAttributes: START '
          '(broadcasterId=$broadcasterId)',
    );
    _currentBroadcasterId = broadcasterId;
    // Issue #727: kick off the per-broadcaster NG load alongside user
    // attributes. Independent future so a slow NG load cannot stall the
    // color/nickname display, and vice versa.
    unawaited(_loadBroadcasterNgState(broadcasterId));
    final UserAttributesSnapshot loaded = await widget.userAttributeStore!
        .loadAttributes(broadcasterId);
    final Map<String, int> diskColors = loaded.colors;
    final Map<String, String> diskNicknames = loaded.nicknames;
    if (!mounted || _currentBroadcasterId != broadcasterId) {
      return;
    }

    if (!mergeInMemory) {
      _userAttrNotifier.value = (colors: diskColors, nicknames: diskNicknames);
      return;
    }

    // Merge disk data with the current in-memory state so that changes
    // accumulated before the broadcaster ID was known (e.g. auto-nickname
    // registration from historical messages) are not lost.  In-memory
    // values take priority because they may contain unsaved edits.
    final ({Map<String, int> colors, Map<String, String> nicknames}) current =
        _userAttrNotifier.value;
    final Map<String, int> mergedColors = <String, int>{
      ...diskColors,
      ...current.colors,
    };
    final Map<String, String> mergedNicknames = <String, String>{
      ...diskNicknames,
      ...current.nicknames,
    };

    _userAttrNotifier.value = (
      colors: mergedColors,
      nicknames: mergedNicknames,
    );

    // Flush in-memory changes that could not be persisted earlier.
    _flushPendingAttributes(broadcasterId, current, diskColors, diskNicknames);
  }

  void _flushPendingAttributes(
    String broadcasterId,
    ({Map<String, int> colors, Map<String, String> nicknames}) inMemorySnapshot,
    Map<String, int> diskColors,
    Map<String, String> diskNicknames,
  ) {
    final UserAttributeStore? store = widget.userAttributeStore;
    if (store == null) {
      return;
    }
    for (final MapEntry<String, int> e in inMemorySnapshot.colors.entries) {
      if (!diskColors.containsKey(e.key) || diskColors[e.key] != e.value) {
        unawaited(
          store.setColor(
            broadcasterId: broadcasterId,
            userId: e.key,
            colorValue: e.value,
          ),
        );
      }
    }
    for (final MapEntry<String, String> e
        in inMemorySnapshot.nicknames.entries) {
      if (!diskNicknames.containsKey(e.key) ||
          diskNicknames[e.key] != e.value) {
        unawaited(
          store.setNickname(
            broadcasterId: broadcasterId,
            userId: e.key,
            nickname: e.value,
          ),
        );
      }
    }
  }

  /// Issue #727: load the per-broadcaster NG snapshot for [broadcasterId]
  /// from [SelectScreen.broadcasterNgStore] and update
  /// [_broadcasterNgNotifier]. No-op when the store is not wired.
  ///
  /// Discards stale results when the user has switched to a different
  /// broadcaster mid-load; this matches the user-attribute load pattern
  /// just above.
  Future<void> _loadBroadcasterNgState(String broadcasterId) async {
    final BroadcasterNgStore? store = widget.broadcasterNgStore;
    if (store == null) {
      return;
    }
    try {
      // Issue #727 review fix: single combined load avoids the duplicate
      // template-seeding round-trip that calling loadNgUserIds + loadNg
      // WordRules back to back would do on first access.
      final ({Set<String> ngUserIds, List<NgWordRule> rules}) snapshot =
          await store.loadBroadcasterNgAttributes(broadcasterId);
      if (!mounted || _currentBroadcasterId != broadcasterId) {
        return;
      }
      _broadcasterNgNotifier.value = (
        broadcasterId: broadcasterId,
        ngUserIds: snapshot.ngUserIds,
        rules: snapshot.rules,
      );
    } on Object catch (error, stackTrace) {
      _errorLog(
        '_loadBroadcasterNgState: failed for $broadcasterId',
        error: error,
      );
      // Defensive fallback: leave the previous snapshot in place rather
      // than wiping it on a transient read failure. The legacy global
      // settings still flow through `_resolveContentFilter` while this
      // runs because the notifier value never goes stale into the build.
      appDebugLogLazy(
        () => '[SelectScreen] _loadBroadcasterNgState stack: $stackTrace',
      );
    }
  }

  /// Issue #727: composes a [ContentFilterConfig] sourced from the
  /// per-broadcaster store when available, or the legacy global settings
  /// otherwise. The non-NG fields always come from [_settingsNotifier]
  /// since they remain global in PR1.
  ContentFilterConfig _buildContentFilterConfig() {
    final ({Set<String> ngUserIds, List<String> ngWords}) ng =
        _resolveContentFilter();
    return ContentFilterConfig(
      ngUserIds: ng.ngUserIds,
      ngWords: ng.ngWords,
      starPrefixHidingEnabled: _settingsNotifier.value.starPrefixHidingEnabled,
      slashPrefixSkipEnabled: _settingsNotifier.value.slashPrefixSkipEnabled,
      emphasizeGiftNicoadComment:
          _settingsNotifier.value.emphasizeGiftNicoadComment,
      userColorMap: _userAttrNotifier.value.colors,
      userNicknameMap: _userAttrNotifier.value.nicknames,
      ngProtectionNotificationEnabled:
          _settingsNotifier.value.ngProtectionNotificationEnabled,
      ngDisplayPreferences: NgDisplayPreferences.fromAppSettings(
        _settingsNotifier.value,
      ),
    );
  }

  /// Issue #727: returns the (ngUserIds, ngWords) pair to feed into the
  /// active [ContentFilterConfig].
  ///
  /// Resolution order:
  ///   1. When a broadcaster is connected and the per-broadcaster store
  ///      has produced a snapshot tagged with that same broadcaster, use
  ///      the snapshot — but **union** the current legacy
  ///      `settings.ngUserIdSet` / `settings.ngWordList` into the result.
  ///   2. Otherwise fall back to the legacy global fields on
  ///      [AppSettings] so unconnected users (and hosts that do not pass
  ///      a [BroadcasterNgStore]) still see their existing NG filter.
  ///
  /// **Why union?** The legacy `NgUserListScreen` / `NgWordListScreen`
  /// management screens still write to `AppSettings.ngUserIds` /
  /// `AppSettings.ngWordRules` in this PR. Without the union, a user
  /// editing NG entries from those screens while connected to a
  /// broadcaster would see no filter effect — a silent regression.
  /// The per-broadcaster path remains the source of truth for writes
  /// (the long-press toggle in `_toggleNgUser` writes only there); the
  /// union is a temporary read-side bridge so legacy edits leak through
  /// until PR2 retargets those screens to write through
  /// [BroadcasterNgStore].
  ///
  /// TODO(#727): remove legacy union once PR2 lands.
  ({Set<String> ngUserIds, List<String> ngWords}) _resolveContentFilter() {
    return computeContentFilterInputs(
      settings: _settingsNotifier.value,
      currentBroadcasterId: _currentBroadcasterId,
      snapshot: _broadcasterNgNotifier.value,
      hasStore: widget.broadcasterNgStore != null,
    );
  }

  void _onUserColorChanged(String userId, int colorValue) {
    final ({Map<String, int> colors, Map<String, String> nicknames}) prev =
        _userAttrNotifier.value;
    _userAttrNotifier.value = (
      colors: Map<String, int>.from(prev.colors)..[userId] = colorValue,
      nicknames: prev.nicknames,
    );
    final String? broadcasterId = _currentBroadcasterId;
    if (broadcasterId == null) {
      _debugLogLazy(
        () =>
            '[SelectScreen] _onUserColorChanged: SAVE SKIPPED '
            '(broadcasterId is null, userId=$userId)',
      );
    }
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(
        widget.userAttributeStore!.setColor(
          broadcasterId: broadcasterId,
          userId: userId,
          colorValue: colorValue,
        ),
      );
    }
  }

  void _onUserColorRemoved(String userId) {
    final ({Map<String, int> colors, Map<String, String> nicknames}) prev =
        _userAttrNotifier.value;
    _userAttrNotifier.value = (
      colors: Map<String, int>.from(prev.colors)..remove(userId),
      nicknames: prev.nicknames,
    );
    final String? broadcasterId = _currentBroadcasterId;
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(
        widget.userAttributeStore!.removeColor(
          broadcasterId: broadcasterId,
          userId: userId,
        ),
      );
    }
  }

  void _onNicknameChanged(String userId, String nickname) {
    final ({Map<String, int> colors, Map<String, String> nicknames}) prev =
        _userAttrNotifier.value;
    _userAttrNotifier.value = (
      colors: prev.colors,
      nicknames: Map<String, String>.from(prev.nicknames)..[userId] = nickname,
    );
    final String? broadcasterId = _currentBroadcasterId;
    if (broadcasterId == null) {
      _debugLogLazy(
        () =>
            '[SelectScreen] _onNicknameChanged: SAVE SKIPPED '
            '(broadcasterId is null, userId=$userId)',
      );
    }
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(
        widget.userAttributeStore!.setNickname(
          broadcasterId: broadcasterId,
          userId: userId,
          nickname: nickname,
        ),
      );
    }
  }

  void _onNicknameRemoved(String userId) {
    final ({Map<String, int> colors, Map<String, String> nicknames}) prev =
        _userAttrNotifier.value;
    _userAttrNotifier.value = (
      colors: prev.colors,
      nicknames: Map<String, String>.from(prev.nicknames)..remove(userId),
    );
    final String? broadcasterId = _currentBroadcasterId;
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(
        widget.userAttributeStore!.removeNickname(
          broadcasterId: broadcasterId,
          userId: userId,
        ),
      );
    }
  }

  void _onDictionaryRulesChanged(AppSettings updated) {
    _settingsNotifier.value = updated;
  }

  bool get _isSpeechMuted =>
      _preMuteVolume != null || _preMuteAndroidTtsVolume != null;

  void _toggleSpeechMute() {
    final SettingsStore? settingsStore = widget.settingsStore;
    if (settingsStore == null) return;

    final SpeechMuteToggleResult result = computeSpeechMuteToggle(
      current: _settingsNotifier.value,
      currentVoicevoxPreMute: _preMuteVolume,
      currentAndroidTtsPreMute: _preMuteAndroidTtsVolume,
    );
    _preMuteVolume = result.voicevoxPreMute;
    _preMuteAndroidTtsVolume = result.androidTtsPreMute;
    _settingsNotifier.value = result.updated;
    // Issue #697 cycle-2-new-1 + round-2 review: aggregate the three
    // SharedPreferences writes into a single error-handling path so a
    // failure of any one is logged centrally via appErrorLog instead of
    // being silently dropped on three separate `unawaited` futures.
    //
    // Note on Future.wait semantics: `Future.wait` defaults to
    // `eagerError: false`, which means writes that have already started
    // before another fails are still allowed to complete in the
    // background. We do NOT promise atomic persistence — any of the
    // three writes may have committed by the time `catchError` runs.
    // The in-memory mute state on this screen is still self-consistent;
    // a partial-write failure is recovered on the next user toggle (which
    // always rewrites all three keys with the freshest values).
    unawaited(
      Future.wait<void>(<Future<void>>[
        settingsStore.save(result.updated),
        settingsStore.savePreMuteVolume(result.voicevoxPreMute),
        settingsStore.savePreMuteAndroidTtsVolume(result.androidTtsPreMute),
      ]).catchError((Object e, StackTrace st) {
        appErrorLog(
          name: 'SelectScreen',
          message: '_toggleSpeechMute: settings persistence FAILED',
          error: e,
          stackTrace: st,
        );
        return <void>[];
      }),
    );
  }

  /// Issue #727: long-press NG toggle writes through the per-broadcaster
  /// NG store when available, scoping the block to the active broadcaster.
  /// Falls back to the legacy global field on [AppSettings] when either
  /// the store or the broadcaster ID is missing — this preserves behavior
  /// for tests and minimally-wired embedders.
  ///
  /// In the per-broadcaster path the [_settingsNotifier] is intentionally
  /// NOT mutated; the legacy global fields are managed by the dedicated
  /// list screens (PR2 will retarget them to the new store).
  void _toggleNgUser(String userId) {
    if (userId.isEmpty) {
      return;
    }
    final BroadcasterNgStore? ngStore = widget.broadcasterNgStore;
    final String? broadcasterId = _currentBroadcasterId;
    if (ngStore != null && broadcasterId != null) {
      final BroadcasterNgSnapshot snapshot = _broadcasterNgNotifier.value;
      final bool isCurrentlyNg = snapshot.ngUserIds.contains(userId);
      final Set<String> nextIds = <String>{...snapshot.ngUserIds};
      if (isCurrentlyNg) {
        nextIds.remove(userId);
      } else {
        nextIds.add(userId);
      }
      // Optimistic in-memory update tagged with the current broadcaster.
      // The optimistic value is captured up front so we can revert it if
      // the store write fails below.
      final BroadcasterNgSnapshot previous = snapshot;
      final BroadcasterNgSnapshot next = (
        broadcasterId: broadcasterId,
        ngUserIds: nextIds,
        rules: snapshot.rules,
      );
      // Issue #727 SHOULD FIX 2: capture the per-toggle generation so the
      // deferred rollback below can detect a later toggle and bail out
      // without clobbering newer state.
      final int gen = ++_toggleNgGeneration;
      _broadcasterNgNotifier.value = next;
      final Future<void> write = isCurrentlyNg
          ? ngStore.removeNgUserId(broadcasterId, userId)
          : ngStore.addNgUserId(broadcasterId, userId);
      // Issue #727 review fix: roll back the optimistic in-memory state
      // on persistence failure so the UI does not drift from the stored
      // truth. Only reverts when the broadcaster is still active and the
      // generation counter has not advanced — otherwise a later edit
      // (toggle, switch broadcaster, disconnect) has superseded this
      // one and rolling back would clobber the newer state.
      unawaited(
        write.onError<Object>((Object error, StackTrace stackTrace) {
          _errorLog(
            '_toggleNgUser: persistence failed; rolling back '
            '(userId=$userId, isCurrentlyNg=$isCurrentlyNg)',
            error: error,
            stackTrace: stackTrace,
          );
          if (!mounted) {
            return;
          }
          if (_currentBroadcasterId != broadcasterId) {
            return;
          }
          // Issue #727 SHOULD FIX 2: replaces the previous
          // `identical(_broadcasterNgNotifier.value, next)` check; Dart
          // records do not guarantee stable identity so the generation
          // counter is the robust signal that no later toggle has
          // superseded this one.
          if (_toggleNgGeneration != gen) {
            return;
          }
          _broadcasterNgNotifier.value = previous;
          // Issue #727 SHOULD FIX 1: surface the failure to the user so
          // they know the toggle did not stick. Reuses the existing
          // `ScaffoldMessenger.of(context)` flow for styling/lifecycle
          // consistency with other snackbars in this file (no GlobalKey
          // is wired). The string is inlined for now; it will move to
          // `AppStrings` once a `SelectScreenStrings` group is added.
          // TODO(#476): centralise this string under AppStrings.
          final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
            context,
          );
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(content: Text('NG ユーザー設定の保存に失敗しました')),
            );
        }),
      );
      return;
    }
    // Fallback: legacy global path. Used when no broadcaster is connected
    // or when the store is not wired (e.g. tests). When PR2 retargets the
    // list screens this branch is the last remaining writer of the
    // legacy fields, but it remains as a safety net.
    // TODO(#727): remove together with PR2 once NG list screens write
    // through BroadcasterNgStore.
    final AppSettings current = _settingsNotifier.value;
    final AppSettings updated = current.isNgUser(userId)
        ? current.removeNgUserId(userId)
        : current.addNgUserId(userId);
    _settingsNotifier.value = updated;
    final SettingsStore? settingsStore = widget.settingsStore;
    if (settingsStore != null) {
      unawaited(settingsStore.save(updated));
    }
  }

  /// Issue #774: コメント画面のソート切替を SharedPreferences に永続化する。
  /// CommentScreen 側で UI 状態が確定した後に呼ばれるため、ここでは
  /// `_settingsNotifier` を更新して再ビルド時に同じ値が再注入されるよう
  /// 揃え、`SettingsStore.save` で次回起動でも復元できるようにする。
  void _onSortOrderChanged(CommentSortOrder next) {
    final AppSettings current = _settingsNotifier.value;
    if (current.commentSortOrder == next) {
      return;
    }
    final AppSettings updated = current.copyWith(commentSortOrder: next);
    _settingsNotifier.value = updated;
    final SettingsStore? settingsStore = widget.settingsStore;
    if (settingsStore != null) {
      unawaited(settingsStore.save(updated));
    }
  }

  Future<void> _openSettings(
    BuildContext context,
    UserSessionStore? userSessionStore,
  ) async {
    final SettingsStore? settingsStore = widget.settingsStore;
    if (settingsStore == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          settingsStore: settingsStore,
          userSessionStore: userSessionStore,
          themeModeNotifier: widget.themeModeNotifier,
          userAttributeStore: widget.userAttributeStore,
          broadcasterIdNotifier: widget.supplierUserIdNotifier,
          userNameResolution: widget.userNameResolution,
          speechPlatform: MethodChannelCommentSpeech(),
          androidTtsAvailability: widget.androidTtsAvailability,
        ),
      ),
    );

    await _reloadSettingsFromStore();
    await _refreshLoginState();
    await _refreshAll();
    // Reload user attributes in case nicknames were edited in settings.
    // Use the notifier value as fallback in the same way as the broadcasterId
    // passed to SettingsScreen above.
    final String? activeBroadcasterId =
        _currentBroadcasterId ?? widget.supplierUserIdNotifier?.value;
    if (activeBroadcasterId != null) {
      _currentBroadcasterId = null;
      await _loadUserAttributes(activeBroadcasterId, mergeInMemory: false);
    }
  }

  Future<void> _refreshLoginState() async {
    final UserSessionStore? store = widget.userSessionStore;
    if (store == null) {
      _loginStateNotifier.value = null;
      return;
    }

    String session;
    try {
      session = await store.load();
    } on Exception {
      session = '';
    }
    if (!mounted) {
      return;
    }
    _loginStateNotifier.value = session.isNotEmpty;
  }

  Future<String> _loadUserSession() async {
    final UserSessionStore? sessionStore = widget.userSessionStore;
    if (sessionStore == null) {
      return '';
    }
    try {
      return await sessionStore.load();
    } on Exception {
      return '';
    }
  }

  /// Refreshes all data: follow programs, own broadcast, and favorite user
  /// broadcast status. Called by pull-to-refresh and after the settings
  /// screen returns.
  Future<void> _refreshAll() async {
    // Both call sites — pull-to-refresh and post-settings — imply "give
    // me fresh data". Bypass the favorite checker's TTL cache so the
    // user sees the up-to-date result rather than a value cached from
    // a recent throttled tick.
    _favoriteUserLiveChecker.invalidateCache();
    await Future.wait<void>(<Future<void>>[
      _fetchAllPrograms(),
      _fetchFavoriteUserStatus(),
    ]);
    if (mounted) {
      _scheduleFavoriteRefresh();
    }
  }

  /// Fetches the user's own broadcast and follow programs, then schedules
  /// the next refresh after [_followRefreshInterval].
  Future<void> _fetchAllPrograms() async {
    final String userSession = await _loadUserSession();
    if (!mounted) {
      return;
    }

    // Run both fetches concurrently with the same session token.
    // Each fetch handles its own errors internally, but we wrap
    // Future.wait in a try-catch as a safety net so that an unexpected
    // error in one fetch never prevents the refresh timer from being
    // rescheduled (which would silently stop all future updates).
    try {
      await Future.wait<void>(<Future<void>>[
        _fetchMyProgram(userSession),
        _fetchFollowPrograms(userSession),
      ]);
    } on Object catch (e) {
      _errorLog('Unexpected error during program fetch', error: e);
    }

    if (!mounted) {
      return;
    }

    _followRefreshTimer?.cancel();
    _followRefreshTimer = Timer(
      _followRefreshInterval,
      () => unawaited(_fetchAllPrograms()),
    );
  }

  /// Fetches favorite user status once, then starts the adaptive refresh
  /// cycle. Called from [initState].
  Future<void> _fetchFavoriteUserStatusAndSchedule() async {
    await _fetchFavoriteUserStatus();
    if (mounted) {
      _scheduleFavoriteRefresh();
    }
  }

  /// The cadence at which the favorite-user list should be polled given
  /// the current app state. The foreground interval is only used when the
  /// list is actually visible — i.e. the app is in the foreground AND
  /// CommentScreen is not on top of the connection list.
  Duration get _favoriteRefreshInterval {
    final bool useForegroundCadence =
        _isInForeground && !_isCommentScreenActive;
    return useForegroundCadence
        ? _favoriteRefreshIntervalForeground
        : _favoriteRefreshIntervalBackground;
  }

  /// Schedules the next favorite-user broadcast check using
  /// [_favoriteRefreshInterval]. If the user has zero favorites the
  /// timer is cancelled and not rescheduled — there is nothing to poll
  /// for. Favorites can currently only change via the settings screen,
  /// so the schedule is reactivated through [_refreshAll] (called on
  /// settings exit) once a favorite has been added. If a future feature
  /// adds another path that mutates `favoriteUserIdSet`, that path
  /// MUST call [_scheduleFavoriteRefresh] (or [_refreshAll]) so the
  /// timer comes back to life.
  void _scheduleFavoriteRefresh() {
    _favoriteRefreshTimer?.cancel();
    if (_settingsNotifier.value.favoriteUserIdSet.isEmpty) {
      return;
    }
    _favoriteRefreshTimer = Timer(_favoriteRefreshInterval, () async {
      await _fetchFavoriteUserStatus();
      if (mounted) {
        _scheduleFavoriteRefresh();
      }
    });
  }

  /// Invalidates the favorite-user cache, fires an immediate refresh and
  /// resumes the polling cycle. Used whenever the favorite list becomes
  /// visible again after a period in which we may have been showing
  /// stale data — namely returning from the comment screen and resuming
  /// the app from background.
  void _refreshFavoritesNowAndReschedule() {
    _favoriteUserLiveChecker.invalidateCache();
    unawaited(_fetchFavoriteUserStatus());
    _scheduleFavoriteRefresh();
  }

  Future<void> _fetchMyProgram(String userSession) async {
    final MyProgramRepository? repository = widget.myProgramRepository;
    if (repository == null) {
      return;
    }

    try {
      // Retry up to 3 times on first load only, mirroring
      // _fetchFollowPrograms behaviour.  Once we have a result the API
      // response is authoritative — the user may simply not be broadcasting.
      FollowProgram? program;
      const int maxAttempts = 3;
      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        program = widget.broadcastControlRepository != null
            ? await repository.fetchControllableProgram(
                userSession: userSession,
              )
            : await repository.fetchOwnProgram(userSession: userSession);
        if (!mounted) {
          return;
        }
        if (program != null || _myProgram != null) {
          break;
        }
        if (attempt < maxAttempts - 1) {
          await Future<void>.delayed(
            Duration(seconds: math.pow(2, attempt).toInt()),
          );
          if (!mounted) {
            return;
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _myProgram = program;
      });
    } on Object catch (e) {
      // Catch Object (not just Exception) to match the safety net in
      // _fetchAllPrograms and ensure Error types are also logged here
      // rather than only at the Future.wait level.
      _errorLog('Error in _fetchMyProgram', error: e);
    }
  }

  Future<void> _fetchFollowPrograms(String userSession) async {
    final FollowProgramRepository? repository = widget.followProgramRepository;
    if (repository == null) {
      return;
    }

    // Retry up to 3 times on first load only. Once we have a result
    // (even empty), it is authoritative — the user may simply have no
    // followed broadcasts on air.
    List<FollowProgram> programs = const <FollowProgram>[];
    const int maxAttempts = 3;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      programs = await repository.fetchOnAirPrograms(userSession: userSession);
      if (!mounted) {
        return;
      }
      if (programs.isNotEmpty || _followPrograms.isNotEmpty) {
        break;
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(
          Duration(seconds: math.pow(2, attempt).toInt()),
        );
        if (!mounted) {
          return;
        }
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _followPrograms = programs;
    });
  }

  static String? _buildIconUrlFromUserId(String? userId) {
    return buildNicoIconUrl(userId);
  }

  DateTime? _resolveCommentBeginAt() {
    final DateTime? followBeginAt = _followBeginAt;
    final DateTime? resolvedBeginAt = widget.beginAtNotifier?.value;
    if (resolvedBeginAt == null) {
      return followBeginAt;
    }
    if (followBeginAt == null) {
      return resolvedBeginAt;
    }

    // Follow-list beginAt arrives immediately, but API responses can
    // occasionally provide an invalid future epoch. In that case, prefer the
    // programinfo beginAt so comment rows keep elapsed-time rendering.
    if (_isFutureBeginAt(followBeginAt) && !_isFutureBeginAt(resolvedBeginAt)) {
      return resolvedBeginAt;
    }
    // When both values are still in the future, keep the follow-list value.
    // This preserves the immediate tap-path source of truth and avoids
    // switching timestamps repeatedly until a valid non-future beginAt arrives.
    return followBeginAt;
  }

  bool _isFutureBeginAt(DateTime value) {
    return value.isAfter(DateTime.now());
  }

  void _connectToProgram(FollowProgram program) {
    _followBroadcasterName = program.providerName;
    _followBroadcasterIconUrl = program.providerIconUrl;
    _followBeginAt = program.beginAt;
    _controller.text = program.programId;
    _debugLogLazy(
      () =>
          '[SelectScreen] follow program tapped: programId=${program.programId}',
    );
    unawaited(
      _connect(
        connectSource: 'follow-program',
        preferredBroadcasterId: program.providerUserId,
      ),
    );
  }

  Future<void> _fetchFavoriteUserStatus() async {
    final Set<String> favoriteIds = _settingsNotifier.value.favoriteUserIdSet;
    if (favoriteIds.isEmpty) {
      if (_favoriteOnAirMap.isNotEmpty) {
        setState(() {
          _favoriteOnAirMap = const <String, FollowProgram>{};
        });
      }
      return;
    }

    _debugLogLazy(
      () =>
          '[SelectScreen] favorite status refresh start: users=${favoriteIds.length}',
    );
    final Map<String, FollowProgram> result = await _favoriteUserLiveChecker
        .checkBroadcastStatus(favoriteIds);
    if (!mounted) {
      return;
    }

    setState(() {
      _favoriteOnAirMap = result;
    });
    _debugLogLazy(
      () =>
          '[SelectScreen] favorite status refresh done: onAir=${result.length}',
    );
  }

  void _connectToFavoriteProgram(FollowProgram program) {
    _followBroadcasterName = program.providerName;
    _followBroadcasterIconUrl = program.providerIconUrl;
    _followBeginAt = program.beginAt;
    _controller.text = program.programId;
    _debugLogLazy(
      () =>
          '[SelectScreen] favorite program tapped: programId=${program.programId}',
    );
    unawaited(
      _connect(
        connectSource: 'favorite-user',
        preferredBroadcasterId: program.providerUserId,
      ),
    );
  }

  /// Issue #739: pushes the latest [AppSettings.playRemainingAfterEnded]
  /// value to the optional sink supplied by the parent. Called both
  /// initially and on every [_settingsNotifier] change so toggling the
  /// switch in the TTS settings screen propagates without rebuilding the
  /// foreground service controller.
  void _syncPlayRemainingAfterEndedSink() {
    final ValueNotifier<bool>? sink = widget.playRemainingAfterEndedSink;
    if (sink == null) {
      return;
    }
    final bool latest = _settingsNotifier.value.playRemainingAfterEnded;
    if (sink.value != latest) {
      sink.value = latest;
    }
  }

  Future<void> _reloadSettingsFromStore() async {
    final SettingsStore? settingsStore = widget.settingsStore;
    if (settingsStore == null) {
      return;
    }

    final AppSettings loaded = await settingsStore.load();
    if (!mounted) {
      return;
    }

    _settingsNotifier.value = loaded;
    _preMuteVolume = settingsStore.loadPreMuteVolume();
    _preMuteAndroidTtsVolume = settingsStore.loadPreMuteAndroidTtsVolume();
    _requestFavoriteUserNameResolution();
    if (widget.themeModeNotifier != null &&
        widget.themeModeNotifier!.value != loaded.themeMode) {
      widget.themeModeNotifier!.value = loaded.themeMode;
    }
  }

  bool _isTerminalLike(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        return true;
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        return false;
    }
  }
}

class _LoginStatusBanner extends StatelessWidget {
  const _LoginStatusBanner({
    required this.isLoggedIn,
    required this.themeMode,
    required this.onTapLogin,
  });

  final bool? isLoggedIn;
  final AppThemeMode themeMode;
  final VoidCallback onTapLogin;

  @override
  Widget build(BuildContext context) {
    final bool? loggedIn = isLoggedIn;
    if (loggedIn == null) {
      return const SizedBox.shrink();
    }

    final AppThemeMode effectiveMode = AppTheme.resolveEffectiveMode(
      themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    final AppThemeColors colors = AppTheme.colorsFor(effectiveMode);

    if (loggedIn) {
      return Semantics(
        label: 'ニコニコ ログイン済み',
        child: Container(
          key: const Key('login-status-banner-ok'),
          width: double.infinity,
          color: colors.loginBannerOkBackground,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.check_circle,
                color: colors.loginBannerOkIcon,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'ニコニコ ログイン済み',
                style: TextStyle(color: colors.loginBannerOkForeground),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: 'ログインが必要です。タップして設定を開く',
      child: Material(
        key: const Key('login-status-banner-required'),
        color: colors.loginBannerWarningBackground,
        child: InkWell(
          onTap: onTapLogin,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.warning_amber_rounded,
                  color: colors.loginBannerWarningIcon,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ログインが必要です。タップして設定を開く',
                    style: TextStyle(
                      color: colors.loginBannerWarningForeground,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.loginBannerWarningIcon),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Combined scrollable list showing both follow programs and favorite user
/// broadcasts in a single [RefreshIndicator]-wrapped [ListView].
///
/// Sections are rendered as:
///   1. Favorite users on-air (if any)
///   2. Follow programs (if any)
///   3. Empty placeholder when both lists are empty
class _CombinedProgramList extends StatelessWidget {
  const _CombinedProgramList({
    required this.followPrograms,
    required this.favoriteOnAirMap,
    required this.enabled,
    required this.onFollowTap,
    required this.onFavoriteTap,
    required this.onRefresh,
    this.onFavoriteRefresh,
  });

  final List<FollowProgram> followPrograms;
  final Map<String, FollowProgram> favoriteOnAirMap;
  final bool enabled;
  final void Function(FollowProgram program) onFollowTap;
  final void Function(FollowProgram program) onFavoriteTap;
  final Future<void> Function() onRefresh;
  final VoidCallback? onFavoriteRefresh;

  @override
  Widget build(BuildContext context) {
    final bool hasFavorites = favoriteOnAirMap.isNotEmpty;
    final bool hasFollows = followPrograms.isNotEmpty;

    if (!hasFavorites && !hasFollows) {
      // Empty state: still allow pull-to-refresh.
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 64),
            Center(
              child: Text(
                '放送中の番組はありません',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Build a flat list of widgets: favorite section first, then follow section.
    final List<Widget> children = <Widget>[];

    if (hasFavorites) {
      children.add(_buildFavoriteSectionHeader(context));
      final List<FollowProgram> favoritePrograms = favoriteOnAirMap.values
          .toList();
      for (int i = 0; i < favoritePrograms.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 1));
        }
        final FollowProgram program = favoritePrograms[i];
        children.add(
          _FollowProgramTile(
            program: program,
            enabled: enabled,
            onTap: () => onFavoriteTap(program),
            accentColor: Colors.pinkAccent,
          ),
        );
      }
    }

    if (hasFollows) {
      children.add(_buildFollowSectionHeader(context));
      for (int i = 0; i < followPrograms.length; i++) {
        if (i > 0) {
          children.add(const Divider(height: 1));
        }
        final FollowProgram program = followPrograms[i];
        children.add(
          _FollowProgramTile(
            program: program,
            enabled: enabled,
            onTap: () => onFollowTap(program),
          ),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: children,
      ),
    );
  }

  Widget _buildFavoriteSectionHeader(BuildContext context) {
    final int count = favoriteOnAirMap.length;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 4, top: 4, bottom: 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.favorite, size: 16, color: Colors.pinkAccent),
          const SizedBox(width: 6),
          Text('お気に入りユーザーの放送', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(
            '$count件',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const Spacer(),
          if (onFavoriteRefresh != null)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                padding: EdgeInsets.zero,
                tooltip: '配信状態を更新',
                onPressed: onFavoriteRefresh,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFollowSectionHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: <Widget>[
          const Icon(Icons.sensors, size: 16, color: Colors.red),
          const SizedBox(width: 6),
          Text('フォロー中の放送', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 8),
          Text(
            '${followPrograms.length}件',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowProgramTile extends StatelessWidget {
  const _FollowProgramTile({
    required this.program,
    required this.enabled,
    required this.onTap,
    this.accentColor = Colors.red,
  });

  final FollowProgram program;
  final bool enabled;
  final VoidCallback onTap;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? elapsed = program.elapsedLabel();
    final String semanticsLabel = _buildSemanticsLabel(elapsed);

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: <Widget>[
              _buildIconWithLiveIndicator(theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      program.title,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatProviderInfo(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (elapsed != null) ...<Widget>[
                Icon(
                  Icons.access_time,
                  size: 11,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(width: 3),
                Text(
                  elapsed,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.play_circle_outline,
                size: 20,
                color: enabled
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSemanticsLabel(String? elapsed) {
    final StringBuffer sb = StringBuffer('${program.providerName}の放送');
    sb.write(' ${program.title}');
    if (elapsed != null) {
      sb.write(' 経過$elapsed');
    }
    sb.write(' タップして接続');
    return sb.toString();
  }

  String _formatProviderInfo() {
    final String? community = program.communityName;
    if (community != null && community.isNotEmpty) {
      return '${program.providerName} / $community - ${program.programId}';
    }
    return '${program.providerName} - ${program.programId}';
  }

  Widget _buildIconWithLiveIndicator(ThemeData theme) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildIcon(),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    final String? iconUrl = program.providerIconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return Image.network(
        iconUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        cacheWidth: 80,
        cacheHeight: 80,
        errorBuilder: (_, _, _) => _buildFallbackIcon(),
      );
    }
    return _buildFallbackIcon();
  }

  static Widget _buildFallbackIcon() {
    return Container(
      width: 40,
      height: 40,
      color: Colors.grey.shade300,
      child: const Icon(Icons.person, size: 22, color: Colors.grey),
    );
  }
}

class _MyBroadcastSection extends StatelessWidget {
  const _MyBroadcastSection({
    required this.program,
    required this.enabled,
    required this.onTap,
  });

  final FollowProgram program;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? elapsed = program.elapsedLabel();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.videocam, size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Text('あなたの放送', style: theme.textTheme.titleSmall),
            ],
          ),
        ),
        const Divider(height: 1),
        Semantics(
          button: true,
          label: 'あなたの放送 ${program.title} タップして接続',
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: <Widget>[
                  _buildIconWithBroadcastIndicator(theme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          program.title,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          program.programId,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (elapsed != null) ...<Widget>[
                    Icon(
                      Icons.access_time,
                      size: 11,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      elapsed,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    Icons.play_circle_outline,
                    size: 20,
                    color: enabled
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildIconWithBroadcastIndicator(ThemeData theme) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: _buildIcon(),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    final String? iconUrl = program.providerIconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return Image.network(
        iconUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        cacheWidth: 80,
        cacheHeight: 80,
        errorBuilder: (_, _, _) => _buildFallbackIcon(),
      );
    }
    return _buildFallbackIcon();
  }

  static Widget _buildFallbackIcon() {
    return Container(
      width: 40,
      height: 40,
      color: Colors.orange.shade100,
      child: const Icon(Icons.videocam, size: 22, color: Colors.orange),
    );
  }
}

/// Result of [computeSpeechMuteToggle].
///
/// `updated` is the [AppSettings] to persist after toggling. The two pre-mute
/// fields hold the per-engine pre-mute volumes (or `null` after unmute).
@immutable
class SpeechMuteToggleResult {
  const SpeechMuteToggleResult({
    required this.updated,
    required this.voicevoxPreMute,
    required this.androidTtsPreMute,
  });

  final AppSettings updated;
  final double? voicevoxPreMute;
  final double? androidTtsPreMute;
}

/// Pure function that decides the next mute state.
///
/// Extracted from `_SelectScreenState._toggleSpeechMute` so the engine-agnostic
/// mute behaviour added for Issue #697 can be unit-tested without spinning up
/// the full SelectScreen + CommentScreen + MethodChannel stack.
///
/// Behaviour:
/// - When already muted (either pre-mute slot non-null), restore both engine
///   volumes from their respective pre-mute slots and clear both slots. A
///   slot may be `null` (e.g. on upgrade from a build that only persisted
///   the VOICEVOX slot, or the engine was on a single engine when muted) —
///   in that case the current value is preserved instead of being zeroed.
/// - When not muted, capture the current volumes for both engines into the
///   pre-mute slots and zero out both volumes. Volumes that were already 0
///   (so unmuting them would still be silent) are stored as `1.0` instead so
///   the user always recovers an audible state.
@visibleForTesting
SpeechMuteToggleResult computeSpeechMuteToggle({
  required AppSettings current,
  required double? currentVoicevoxPreMute,
  required double? currentAndroidTtsPreMute,
}) {
  final bool isMuted =
      currentVoicevoxPreMute != null || currentAndroidTtsPreMute != null;
  if (isMuted) {
    // Post-merge round-2 review: when one engine's pre-mute slot is null
    // (e.g. partial-write failure on a previous toggle, then app
    // restart) we previously fell back to `current.<engine>Volume`,
    // which is `0.0` because the muted save did succeed for the
    // settings record. Without this `> 0` guard the unmute would
    // restore the volume to 0 and leave the user with silence forever
    // even though they tapped unmute. Mirror the mute path's "store
    // 1.0 instead of 0" defence to guarantee the user always recovers
    // an audible state.
    final double restoredVoicevox =
        currentVoicevoxPreMute ??
        (current.voicevoxVolume > 0 ? current.voicevoxVolume : 1.0);
    final double restoredAndroidTts =
        currentAndroidTtsPreMute ??
        (current.androidTtsVolume > 0 ? current.androidTtsVolume : 1.0);
    return SpeechMuteToggleResult(
      updated: current.copyWith(
        voicevoxVolume: restoredVoicevox,
        androidTtsVolume: restoredAndroidTts,
      ),
      voicevoxPreMute: null,
      androidTtsPreMute: null,
    );
  }
  return SpeechMuteToggleResult(
    updated: current.copyWith(voicevoxVolume: 0.0, androidTtsVolume: 0.0),
    voicevoxPreMute: current.voicevoxVolume > 0 ? current.voicevoxVolume : 1.0,
    androidTtsPreMute: current.androidTtsVolume > 0
        ? current.androidTtsVolume
        : 1.0,
  );
}
