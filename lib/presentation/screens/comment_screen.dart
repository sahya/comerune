import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/models/app_message.dart';

const String kLegacyUnsupportedFormatMessage = 'legacy: 未対応フォーマット';

String _formatHms(DateTime value) {
  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

String _formatHmsOrDash(DateTime? value) {
  if (value == null) {
    return '-';
  }

  return _formatHms(value);
}

enum CommentSortOrder { ascending, descending }

class CommentScreen extends StatefulWidget {
  const CommentScreen({
    super.key,
    required this.lv,
    required this.connectionSupervisor,
    required this.messages,
    required this.onStopAllConnections,
    required this.onReconnectSameLv,
    required this.onDifferentLvConnected,
    this.onOpenSettings,
    this.debugMode = false,
    this.connectionMethod,
    this.programTitle,
    this.broadcasterName,
    this.showUserName = true,
    this.resolveUserName,
    this.requestUserNameResolve,
    this.commentLogWriter,
    this.autoSaveCommentLog = false,
  });

  final String lv;
  final ConnectionSupervisor connectionSupervisor;
  final List<AppMessage> messages;
  final Future<void> Function() onStopAllConnections;
  final Future<void> Function() onReconnectSameLv;
  final Future<void> Function(String previousLv, String nextLv)
      onDifferentLvConnected;
  final Future<void> Function()? onOpenSettings;
  final bool debugMode;
  final ConnectionMethod? connectionMethod;
  final String? programTitle;
  final String? broadcasterName;
  final bool showUserName;

  /// Returns the cached resolved name for a user ID, or null.
  final String? Function(String userId)? resolveUserName;

  /// Requests asynchronous resolution of a user ID.
  final void Function(String userId)? requestUserNameResolve;

  final CommentLogWriter? commentLogWriter;
  final bool autoSaveCommentLog;

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  static const double _autoScrollResumeThreshold = 50;

  late final ScrollController _scrollController;
  late ConnectionStatus _lastStatus;
  bool _autoScrollEnabled = true;
  bool _isStoppingForExit = false;
  bool _isSavingLog = false;
  CommentSortOrder _sortOrder = CommentSortOrder.ascending;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _lastStatus = widget.connectionSupervisor.status;
    widget.connectionSupervisor.addListener(_handleConnectionChanged);

    _requestUserNameResolution(widget.messages);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEdge(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant CommentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.connectionSupervisor != widget.connectionSupervisor) {
      oldWidget.connectionSupervisor.removeListener(_handleConnectionChanged);
      widget.connectionSupervisor.addListener(_handleConnectionChanged);
      _lastStatus = widget.connectionSupervisor.status;
    }

    if (oldWidget.lv != widget.lv) {
      _autoScrollEnabled = true;
      unawaited(widget.onDifferentLvConnected(oldWidget.lv, widget.lv));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEdge(animated: false);
      });
    }

    final bool hasNewMessages =
        _hasNewMessages(oldWidget.messages, widget.messages);
    if (hasNewMessages) {
      _requestUserNameResolutionForNewMessages(
        oldWidget.messages,
        widget.messages,
      );
      if (_autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToEdge();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.connectionSupervisor.removeListener(_handleConnectionChanged);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _requestUserNameResolution(List<AppMessage> messages) {
    final void Function(String)? request = widget.requestUserNameResolve;
    if (request == null) {
      return;
    }

    for (final AppMessage message in messages) {
      final String? userId = message.userId;
      if (userId != null && userId.isNotEmpty) {
        request(userId);
      }
    }
  }

  void _requestUserNameResolutionForNewMessages(
    List<AppMessage> oldMessages,
    List<AppMessage> newMessages,
  ) {
    final void Function(String)? request = widget.requestUserNameResolve;
    if (request == null) {
      return;
    }

    // Find where new messages diverge from old by locating the old tail ID
    // in the new list. This handles ring-buffer rotation (same length,
    // head removed + tail appended) correctly.
    int start = 0;
    if (oldMessages.isNotEmpty && newMessages.isNotEmpty) {
      final String oldTailId = oldMessages.last.id;
      for (int i = newMessages.length - 1; i >= 0; i--) {
        if (newMessages[i].id == oldTailId) {
          start = i + 1;
          break;
        }
      }
    }

    for (int i = start; i < newMessages.length; i++) {
      final String? userId = newMessages[i].userId;
      if (userId != null && userId.isNotEmpty) {
        request(userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // TODO(PR#20-O2): Flutter 3.24+ で onPopInvoked は deprecated。
      //   onPopInvokedWithResult に移行する。
      onPopInvoked: (bool didPop) {
        unawaited(_handleBackNavigation(didPop));
      },
      // TODO(PR#20-O3): AnimatedBuilder を ListenableBuilder に置き換える。
      //   Flutter 3.10+ で非アニメーション用途には ListenableBuilder が推奨。
      child: AnimatedBuilder(
        animation: widget.connectionSupervisor,
        builder: (BuildContext context, _) {
          final ConnectionStatus status = widget.connectionSupervisor.status;
          final List<AppMessage> visibleMessages = widget.messages
              .where(_shouldDisplayMessage)
              .toList(growable: false);

          final List<AppMessage> sortedMessages =
              _applySortOrder(visibleMessages);

          return Scaffold(
            appBar: AppBar(
              title: Text(widget.lv),
              actions: <Widget>[
                if (widget.commentLogWriter != null)
                  IconButton(
                    key: const Key('save-comment-log-button'),
                    icon: const Icon(Icons.save),
                    tooltip: 'コメントログを保存',
                    onPressed:
                        _isSavingLog ? null : () => unawaited(_saveLogManual()),
                  ),
                IconButton(
                  key: const Key('sort-toggle-button'),
                  icon: Icon(
                    _sortOrder == CommentSortOrder.ascending
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                  ),
                  tooltip: _sortOrder == CommentSortOrder.ascending
                      ? '新しい順に切替'
                      : '古い順に切替',
                  onPressed: _toggleSortOrder,
                ),
                PopupMenuButton<String>(
                  onSelected: (_) async {
                    if (widget.onOpenSettings != null) {
                      await widget.onOpenSettings!.call();
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: Text('設定'),
                    ),
                  ],
                ),
              ],
            ),
            body: Column(
              children: <Widget>[
                if (widget.programTitle != null)
                  _ProgramTitleBar(
                    key: const Key('program-title-bar'),
                    title: widget.programTitle!,
                    broadcasterName: widget.broadcasterName,
                  ),
                _StatusBar(
                  key: const Key('status-bar'),
                  lv: widget.lv,
                  supervisor: widget.connectionSupervisor,
                  debugMode: widget.debugMode,
                  connectionMethod: widget.connectionMethod,
                ),
                Expanded(
                  child: ListView.builder(
                    key: const Key('comment-list'),
                    controller: _scrollController,
                    itemCount: sortedMessages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final AppMessage message = sortedMessages[index];
                      return _CommentRow(
                        message: message,
                        resolvedUserName: _resolveDisplayName(message),
                        showUserName: widget.showUserName,
                      );
                    },
                  ),
                ),
                _buildBottomAction(status),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _resolveDisplayName(AppMessage message) {
    if (message.userName != null) {
      return message.userName;
    }
    final String? userId = message.userId;
    if (userId == null) {
      return null;
    }
    return widget.resolveUserName?.call(userId);
  }

  void _toggleSortOrder() {
    setState(() {
      _sortOrder = _sortOrder == CommentSortOrder.ascending
          ? CommentSortOrder.descending
          : CommentSortOrder.ascending;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEdge(animated: false);
    });
  }

  List<AppMessage> _applySortOrder(List<AppMessage> messages) {
    if (_sortOrder == CommentSortOrder.ascending) {
      return messages;
    }

    return messages.reversed.toList(growable: false);
  }

  Future<void> _handleBackNavigation(bool didPop) async {
    if (didPop) {
      return;
    }

    await _stopForExit();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Widget _buildBottomAction(ConnectionStatus status) {
    if (status == ConnectionStatus.ended || status == ConnectionStatus.failed) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: const Key('reconnect-button'),
            onPressed: () async {
              await widget.onReconnectSameLv();
            },
            child: const Text('再接続'),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.all(12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          key: const Key('stop-button'),
          onPressed: _isStopEnabled(status)
              ? () async {
                  await _stopAndPop();
                }
              : null,
          child: const Text('接続停止'),
        ),
      ),
    );
  }

  bool _isStopEnabled(ConnectionStatus status) {
    switch (status) {
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

  Future<void> _stopAndPop() async {
    await _stopForExit();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _stopForExit() async {
    if (_isStoppingForExit) {
      return;
    }
    _isStoppingForExit = true;

    try {
      _markStoppedIfPossible();
      await widget.onStopAllConnections();
    } finally {
      _isStoppingForExit = false;
    }
  }

  void _markStoppedIfPossible() {
    if (_isStopEnabled(widget.connectionSupervisor.status)) {
      widget.connectionSupervisor.stopByUser();
    }
  }

  void _handleConnectionChanged() {
    final ConnectionStatus currentStatus = widget.connectionSupervisor.status;

    if (widget.autoSaveCommentLog && _isAutoSaveTrigger(currentStatus)) {
      unawaited(_saveLogAuto());
    }

    if (_lastStatus != ConnectionStatus.failed &&
        currentStatus == ConnectionStatus.failed) {
      final String message = _buildFailedSnackbarMessage();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }

    _lastStatus = currentStatus;
  }

  String _buildFailedSnackbarMessage() {
    final ConnectionErrorCode? errorCode =
        widget.connectionSupervisor.lastError;
    final String base = _failedMessage(errorCode);
    final String detail = widget.connectionSupervisor.lastErrorDetail ?? '';
    final String compactDetail =
        detail.isEmpty ? '-' : _compactSingleLine(detail);

    if (widget.debugMode) {
      final String code = errorCode?.code ?? 'UNKNOWN_ERROR';
      return '$base [code: $code] 原因: $compactDetail 再接続ボタンで再試行できます。';
    }

    final String detailSuffix =
        detail.isEmpty ? '' : ' 原因: ${_compactSingleLine(detail)}';
    return '$base$detailSuffix 再接続ボタンで再試行できます。';
  }

  String _failedMessage(ConnectionErrorCode? errorCode) {
    switch (errorCode) {
      case ConnectionErrorCode.sessionWsConnectFailed:
        return 'セッション接続に失敗しました';
      case ConnectionErrorCode.sessionWsTimeout:
        return 'セッション接続がタイムアウトしました';
      case ConnectionErrorCode.endpointResolveFailed:
        return 'コメントサーバーの取得に失敗しました';
      case ConnectionErrorCode.ndgrStreamFailed:
      case ConnectionErrorCode.legacyWsFailed:
        return 'コメント受信に失敗しました';
      case ConnectionErrorCode.lvParseFailed:
        return '放送IDが見つかりません';
      case ConnectionErrorCode.speechBouyomiFailed:
      case ConnectionErrorCode.speechVoicevoxFailed:
      case ConnectionErrorCode.userStopped:
      case null:
        return '接続に失敗しました';
      case ConnectionErrorCode.broadcastEnded:
        return '放送が終了しました';
    }
  }

  String _compactSingleLine(String value) {
    return value.replaceAll('\n', ' ').trim();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_sortOrder == CommentSortOrder.ascending) {
      _handleScrollAscending();
    } else {
      _handleScrollDescending();
    }
  }

  void _handleScrollAscending() {
    final bool nearBottom = _isNearBottom();
    if (nearBottom && !_autoScrollEnabled) {
      _autoScrollEnabled = true;
      return;
    }

    if (_autoScrollEnabled &&
        !nearBottom &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.forward) {
      _autoScrollEnabled = false;
    }
  }

  void _handleScrollDescending() {
    final bool nearTop = _isNearTop();
    if (nearTop && !_autoScrollEnabled) {
      _autoScrollEnabled = true;
      return;
    }

    if (_autoScrollEnabled &&
        !nearTop &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.reverse) {
      _autoScrollEnabled = false;
    }
  }

  bool _shouldDisplayMessage(AppMessage message) {
    switch (message.type) {
      case AppMessageType.chat:
      case AppMessageType.operator:
      case AppMessageType.notification:
        return true;
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return false;
    }
  }

  bool _hasNewMessages(
    List<AppMessage> previous,
    List<AppMessage> current,
  ) {
    if (identical(previous, current)) {
      return false;
    }
    if (current.isEmpty) {
      return false;
    }
    if (previous.isEmpty) {
      return true;
    }
    if (previous.length != current.length) {
      return true;
    }
    return previous.last.id != current.last.id;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) {
      return true;
    }

    final double distanceToBottom = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    return distanceToBottom <= _autoScrollResumeThreshold;
  }

  bool _isNearTop() {
    if (!_scrollController.hasClients) {
      return true;
    }

    return _scrollController.position.pixels <= _autoScrollResumeThreshold;
  }

  bool _isAutoSaveTrigger(ConnectionStatus status) {
    if (_lastStatus == status) {
      return false;
    }
    switch (status) {
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
      case ConnectionStatus.failed:
        return true;
      case ConnectionStatus.idle:
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        return false;
    }
  }

  Future<void> _saveLogManual() async {
    final bool hasMessages = widget.messages.any(_shouldDisplayMessage);
    if (!hasMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('保存するコメントがありません')),
          );
      }
      return;
    }

    final String? path = await _saveLog();
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (path != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('コメントログを保存しました: $path')),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('コメントログの保存に失敗しました')),
      );
    }
  }

  Future<void> _saveLogAuto() async {
    await _saveLog();
  }

  Future<String?> _saveLog() async {
    final CommentLogWriter? writer = widget.commentLogWriter;
    if (writer == null) {
      return null;
    }

    setState(() {
      _isSavingLog = true;
    });

    try {
      final List<AppMessage> messages =
          widget.messages.where(_shouldDisplayMessage).toList(growable: false);
      return await writer.save(lv: widget.lv, messages: messages);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLog = false;
        });
      }
    }
  }

  void _scrollToEdge({bool animated = true}) {
    if (!_scrollController.hasClients) {
      return;
    }

    final double offset = _sortOrder == CommentSortOrder.ascending
        ? _scrollController.position.maxScrollExtent
        : 0;

    if (!animated) {
      _scrollController.jumpTo(offset);
      return;
    }

    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
}

class _ProgramTitleBar extends StatelessWidget {
  const _ProgramTitleBar({
    super.key,
    required this.title,
    this.broadcasterName,
  });

  final String title;
  final String? broadcasterName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.indigo.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            key: const Key('program-title-text'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (broadcasterName != null)
            Text(
              '配信者: $broadcasterName',
              key: const Key('broadcaster-name-text'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    super.key,
    required this.lv,
    required this.supervisor,
    required this.debugMode,
    required this.connectionMethod,
  });

  final String lv;
  final ConnectionSupervisor supervisor;
  final bool debugMode;
  final ConnectionMethod? connectionMethod;

  @override
  Widget build(BuildContext context) {
    final Color wifiColor =
        supervisor.wifiIndicatorColor == WifiIndicatorColor.green
            ? Colors.green
            : Colors.red;

    return Container(
      width: double.infinity,
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.wifi,
                key: const Key('status-wifi-icon'),
                color: wifiColor,
              ),
              const SizedBox(width: 8),
              Text(
                'lv: $lv',
                key: const Key('status-lv'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: <Widget>[
              Text(
                '最終受信: ${_formatHmsOrDash(supervisor.lastReceivedAt)}',
                key: const Key('status-last-received'),
              ),
              Text(
                '再接続: ${supervisor.reconnectCount}回',
                key: const Key('status-reconnect-count'),
              ),
              Text(
                'エラー: ${_errorLabel(supervisor.lastError)}',
                key: const Key('status-last-error'),
              ),
            ],
          ),
          if (debugMode) ...<Widget>[
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: <Widget>[
                Text(
                  '方式: ${_connectionMethodLabel(connectionMethod)}',
                  key: const Key('status-connection-method'),
                ),
                Text(
                  'フェーズ: ${supervisor.status.code}',
                  key: const Key('status-phase'),
                ),
                if ((supervisor.lastErrorDetail ?? '').isNotEmpty)
                  Text(
                    'エラー詳細: ${supervisor.lastErrorDetail}',
                    key: const Key('status-last-error-detail'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _connectionMethodLabel(ConnectionMethod? method) {
    switch (method) {
      case ConnectionMethod.ndgr:
        return 'NDGR';
      case ConnectionMethod.legacy:
        return 'legacy';
      case null:
        return '-';
    }
  }

  String _errorLabel(ConnectionErrorCode? code) {
    switch (code) {
      case ConnectionErrorCode.broadcastEnded:
        return '放送終了';
      case ConnectionErrorCode.userStopped:
        return 'ユーザー停止';
      case null:
        return '-';
      case ConnectionErrorCode.lvParseFailed:
      case ConnectionErrorCode.sessionWsConnectFailed:
      case ConnectionErrorCode.sessionWsTimeout:
      case ConnectionErrorCode.endpointResolveFailed:
      case ConnectionErrorCode.ndgrStreamFailed:
      case ConnectionErrorCode.legacyWsFailed:
      case ConnectionErrorCode.speechBouyomiFailed:
      case ConnectionErrorCode.speechVoicevoxFailed:
        return code.code;
    }
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.message,
    this.resolvedUserName,
    this.showUserName = true,
  });

  final AppMessage message;
  final String? resolvedUserName;
  final bool showUserName;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('comment-row-${message.id}'),
      color: _backgroundColor(message),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(_lineText(message)),
    );
  }

  String _lineText(AppMessage message) {
    final String timestamp = _formatHms(message.timestamp);

    if (!showUserName) {
      return '$timestamp  ${message.content}';
    }

    final String userId = message.userId ?? '';

    if (userId.isEmpty) {
      return '$timestamp  ${message.content}';
    }

    final String displayName =
        resolvedUserName != null ? '$resolvedUserName ($userId)' : userId;

    return '$timestamp  $displayName  ${message.content}';
  }

  Color? _backgroundColor(AppMessage message) {
    if (_isLegacyUnsupportedSystemMessage(message)) {
      return Colors.lightBlue.shade50;
    }

    switch (message.type) {
      case AppMessageType.operator:
        return Colors.yellow.shade100;
      case AppMessageType.notification:
        return Colors.lightBlue.shade50;
      case AppMessageType.chat:
      // TODO(PR#20-O1): gift/nicoad は _shouldDisplayMessage で除外済みのため
      //   ここには到達しない。将来 gift/nicoad を表示する際に背景色を定義する。
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return null;
    }
  }

  bool _isLegacyUnsupportedSystemMessage(AppMessage message) {
    final Object? raw = message.raw;
    if (raw is Map<Object?, Object?> &&
        raw['kind'] == 'legacy_unsupported_format') {
      return true;
    }

    return message.type == AppMessageType.notification &&
        message.content == kLegacyUnsupportedFormatMessage;
  }
}
