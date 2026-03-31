import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../application/statistics/statistics_store.dart';
import '../../application/timeline/timeline_store.dart';
import '../../data/auth/user_session_store.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../data/follow/follow_program.dart';
import '../../data/follow/follow_program_repository.dart';
import '../../data/follow/my_program_repository.dart';
import '../../data/user/user_attribute_store.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/utils/lv_parser.dart';
import '../../comment_speech/comment_speech.dart'
    show MethodChannelCommentSpeech, SpeechSettings;
import '../screens/comment_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/app_theme.dart';

/// Builds a niconico user icon URL from a numeric user ID.
///
/// Returns `null` for non-numeric IDs (e.g. anonymous `a:xxx` format).
String? buildNicoIconUrl(String? userId) {
  if (userId == null || userId.isEmpty) {
    return null;
  }
  final int? numericId = int.tryParse(userId);
  if (numericId == null) {
    return null;
  }
  final int prefix = numericId ~/ 10000;
  return 'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/$prefix/$numericId.jpg';
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
    this.resolveUserName,
    this.requestUserNameResolve,
    this.userNameListenable,
    this.supplierUserIdNotifier,
    this.beginAtNotifier,
    this.commentLogWriter,
    this.themeModeNotifier,
    this.followProgramRepository,
    this.myProgramRepository,
    this.userAttributeStore,
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
  final String? Function(String userId)? resolveUserName;
  final void Function(String userId)? requestUserNameResolve;
  final Listenable? userNameListenable;
  final ValueNotifier<String?>? supplierUserIdNotifier;
  final ValueNotifier<DateTime?>? beginAtNotifier;
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final FollowProgramRepository? followProgramRepository;
  final MyProgramRepository? myProgramRepository;
  final UserAttributeStore? userAttributeStore;

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> {
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
  final ValueNotifier<
          ({Map<String, int> colors, Map<String, String> nicknames})>
      _userAttrNotifier =
      ValueNotifier<({Map<String, int> colors, Map<String, String> nicknames})>(
    (colors: const <String, int>{}, nicknames: const <String, String>{}),
  );
  String? _currentBroadcasterId;
  final MethodChannelCommentSpeech _speechPlatform =
      MethodChannelCommentSpeech();

  static const Duration _followRefreshInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _settingsNotifier = ValueNotifier<AppSettings>(widget.initialSettings);
    _previousStatus = widget.connectionSupervisor.status;
    _controller.addListener(_onInputChanged);
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
    _followRefreshTimer?.cancel();
    widget.connectionSupervisor.removeListener(_onSupervisorChanged);
    widget.supplierUserIdNotifier?.removeListener(_onSupplierUserIdChanged);
    _loginStateNotifier.dispose();
    _userAttrNotifier.dispose();
    _settingsNotifier.dispose();
    _controller
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
  }

  // TODO(PR#18-optional): setState rebuilds the entire widget on every
  //  keystroke. Consider using ValueListenableBuilder to limit rebuilds to
  //  the connect button's enabled/disabled state only.
  void _onInputChanged() {
    setState(() {});
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
        id: 'system:broadcast_ended:${now.millisecondsSinceEpoch}',
        timestamp: now,
        content: '放送が終了しました',
        type: AppMessageType.notification,
      ),
    );
  }

  bool get _isConnectionInProgress =>
      !widget.connectionSupervisor.canStartConnection;

  bool get _canAttemptConnection {
    if (_controller.text.trim().isEmpty) {
      return false;
    }
    return widget.connectionSupervisor.canStartConnection;
  }

  void _onSubmit(String _) {
    _followBroadcasterName = null;
    _followBroadcasterIconUrl = null;
    _followBeginAt = null;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_canAttemptConnection) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String? lv = LvParser.extract(_controller.text);
    if (lv == null) {
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('放送IDが見つかりません')));
      return;
    }

    final AppSettings settings = _settingsNotifier.value;
    if (_lastConnectedLv != null && _lastConnectedLv != lv) {
      widget.timelineStore?.clear();
    }
    widget.timelineStore?.setCapacity(
      settings.pastCommentFetchCount.historyCount,
    );
    await widget.onPrepareConnection?.call(lv, settings);

    final bool started = widget.connectionSupervisor.startConnection();

    if (!started || !mounted) {
      return;
    }

    _lastConnectedLv = lv;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) =>
            _buildCommentScreen(routeContext, lv),
      ),
    );

    if (mounted) {
      unawaited(_fetchAllPrograms());
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
                  child: ElevatedButton(
                    key: const Key('select_screen_connect_button'),
                    onPressed: _canAttemptConnection
                        ? () {
                            _followBroadcasterName = null;
                            _followBroadcasterIconUrl = null;
                            _followBeginAt = null;
                            unawaited(_connect());
                          }
                        : null,
                    child: const Text('接続開始'),
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
            child: _FollowProgramList(
              programs: _followPrograms,
              enabled: !_isConnectionInProgress,
              onTap: _connectToProgram,
              onRefresh: _fetchAllPrograms,
            ),
          ),
          if (_settingsNotifier.value.favoriteUserIdSet.isNotEmpty)
            _FavoriteUserSection(
              userIds: _settingsNotifier.value.favoriteUserIdSet,
              resolveUserName: widget.resolveUserName,
              userNameListenable: widget.userNameListenable,
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
      if (widget.timelineStore != null) widget.timelineStore!,
      if (widget.statisticsStore != null) widget.statisticsStore!,
      if (widget.programTitleNotifier != null) widget.programTitleNotifier!,
      if (widget.userNameListenable != null) widget.userNameListenable!,
      if (widget.supplierUserIdNotifier != null) widget.supplierUserIdNotifier!,
      if (widget.beginAtNotifier != null) widget.beginAtNotifier!,
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
            ? widget.resolveUserName?.call(supplierUserId)
            : null;
        final String? broadcasterName =
            cachedBroadcasterName ?? _followBroadcasterName;
        final String? broadcasterIconUrl = _followBroadcasterIconUrl ??
            _buildIconUrlFromUserId(supplierUserId);

        return CommentScreen(
          lv: lv,
          connectionSupervisor: widget.connectionSupervisor,
          messages: messages,
          onStopAllConnections: _stopAllConnections,
          onReconnectSameLv: _reconnectSameLv,
          onDifferentLvConnected: _onDifferentLvConnected,
          onOpenSettings: widget.settingsStore == null
              ? null
              : () => _openSettings(routeContext, widget.userSessionStore),
          debugMode: _settingsNotifier.value.debugMode,
          connectionMethod: _connectionMethod,
          programTitle: widget.programTitleNotifier?.value,
          broadcasterName: broadcasterName,
          broadcasterUserId: supplierUserId,
          broadcasterIconUrl: broadcasterIconUrl,
          // Prefer the follow-list beginAt (available immediately) and
          // fall back to the programinfo API value (resolved async).
          beginAt: _followBeginAt ?? widget.beginAtNotifier?.value,
          showUserName: _settingsNotifier.value.showUserName,
          commentFontSize: _settingsNotifier.value.commentFontSize,
          resolveUserName:
              nameResolutionEnabled ? widget.resolveUserName : null,
          requestUserNameResolve:
              nameResolutionEnabled ? widget.requestUserNameResolve : null,
          commentLogWriter: widget.commentLogWriter,
          autoSaveCommentLog: _settingsNotifier.value.autoSaveCommentLog,
          autoSaveCommentLogPath:
              _settingsNotifier.value.autoSaveCommentLogPath,
          ngUserIds: _settingsNotifier.value.ngUserIdSet,
          ngWords: _settingsNotifier.value.ngWordList,
          onToggleNgUser: _toggleNgUser,
          starPrefixHidingEnabled:
              _settingsNotifier.value.starPrefixHidingEnabled,
          userColorMap: _userAttrNotifier.value.colors,
          onUserColorChanged:
              widget.userAttributeStore != null ? _onUserColorChanged : null,
          onUserColorRemoved:
              widget.userAttributeStore != null ? _onUserColorRemoved : null,
          userNicknameMap: _userAttrNotifier.value.nicknames,
          onNicknameChanged:
              widget.userAttributeStore != null ? _onNicknameChanged : null,
          onNicknameRemoved:
              widget.userAttributeStore != null ? _onNicknameRemoved : null,
          autoNicknameRegistration:
              _settingsNotifier.value.autoNicknameRegistration,
          themeMode: _settingsNotifier.value.themeMode,
          statisticsEnabled: _settingsNotifier.value.statisticsEnabled,
          statisticsViewerCommentEnabled:
              _settingsNotifier.value.statisticsViewerCommentEnabled,
          statisticsActiveUserEnabled:
              _settingsNotifier.value.statisticsActiveUserEnabled,
          highlightPickupEnabled:
              _settingsNotifier.value.highlightPickupEnabled,
          viewerCount: widget.statisticsStore?.viewerCount,
          totalCommentCount: widget.statisticsStore?.totalCommentCount ?? 0,
          activeUserCount: widget.statisticsStore?.activeUserCount ?? 0,
          speechPlatform: _speechPlatform,
          speechSettings: _buildSpeechSettings(),
          readUserName: _settingsNotifier.value.readUserName,
          settingsStore: widget.settingsStore,
          onDictionaryRulesChanged: _onDictionaryRulesChanged,
        );
      },
    );
  }

  SpeechSettings _buildSpeechSettings() {
    final AppSettings s = _settingsNotifier.value;
    debugPrint(
        '[SelectScreen] buildSpeechSettings: engine=${s.speechEngine}, speaker=${s.voicevoxSpeaker}, speed=${s.voicevoxSpeed}');
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
      settings.pastCommentFetchCount.historyCount,
    );
    await widget.onPrepareConnection?.call(lv, settings);

    final bool retried =
        widget.connectionSupervisor.retryConnectionFromTerminal();
    if (!retried && widget.connectionSupervisor.canStartConnection) {
      widget.connectionSupervisor.startConnection();
    }
  }

  Future<void> _onDifferentLvConnected(String previousLv, String nextLv) {
    if (previousLv != nextLv) {
      widget.timelineStore?.clear();
      _currentBroadcasterId = null;
      _userAttrNotifier.value = (
        colors: const <String, int>{},
        nicknames: const <String, String>{},
      );
    }
    _lastConnectedLv = nextLv;
    return Future<void>.value();
  }

  void _onSupplierUserIdChanged() {
    final String? supplierUserId = widget.supplierUserIdNotifier?.value;
    if (supplierUserId != null && supplierUserId != _currentBroadcasterId) {
      unawaited(_loadUserAttributes(supplierUserId));
    }
  }

  void _requestFavoriteUserNameResolution() {
    final void Function(String)? request = widget.requestUserNameResolve;
    if (request == null) {
      return;
    }
    for (final String userId in _settingsNotifier.value.favoriteUserIdSet) {
      request(userId);
    }
  }

  Future<void> _loadUserAttributes(String? broadcasterId) async {
    if (broadcasterId == null ||
        broadcasterId == _currentBroadcasterId ||
        widget.userAttributeStore == null) {
      return;
    }
    _currentBroadcasterId = broadcasterId;
    final Map<String, int> colors =
        await widget.userAttributeStore!.loadColors(broadcasterId);
    final Map<String, String> nicknames =
        await widget.userAttributeStore!.loadNicknames(broadcasterId);
    if (!mounted || _currentBroadcasterId != broadcasterId) {
      return;
    }
    _userAttrNotifier.value = (colors: colors, nicknames: nicknames);
  }

  void _onUserColorChanged(String userId, int colorValue) {
    final ({Map<String, int> colors, Map<String, String> nicknames}) prev =
        _userAttrNotifier.value;
    _userAttrNotifier.value = (
      colors: Map<String, int>.from(prev.colors)..[userId] = colorValue,
      nicknames: prev.nicknames,
    );
    final String? broadcasterId = _currentBroadcasterId;
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(widget.userAttributeStore!.setColor(
        broadcasterId: broadcasterId,
        userId: userId,
        colorValue: colorValue,
      ));
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
      unawaited(widget.userAttributeStore!.removeColor(
        broadcasterId: broadcasterId,
        userId: userId,
      ));
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
    if (broadcasterId != null && widget.userAttributeStore != null) {
      unawaited(widget.userAttributeStore!.setNickname(
        broadcasterId: broadcasterId,
        userId: userId,
        nickname: nickname,
      ));
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
      unawaited(widget.userAttributeStore!.removeNickname(
        broadcasterId: broadcasterId,
        userId: userId,
      ));
    }
  }

  void _onDictionaryRulesChanged(AppSettings updated) {
    _settingsNotifier.value = updated;
  }

  void _toggleNgUser(String userId) {
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
          resolveUserName: widget.resolveUserName,
          requestUserNameResolve: widget.requestUserNameResolve,
          userNameListenable: widget.userNameListenable,
          speechPlatform: MethodChannelCommentSpeech(),
        ),
      ),
    );

    await _reloadSettingsFromStore();
    await _refreshLoginState();
    await _fetchAllPrograms();
    // Reload user attributes in case nicknames were edited in settings.
    // Use the notifier value as fallback in the same way as the broadcasterId
    // passed to SettingsScreen above.
    final String? activeBroadcasterId =
        _currentBroadcasterId ?? widget.supplierUserIdNotifier?.value;
    if (activeBroadcasterId != null) {
      _currentBroadcasterId = null;
      await _loadUserAttributes(activeBroadcasterId);
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

  /// Fetches both the user's own broadcast and follow programs in one pass,
  /// sharing a single [userSession] load to avoid redundant secure storage I/O.
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
      log(
        'Unexpected error during program fetch: $e',
        name: 'SelectScreen',
      );
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
        program =
            await repository.fetchOwnProgram(userSession: userSession);
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
      log(
        'Error in _fetchMyProgram: $e',
        name: 'SelectScreen',
      );
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

  void _connectToProgram(FollowProgram program) {
    _followBroadcasterName = program.providerName;
    _followBroadcasterIconUrl = program.providerIconUrl;
    _followBeginAt = program.beginAt;
    _controller.text = program.programId;
    unawaited(_connect());
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
              Icon(Icons.check_circle,
                  color: colors.loginBannerOkIcon, size: 18),
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
                Icon(Icons.warning_amber_rounded,
                    color: colors.loginBannerWarningIcon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ログインが必要です。タップして設定を開く',
                    style:
                        TextStyle(color: colors.loginBannerWarningForeground),
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

class _FollowProgramList extends StatelessWidget {
  const _FollowProgramList({
    required this.programs,
    required this.enabled,
    required this.onTap,
    required this.onRefresh,
  });

  final List<FollowProgram> programs;
  final bool enabled;
  final void Function(FollowProgram program) onTap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (programs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              const Icon(Icons.sensors, size: 16, color: Colors.red),
              const SizedBox(width: 6),
              Text(
                'フォロー中の放送',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${programs.length}件',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                width: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: const Icon(Icons.refresh),
                  tooltip: '更新',
                  onPressed: onRefresh,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: programs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                return _FollowProgramTile(
                  program: programs[index],
                  enabled: enabled,
                  onTap: () => onTap(programs[index]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FollowProgramTile extends StatelessWidget {
  const _FollowProgramTile({
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
                Icon(Icons.access_time,
                    size: 11, color: theme.colorScheme.outline),
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
                color:
                    enabled ? theme.colorScheme.primary : theme.disabledColor,
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
                color: Colors.red,
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
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
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
              Text(
                'あなたの放送',
                style: theme.textTheme.titleSmall,
              ),
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
                    Icon(Icons.access_time,
                        size: 11, color: theme.colorScheme.outline),
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
        errorBuilder: (_, __, ___) => _buildFallbackIcon(),
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

class _FavoriteUserSection extends StatefulWidget {
  const _FavoriteUserSection({
    required this.userIds,
    this.resolveUserName,
    this.userNameListenable,
  });

  final Set<String> userIds;
  final String? Function(String userId)? resolveUserName;
  final Listenable? userNameListenable;

  @override
  State<_FavoriteUserSection> createState() => _FavoriteUserSectionState();
}

class _FavoriteUserSectionState extends State<_FavoriteUserSection> {
  @override
  void initState() {
    super.initState();
    widget.userNameListenable?.addListener(_onUserNameChanged);
  }

  @override
  void didUpdateWidget(covariant _FavoriteUserSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userNameListenable != widget.userNameListenable) {
      oldWidget.userNameListenable?.removeListener(_onUserNameChanged);
      widget.userNameListenable?.addListener(_onUserNameChanged);
    }
  }

  @override
  void dispose() {
    widget.userNameListenable?.removeListener(_onUserNameChanged);
    super.dispose();
  }

  void _onUserNameChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.person_add, size: 16),
              const SizedBox(width: 6),
              Text(
                'お気に入りユーザー',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.userIds.length}件',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...widget.userIds.map((String userId) {
          final String? iconUrl = buildNicoIconUrl(userId);
          final String? nickname = widget.resolveUserName?.call(userId);
          return ListTile(
            dense: true,
            leading: ClipOval(
              child: SizedBox(
                width: 32,
                height: 32,
                child: iconUrl != null
                    ? Image.network(
                        iconUrl,
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        cacheWidth: 64,
                        cacheHeight: 64,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person, size: 20),
                      )
                    : const Icon(Icons.person, size: 20),
              ),
            ),
            title: Text(
              nickname != null ? '$nickname ($userId)' : userId,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }),
      ],
    );
  }
}
