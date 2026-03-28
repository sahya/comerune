import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/settings/settings_store.dart';
import '../../application/timeline/timeline_store.dart';
import '../../data/auth/user_session_store.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../data/follow/follow_program.dart';
import '../../data/follow/follow_program_repository.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/utils/lv_parser.dart';
import '../screens/comment_screen.dart';
import '../screens/settings_screen.dart';

class SelectScreen extends StatefulWidget {
  const SelectScreen({
    required this.connectionSupervisor,
    this.timelineStore,
    this.settingsStore,
    this.initialSettings = AppSettings.defaults,
    this.onPrepareConnection,
    this.userSessionStore,
    this.programTitleNotifier,
    this.resolveUserName,
    this.requestUserNameResolve,
    this.userNameListenable,
    this.supplierUserIdNotifier,
    this.commentLogWriter,
    this.themeModeNotifier,
    this.followProgramRepository,
    super.key,
  });

  final ConnectionSupervisor connectionSupervisor;
  final TimelineStore? timelineStore;
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
  final ValueNotifier<AppThemeMode>? themeModeNotifier;
  final FollowProgramRepository? followProgramRepository;

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
  final ValueNotifier<bool?> _loginStateNotifier = ValueNotifier<bool?>(null);
  List<FollowProgram> _followPrograms = const <FollowProgram>[];
  bool _isLoadingFollowPrograms = false;
  Timer? _followRefreshTimer;

  static const Duration _followRefreshInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _settingsNotifier = ValueNotifier<AppSettings>(widget.initialSettings);
    _previousStatus = widget.connectionSupervisor.status;
    _controller.addListener(_onInputChanged);
    widget.connectionSupervisor.addListener(_onSupervisorChanged);
    if (widget.settingsStore != null) {
      unawaited(_reloadSettingsFromStore());
    }
    unawaited(_refreshLoginState());
    unawaited(_fetchFollowPrograms());
  }

  @override
  void didUpdateWidget(covariant SelectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionSupervisor != widget.connectionSupervisor) {
      oldWidget.connectionSupervisor.removeListener(_onSupervisorChanged);
      widget.connectionSupervisor.addListener(_onSupervisorChanged);
      _previousStatus = widget.connectionSupervisor.status;
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
    _loginStateNotifier.dispose();
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

    _previousStatus = status;
    setState(() {});
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

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) =>
            _buildCommentScreen(routeContext, lv),
      ),
    );
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
                            unawaited(_connect());
                          }
                        : null,
                    child: const Text('接続開始'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _FollowProgramList(
              programs: _followPrograms,
              isLoading: _isLoadingFollowPrograms,
              enabled: !_isConnectionInProgress,
              onTap: _connectToProgram,
              onRefresh: _fetchFollowPrograms,
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
      if (widget.timelineStore != null) widget.timelineStore!,
      if (widget.programTitleNotifier != null) widget.programTitleNotifier!,
      if (widget.userNameListenable != null) widget.userNameListenable!,
      if (widget.supplierUserIdNotifier != null) widget.supplierUserIdNotifier!,
    ];

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (BuildContext context, Widget? _) {
        final List<AppMessage> messages =
            widget.timelineStore?.messages ?? const <AppMessage>[];
        final bool nameResolutionEnabled =
            _settingsNotifier.value.resolveUserName;
        final String? supplierUserId = widget.supplierUserIdNotifier?.value;
        final String? resolvedName =
            nameResolutionEnabled && supplierUserId != null
                ? widget.resolveUserName?.call(supplierUserId)
                : null;
        final String? broadcasterName = resolvedName ?? _followBroadcasterName;

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
          broadcasterIconUrl: _followBroadcasterIconUrl,
          showUserName: _settingsNotifier.value.showUserName,
          commentFontSize: _settingsNotifier.value.commentFontSize,
          resolveUserName:
              nameResolutionEnabled ? widget.resolveUserName : null,
          requestUserNameResolve:
              nameResolutionEnabled ? widget.requestUserNameResolve : null,
          commentLogWriter: widget.commentLogWriter,
          autoSaveCommentLog: _settingsNotifier.value.autoSaveCommentLog,
          ngUserIds: _settingsNotifier.value.ngUserIdSet,
          onToggleNgUser: _toggleNgUser,
          themeMode: _settingsNotifier.value.themeMode,
        );
      },
    );
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

  Future<void> _onDifferentLvConnected(String previousLv, String nextLv) async {
    if (previousLv != nextLv) {
      widget.timelineStore?.clear();
    }
    _lastConnectedLv = nextLv;
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
        ),
      ),
    );

    await _reloadSettingsFromStore();
    await _refreshLoginState();
    await _fetchFollowPrograms();
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

  Future<void> _fetchFollowPrograms() async {
    final FollowProgramRepository? repository = widget.followProgramRepository;
    final UserSessionStore? sessionStore = widget.userSessionStore;
    if (repository == null || sessionStore == null) {
      return;
    }

    setState(() {
      _isLoadingFollowPrograms = true;
    });

    String userSession;
    try {
      userSession = await sessionStore.load();
    } on Exception {
      userSession = '';
    }

    final List<FollowProgram> programs =
        await repository.fetchOnAirPrograms(userSession: userSession);

    if (!mounted) {
      return;
    }

    setState(() {
      _followPrograms = programs;
      _isLoadingFollowPrograms = false;
    });

    _followRefreshTimer?.cancel();
    _followRefreshTimer =
        Timer(_followRefreshInterval, () => unawaited(_fetchFollowPrograms()));
  }

  void _connectToProgram(FollowProgram program) {
    _followBroadcasterName = program.providerName;
    _followBroadcasterIconUrl = program.providerIconUrl;
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
    required this.onTapLogin,
  });

  final bool? isLoggedIn;
  final VoidCallback onTapLogin;

  @override
  Widget build(BuildContext context) {
    final bool? loggedIn = isLoggedIn;
    if (loggedIn == null) {
      return const SizedBox.shrink();
    }

    if (loggedIn) {
      return Semantics(
        label: 'ニコニコ ログイン済み',
        child: Container(
          key: const Key('login-status-banner-ok'),
          width: double.infinity,
          color: Colors.green.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Row(
            children: <Widget>[
              Icon(Icons.check_circle, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('ニコニコ ログイン済み'),
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
        color: Colors.orange.shade50,
        child: InkWell(
          onTap: onTapLogin,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded,
                    color: Colors.orange.shade700, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('ログインが必要です。タップして設定を開く'),
                ),
                Icon(Icons.chevron_right, color: Colors.orange.shade700),
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
    required this.isLoading,
    required this.enabled,
    required this.onTap,
    required this.onRefresh,
  });

  final List<FollowProgram> programs;
  final bool isLoading;
  final bool enabled;
  final void Function(FollowProgram program) onTap;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (isLoading && programs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

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
      sb.write(' $elapsed経過');
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
