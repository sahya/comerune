import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app_logging.dart';
import '../../application/comment_post/comment_post_controller.dart';
import '../../application/settings/settings_store.dart';
import '../../domain/models/comment_post_result.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/teach_command.dart';
import '../../domain/models/teach_command_handler.dart';
import '../../domain/utils/elapsed_formatter.dart';
import '../../domain/utils/url_extractor.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../theme/app_theme.dart';
import '../widgets/comment_input_bar.dart';
import 'comment_log_stats_sheet.dart';
import 'comment_screen_config.dart';
import 'user_detail_sheet.dart';

const String kLegacyUnsupportedFormatMessage = 'legacy: 未対応フォーマット';

/// Two-line mode: meta font size as a fraction of the comment font size.
const double _twoLineMetaFontRatio = 0.4;

/// Two-line mode: minimum meta font size in logical pixels.
const double _twoLineMinMetaFontSize = 9.0;

/// Zebra striping: background tint opacity applied to odd-indexed rows.
const double _zebraStripingAlpha = 0.04;

/// Converts an ARGB32 integer to [Color] without using the deprecated
/// `Color(int)` constructor.
Color colorFromARGB32(int argb32) {
  return Color.fromARGB(
    (argb32 >> 24) & 0xFF,
    (argb32 >> 16) & 0xFF,
    (argb32 >> 8) & 0xFF,
    argb32 & 0xFF,
  );
}

String _formatHms(DateTime value, {DateTime? beginAt}) {
  return formatCommentTime(value, beginAt: beginAt);
}

String _formatHmsOrDash(DateTime? value, {DateTime? beginAt}) {
  if (value == null) {
    return '-';
  }

  return _formatHms(value, beginAt: beginAt);
}

void _debugLog(String message) {
  appDebugLog(message);
}

void _debugLogLazy(String Function() messageBuilder) {
  appDebugLogLazy(messageBuilder);
}

void _errorLog(String message, {Object? error, StackTrace? stackTrace}) {
  appErrorLog(
    name: 'CommentScreen',
    message: message,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Resolves the display name string for a comment header.
///
/// - Chat comments: `"<resolvedName> (<userId>)"` or `"<userId>"` when the
///   user ID is present (existing behavior).
/// - Operator (運営) comments: the payload's `userName` (e.g. "運営") since
///   operator comments are normalized with `userId: null`, so the user-ID
///   based path above would otherwise silently drop the label.
/// - Returns `null` when no meaningful label can be rendered.
///
/// This is a top-level function so pinned rows, clipboard formatting and the
/// main `_CommentRow` all share the same fallback behaviour.
String? _displayNameForMessage(AppMessage message, {String? resolvedUserName}) {
  if (message.type == AppMessageType.operator) {
    final String? userName = message.userName;
    if (userName != null && userName.isNotEmpty) {
      return userName;
    }
    return null;
  }
  final String? userId = message.userId;
  if (userId == null || userId.isEmpty) {
    return null;
  }
  return resolvedUserName != null ? '$resolvedUserName ($userId)' : userId;
}

String _commentLineText({
  required AppMessage message,
  required bool showUserName,
  String? resolvedUserName,
  String? contentOverride,
  DateTime? beginAt,
  bool twoLine = false,
}) {
  final String timestamp = _formatHms(message.timestamp, beginAt: beginAt);
  final String content = contentOverride ?? message.content;

  if (!showUserName) {
    return '$timestamp  $content';
  }

  final String? displayName = _displayNameForMessage(
    message,
    resolvedUserName: resolvedUserName,
  );

  if (displayName == null) {
    return '$timestamp  $content';
  }

  if (twoLine) {
    return '$timestamp  $displayName\n$content';
  }

  return '$timestamp  $displayName  $content';
}

/// Test-only accessor for [_commentLineText].
///
/// Exposed so unit tests can pin operator-message formatting (both one-line
/// and two-line modes) without routing through widget tree inspection. The
/// real function stays private; this wrapper is a thin delegation and must
/// not be called from production code.
@visibleForTesting
String commentLineTextForTesting({
  required AppMessage message,
  required bool showUserName,
  String? resolvedUserName,
  String? contentOverride,
  DateTime? beginAt,
  bool twoLine = false,
}) {
  return _commentLineText(
    message: message,
    showUserName: showUserName,
    resolvedUserName: resolvedUserName,
    contentOverride: contentOverride,
    beginAt: beginAt,
    twoLine: twoLine,
  );
}

enum CommentSortOrder { ascending, descending }

/// Actions reachable through the AppBar overflow menu. Kept private to the
/// screen because the menu's wiring lives entirely inside [CommentScreen].
enum _AppBarMenuAction { search, saveLog, settings }

/// Single source of truth for the "emphasize gift / nicoad" decision so
/// that background color and leading icon stay in sync.
///
/// Returns `true` only when [message] is a gift / nicoad message and the
/// user-facing emphasize toggle ([emphasize]) is on.
///
/// Implemented as a file-private top-level pure function so it can be
/// unit-tested without building a widget tree. Keep it pure: it must not
/// touch `BuildContext`, state, or global configuration — callers are
/// expected to resolve the `emphasize` flag from their own scope.
bool _shouldEmphasizeGiftNicoad(AppMessage message, {required bool emphasize}) {
  if (!emphasize) {
    return false;
  }
  return message.type == AppMessageType.gift ||
      message.type == AppMessageType.nicoad;
}

class CommentScreen extends StatefulWidget {
  const CommentScreen({
    super.key,
    required this.programInfo,
    required this.connectionSupervisor,
    required this.messages,
    required this.callbacks,
    this.debugMode = false,
    this.showUserName = true,
    this.commentFontSize = commentFontSizeDefault,
    this.userNameResolution,
    this.commentTwoLineEnabled = false,
    this.commentZebraStripingEnabled = false,
    this.userColorMap = const <String, int>{},
    this.onUserColorChanged,
    this.onUserColorRemoved,
    this.userNicknameMap = const <String, String>{},
    this.onNicknameChanged,
    this.onNicknameRemoved,
    this.autoNicknameRegistration = true,
    required this.themeMode,
    this.statistics = const CommentStatisticsConfig(),
    this.filterConfig = const CommentFilterConfig(),
    this.logConfig = const CommentLogConfig(),
    this.speechConfig = const CommentSpeechConfig(),
    this.commentPostController,
    this.userSessionLoader,
  });

  /// Program-level metadata (lv, title, broadcaster info, etc.).
  final CommentProgramInfo programInfo;

  final ConnectionSupervisor connectionSupervisor;
  final List<AppMessage> messages;

  /// Grouped callback parameters.
  final CommentCallbacks callbacks;

  final bool debugMode;
  final bool showUserName;
  final double commentFontSize;

  /// Bundles user-name resolution callbacks and listenable updates.
  final UserNameResolution? userNameResolution;

  /// When true, comment rows are split into two lines:
  /// line 1 for timestamp/username, line 2 for content.
  final bool commentTwoLineEnabled;

  /// When true, alternating comment rows have a subtle background tint
  /// for easier visual scanning.
  final bool commentZebraStripingEnabled;

  /// Per-user comment color map. Keys are user IDs, values are ARGB32 ints.
  final Map<String, int> userColorMap;

  /// Called when the user sets a custom comment color for a user.
  final void Function(String userId, int colorValue)? onUserColorChanged;

  /// Called when the user removes a custom comment color.
  final void Function(String userId)? onUserColorRemoved;

  /// Per-user nickname (コテハン) map. Keys are user IDs, values are nicknames.
  final Map<String, String> userNicknameMap;

  /// Called when a nickname is set or updated for a user.
  final void Function(String userId, String nickname)? onNicknameChanged;

  /// Called when a nickname is removed for a user.
  final void Function(String userId)? onNicknameRemoved;

  /// Whether automatic nickname registration via `@name` comments is enabled.
  final bool autoNicknameRegistration;

  final AppThemeMode themeMode;

  /// Statistics display configuration and live data.
  final CommentStatisticsConfig statistics;

  /// Grouped filter parameters (NG users, NG words, colors, nicknames).
  final CommentFilterConfig filterConfig;

  /// Grouped comment-log parameters.
  final CommentLogConfig logConfig;

  /// Grouped speech (VoiceVox) parameters.
  final CommentSpeechConfig speechConfig;

  /// Controller for posting live comments. When `null`, the comment-post
  /// FAB/input bar is disabled regardless of login state.
  final CommentPostController? commentPostController;

  /// Loads the current niconico `user_session`. When it resolves to a
  /// non-empty string the comment-post FAB is shown.
  final Future<String> Function()? userSessionLoader;

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  static const double _autoScrollResumeThreshold = 50;
  static const Duration _wakelockReleaseDelay = Duration(seconds: 45);

  /// Upper bound on the keyword search text length. Pasted strings longer
  /// than this are truncated by the TextField; keeps the AppBar search UI
  /// from ballooning and avoids degenerate O(N*M) search with giant queries.
  static const int _kSearchMaxLength = 100;

  late final ScrollController _scrollController;
  late ConnectionStatus _lastStatus;
  bool _autoScrollEnabled = true;
  bool _isStoppingForExit = false;
  bool _isSavingLog = false;
  CommentSortOrder _sortOrder = CommentSortOrder.ascending;
  final Set<String> _pinnedMessageIds = <String>{};
  bool _touchActive = false;

  bool _speechInitializing = false;
  bool _speechInitialized = false;
  bool _speechStarted = false;
  String _speechEngineState = '';

  Timer? _wakelockReleaseTimer;

  /// Periodic timer that ensures new comments are submitted for speech
  /// even when the widget tree is not rebuilt (e.g. while the app is
  /// backgrounded and [didUpdateWidget] is not called).
  Timer? _speechPollTimer;
  StreamSubscription<SpeechEvent>? _speechEventSub;

  /// The ID of the last message processed for speech.
  /// Initialized when speech starts (baseline), then updated after each
  /// submission. This avoids depending on oldWidget.messages which may
  /// reference the same mutable list as widget.messages.
  String? _lastSpeechMessageId;

  /// Timestamp recorded just before the speech engine starts. Messages with a
  /// timestamp before this value are skipped, ensuring that only comments
  /// arriving after speech initialization are read aloud.
  DateTime? _speechBaselineTimestamp;
  List<String> _effectivePresetNgWords = const <String>[];
  List<String> _normalizedEffectiveNgWords = const <String>[];

  /// Cached user_session for the comment-post feature. Empty string means
  /// "not logged in" and hides the FAB. Loaded in [initState].
  String _commentPostUserSession = '';

  /// Whether the current user is the broadcaster of the viewed program.
  /// Resolved asynchronously after [_commentPostUserSession] is loaded.
  bool _isBroadcaster = false;

  /// Whether the comment-post input overlay is currently expanded. When
  /// `false` the FAB is shown; when `true` the input bar is shown inline
  /// below the bottom action bar.
  bool _commentInputExpanded = false;

  /// Whether the input bar is currently awaiting a server response. While
  /// `true`, the backdrop tap-to-close is suppressed so a stray tap does
  /// not dismiss the bar out from under an in-progress submission.
  bool _commentInputSending = false;

  /// Monotonic counter incremented on every call to
  /// [_resolveCommentPostContext]. Each in-flight resolution captures the
  /// value at start; if it does not match the latest counter at await
  /// resume time, the result is stale (e.g. a faster lv switch raced
  /// ahead) and discarded so the UI reflects the most recent context only.
  int _commentPostContextGeneration = 0;

  // ---------------------------------------------------------------------------
  // NG protection notification state (Issue #244)
  //
  // Tracked only when [CommentFilterConfig.ngProtectionNotificationEnabled]
  // is true. Keeps a running badge count (never throttled) and a throttled
  // snackbar window so that bursts of filtered comments don't spam the UI.
  // ---------------------------------------------------------------------------

  /// Cumulative count of comments hidden by NG filtering while the screen
  /// is alive. Shown as an AppBar badge when > 0. Reset on dispose via
  /// widget teardown; there is no manual clear in this PR.
  int _protectedCount = 0;

  /// Timestamp of the most recent protection snackbar. Used to throttle
  /// subsequent snackbars to at most one per [_protectionSnackBarWindow].
  DateTime? _lastProtectionNotificationAt;

  /// The ID of the last message inspected for NG protection. New messages
  /// are only evaluated once, even if the widget rebuilds with the same list.
  String? _lastProtectionInspectedMessageId;

  /// Window during which additional NG detections do not trigger new
  /// snackbars (the badge still increments). 10 seconds per spec.
  static const Duration _protectionSnackBarWindow = Duration(seconds: 10);

  // Comment keyword search state.
  bool _isSearching = false;
  String _searchQuery = '';
  // Normalized (trimmed + lowercased) form of [_searchQuery], cached so that
  // the per-message match check stays O(L) per message instead of recomputing
  // the normalization on every list rebuild.
  String _normalizedSearchQuery = '';
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  // Debounces rapid typing so we do not rebuild + re-filter the whole list
  // on every keystroke. Kept short (150ms) so the UI still feels responsive.
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _searchController = TextEditingController()
      ..addListener(_handleSearchTextChanged);
    _lastStatus = widget.connectionSupervisor.status;
    widget.connectionSupervisor.addListener(_handleConnectionChanged);
    unawaited(_resolveCommentPostContext());

    // Keep screen on while viewing comments.
    unawaited(WakelockPlus.enable());
    _syncWakelockForStatus(_lastStatus);

    _requestUserNameResolution(widget.messages);
    _effectivePresetNgWords = widget.filterConfig.presetNgWords;
    _refreshNormalizedNgWords();

    // Seed the NG-protection cursor with the current tail so that messages
    // already in the list (e.g. past-comment backfill) are not announced
    // retroactively when the broadcaster opens the screen.
    if (widget.messages.isNotEmpty) {
      _lastProtectionInspectedMessageId = widget.messages.last.id;
    }
    if (widget.filterConfig.presetNgWords.isEmpty) {
      unawaited(_loadPresetNgWordsFromAsset());
    }

    _debugLogLazy(
      () =>
          '[CommentScreen] initState: speech.enabled=${widget.speechConfig.speechSettings.enabled}, '
          'platform=${widget.speechConfig.speechPlatform != null ? "ok" : "null"}',
    );
    if (widget.speechConfig.speechSettings.enabled &&
        widget.speechConfig.speechPlatform != null) {
      _debugLog('[CommentScreen] initState: scheduling speech init');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_initializeAndStartSpeech());
        }
      });
    }

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

    if (!_listEqualsShallow(
          oldWidget.filterConfig.ngWords,
          widget.filterConfig.ngWords,
        ) ||
        !_listEqualsShallow(
          oldWidget.filterConfig.presetNgWords,
          widget.filterConfig.presetNgWords,
        )) {
      if (widget.filterConfig.presetNgWords.isNotEmpty) {
        _effectivePresetNgWords = widget.filterConfig.presetNgWords;
        _refreshNormalizedNgWords();
      } else if (oldWidget.filterConfig.presetNgWords.isNotEmpty &&
          widget.filterConfig.presetNgWords.isEmpty) {
        _effectivePresetNgWords = const <String>[];
        _refreshNormalizedNgWords();
        unawaited(_loadPresetNgWordsFromAsset());
      } else {
        _refreshNormalizedNgWords();
      }
    }

    if (oldWidget.programInfo.lv != widget.programInfo.lv) {
      _autoScrollEnabled = true;
      _pinnedMessageIds.clear();
      // Reset NG-protection state when switching to a different program so
      // that the AppBar badge / throttle window do not leak across lv
      // transitions. The cursor is re-seeded after the new message tail
      // arrives via _processNgProtectionNotifications.
      _protectedCount = 0;
      _lastProtectionInspectedMessageId = widget.messages.isNotEmpty
          ? widget.messages.last.id
          : null;
      _lastProtectionNotificationAt = null;
      unawaited(
        widget.callbacks.onDifferentLvConnected(
          oldWidget.programInfo.lv,
          widget.programInfo.lv,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEdge(animated: false);
      });
      // Re-resolve comment-post context (broadcaster flag) for the new lv.
      // Note: state change from _resolveCommentPostContext will trigger
      // the broadcaster flag reset via setState. The immediate reset below
      // avoids a frame where the stale broadcaster flag is visible.
      setState(() {
        _isBroadcaster = false;
      });
      unawaited(_resolveCommentPostContext());
    }

    if (_pinnedMessageIds.isNotEmpty) {
      _cleanUpStalePinnedIds();
    }

    final String lastId = widget.messages.isNotEmpty
        ? widget.messages.last.id
        : 'empty';
    _debugLogLazy(
      () =>
          '[CommentScreen] didUpdate: msgs ${oldWidget.messages.length}→${widget.messages.length}, '
          'identical=${identical(oldWidget.messages, widget.messages)}, lastId=$lastId',
    );

    if (oldWidget.speechConfig.speechSettings !=
        widget.speechConfig.speechSettings) {
      _debugLogLazy(
        () =>
            '[CommentScreen] didUpdate: speechSettings changed: '
            'enabled ${oldWidget.speechConfig.speechSettings.enabled}→${widget.speechConfig.speechSettings.enabled}',
      );
      unawaited(
        _handleSpeechSettingsChanged(oldWidget.speechConfig.speechSettings),
      );
    }

    // Speech: detect new messages independently of _hasNewMessages because
    // the message list may be mutable (oldWidget and widget share the same
    // data). Track progress via _lastSpeechMessageId instead.
    if (_speechStarted && widget.speechConfig.speechSettings.enabled) {
      _submitNewCommentsForSpeech(widget.messages);
    }

    final bool hasNewMessages = _hasNewMessages(
      oldWidget.messages,
      widget.messages,
    );
    if (hasNewMessages) {
      // Log new comment texts for debugging.
      _logNewComments(oldWidget.messages, widget.messages);
      _requestUserNameResolutionForNewMessages(
        oldWidget.messages,
        widget.messages,
      );
      _processNicknameComments(oldWidget.messages, widget.messages);
      _processNgProtectionNotifications(widget.messages);
      // While searching, the user is reading a filtered view, so avoid
      // forcing auto-scroll to the newest comment.
      if (_isSearching) {
        // no-op: auto-scroll is paused during search.
      } else if (_autoScrollEnabled && !_touchActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToEdge();
        });
      } else if (!_touchActive && !_autoScrollEnabled) {
        // Re-check whether the user has scrolled back to the edge.
        // The scroll listener may not fire when maxScrollExtent changes
        // due to new messages, so we check here to resume auto-scroll.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _autoScrollEnabled) return;
          final bool atEdge = _sortOrder == CommentSortOrder.ascending
              ? _isNearBottom()
              : _isNearTop();
          if (atEdge) {
            setState(() {
              _autoScrollEnabled = true;
            });
            _scrollToEdge();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _stopWakelockReleaseTimer();
    unawaited(WakelockPlus.disable());
    _debugLogLazy(
      () => '[CommentScreen] dispose: speechStarted=$_speechStarted',
    );
    _stopSpeechPollTimer();
    _speechEventSub?.cancel();
    if (_speechStarted) {
      _debugLog('[CommentScreen] dispose: stopping speech engine');
      unawaited(widget.speechConfig.speechPlatform?.stop(clearQueue: true));
    }
    widget.connectionSupervisor.removeListener(_handleConnectionChanged);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_handleSearchTextChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _requestUserNameResolution(List<AppMessage> messages) {
    final UserNameResolution? resolution = widget.userNameResolution;
    if (resolution == null) {
      return;
    }

    for (final AppMessage message in messages) {
      final String? userId = message.userId;
      if (userId != null && userId.isNotEmpty) {
        resolution.requestResolve(userId);
      }
    }
  }

  void _requestUserNameResolutionForNewMessages(
    List<AppMessage> oldMessages,
    List<AppMessage> newMessages,
  ) {
    final UserNameResolution? resolution = widget.userNameResolution;
    if (resolution == null) {
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
        resolution.requestResolve(userId);
      }
    }
  }

  void _logNewComments(
    List<AppMessage> oldMessages,
    List<AppMessage> newMessages,
  ) {
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
      final AppMessage m = newMessages[i];
      if (m.type == AppMessageType.chat) {
        _debugLogLazy(
          () =>
              '[CommentScreen] newComment: id=${m.id}, user=${m.userId ?? "unknown"}, chars=${m.content.length}',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Speech (VoiceVox) integration
  // ---------------------------------------------------------------------------

  Future<void> _initializeAndStartSpeech() async {
    _debugLogLazy(
      () =>
          '[CommentScreen] initSpeech: enter '
          '(initializing=$_speechInitializing, initialized=$_speechInitialized)',
    );
    if (_speechInitializing) return;
    final CommentSpeechPlatform? platform = widget.speechConfig.speechPlatform;
    if (platform == null) {
      _debugLog('[CommentScreen] initSpeech: platform=null, abort');
      return;
    }
    _speechInitializing = true;

    // Check if engine is already ready from a previous session.
    if (!_speechInitialized) {
      _debugLog('[CommentScreen] initSpeech: checking engine status...');
      try {
        final SpeechRuntimeStatus status = await platform.getStatus();
        _debugLogLazy(
          () =>
              '[CommentScreen] initSpeech: engine=${status.engineState}, '
              'player=${status.playerState}, queue=${status.queueSize}',
        );
        if (status.engineState == 'READY') {
          _speechInitialized = true;
          _debugLog('[CommentScreen] initSpeech: engine already READY');
        }
      } catch (e) {
        _errorLog('[CommentScreen] initSpeech: getStatus failed', error: e);
      }
    }

    // Show setup dialog for first-time download & initialization.
    if (!_speechInitialized) {
      _debugLog('[CommentScreen] initSpeech: showing SetupDialog...');
      if (!mounted) {
        _speechInitializing = false;
        return;
      }
      final bool success = await VoicevoxSetupDialog.show(context, platform);
      _debugLogLazy(
        () => '[CommentScreen] initSpeech: SetupDialog result=$success',
      );
      if (!success || !mounted) {
        _speechInitializing = false;
        return;
      }
      _speechInitialized = true;
    }

    // Configure, subscribe to events, and start.
    try {
      _speechEventSub?.cancel();
      _speechEventSub = platform.events.listen(_onSpeechEvent);

      // Record baseline BEFORE awaiting engine start so that comments
      // arriving during initialization are not accidentally skipped.
      _speechBaselineTimestamp = DateTime.now();
      if (widget.messages.isNotEmpty) {
        _lastSpeechMessageId = widget.messages.last.id;
      }

      _debugLog('[CommentScreen] initSpeech: updateSettings → start()...');
      await platform.updateSettings(widget.speechConfig.speechSettings);
      await platform.start();

      final ConnectionStatus currentStatus = widget.connectionSupervisor.status;
      if (!mounted ||
          !widget.speechConfig.speechSettings.enabled ||
          currentStatus == ConnectionStatus.ended ||
          currentStatus == ConnectionStatus.failed ||
          currentStatus == ConnectionStatus.stopped) {
        _speechEventSub?.cancel();
        _speechEventSub = null;
        _speechBaselineTimestamp = null;
        _speechStarted = false;
        _speechEngineState = '';
        try {
          await platform.stop(clearQueue: true);
        } catch (e) {
          _errorLog('[CommentScreen] initSpeech: abort stop FAILED', error: e);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _speechStarted = true;
          _speechEngineState = 'READY';
        });
      }
      _startSpeechPollTimer();
      _debugLogLazy(
        () =>
            '[CommentScreen] Speech started. baseline=$_lastSpeechMessageId, '
            'msgCount=${widget.messages.length}',
      );
    } catch (e, stackTrace) {
      _errorLog(
        '[CommentScreen] initSpeech: FAILED',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _speechEngineState = 'ERROR';
        });
      }
    } finally {
      _speechInitializing = false;
    }
  }

  Future<void> _handleSpeechSettingsChanged(SpeechSettings oldSettings) async {
    _debugLogLazy(
      () =>
          '[CommentScreen] settingsChanged: enabled ${oldSettings.enabled}→'
          '${widget.speechConfig.speechSettings.enabled}, started=$_speechStarted',
    );
    if (!oldSettings.enabled && widget.speechConfig.speechSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → enabling speech');
      await _initializeAndStartSpeech();
    } else if (oldSettings.enabled &&
        !widget.speechConfig.speechSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → disabling speech');
      await _stopSpeech();
    } else if (widget.speechConfig.speechSettings.enabled && _speechStarted) {
      _debugLog('[CommentScreen] settingsChanged: → pushing update to engine');
      try {
        await widget.speechConfig.speechPlatform?.updateSettings(
          widget.speechConfig.speechSettings,
        );
      } catch (e) {
        _errorLog(
          '[CommentScreen] settingsChanged: updateSettings FAILED',
          error: e,
        );
      }
    }
  }

  Future<void> _stopSpeech() async {
    _debugLogLazy(() => '[CommentScreen] stopSpeech: started=$_speechStarted');
    _stopSpeechPollTimer();
    if (_speechStarted) {
      try {
        await widget.speechConfig.speechPlatform?.stop(clearQueue: true);
        _debugLog('[CommentScreen] stopSpeech: stopped');
      } catch (e) {
        _errorLog('[CommentScreen] stopSpeech: FAILED', error: e);
      }
      _speechBaselineTimestamp = null;
      if (mounted) {
        setState(() {
          _speechStarted = false;
          _speechEngineState = '';
        });
      }
    }
  }

  void _onSpeechEvent(SpeechEvent event) {
    _debugLogLazy(
      () =>
          '[CommentScreen] speechEvent: ${event.type}, payload=${event.payload}',
    );
    if (event.type == SpeechEventType.engineStateChanged) {
      final String state = event.payload['state'] as String? ?? '';
      if (mounted) {
        setState(() {
          _speechEngineState = state;
        });
      }
    }
  }

  void _startSpeechPollTimer() {
    _stopSpeechPollTimer();
    _speechPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      // Only poll when the app is not in a resumed (foreground) state.
      // When resumed, didUpdateWidget already submits new comments.
      final AppLifecycleState? lifecycleState =
          WidgetsBinding.instance.lifecycleState;
      if (lifecycleState == AppLifecycleState.resumed) return;

      if (_speechStarted && widget.speechConfig.speechSettings.enabled) {
        _submitNewCommentsForSpeech(widget.messages);
      }
    });
  }

  void _stopSpeechPollTimer() {
    _speechPollTimer?.cancel();
    _speechPollTimer = null;
  }

  void _submitNewCommentsForSpeech(List<AppMessage> messages) {
    final CommentSpeechPlatform? platform = widget.speechConfig.speechPlatform;
    if (platform == null || messages.isEmpty) {
      return;
    }

    // Nothing new since last check.
    final String currentLastId = messages.last.id;
    if (_lastSpeechMessageId == currentLastId) {
      return;
    }

    // Find where new messages start — after _lastSpeechMessageId.
    int start = 0;
    if (_lastSpeechMessageId != null) {
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i].id == _lastSpeechMessageId) {
          start = i + 1;
          break;
        }
      }
    }

    _lastSpeechMessageId = currentLastId;
    final int candidates = messages.length - start;
    _debugLogLazy(
      () => '[CommentScreen] submitNewComments: candidates=$candidates',
    );

    for (int i = start; i < messages.length; i++) {
      final AppMessage message = messages[i];
      // Skip messages that arrived before speech was initialized.
      if (_speechBaselineTimestamp != null &&
          message.timestamp.isBefore(_speechBaselineTimestamp!)) {
        continue;
      }
      // Decide whether this message type should ever be spoken.
      // chat -> always speak (subject to filters below).
      // gift / nicoad -> only when the user enabled the dedicated toggle.
      //   When enabled, only the body (`message.content`) is spoken and the
      //   NG user / star-prefix / teach / slash-prefix / NG-word / user-name
      //   pipeline is intentionally skipped, because gift/nicoad messages
      //   have no meaningful user context and their bodies are system-generated.
      // Any other type -> skip (existing behavior preserved).
      if (message.type == AppMessageType.gift) {
        if (!widget.speechConfig.readGiftComment) {
          continue;
        }
        // TODO(security): gift 本文は現在「xxx が yyy を購入しました」のような
        // システム固定文を前提に NG フィルターをバイパスしている。将来 API が
        // 変わり購入者が任意テキストを乗せられるようになった場合、ここを
        // nicoad と同じ `_containsNgWord` チェックに切り替える必要がある。
        _submitGiftOrNicoadSpeech(platform, message);
        continue;
      }
      if (message.type == AppMessageType.nicoad) {
        if (!widget.speechConfig.readNicoadComment) {
          continue;
        }
        // ニコニ広告は購入者が任意テキストを乗せられるため、卑猥・悪意のある
        // 文言を読み上げさせる攻撃ベクタになりうる。gift とは異なり本文が
        // システム固定文ではないため、NG ワード一致時は読み上げをスキップする。
        // 表示（_shouldDisplayMessage 側）は従来どおりバイパス（重要イベント
        // の見逃し防止）で、読み上げだけに保護を効かせる非対称設計。
        // NG ヒット時は silent skip（`_protectedCount` バッジには加算しない）。
        // バッジは「NG ユーザー / NG ワードによりコメントが非表示にされた」
        // ことを伝える既存仕様であり、ここは表示はバイパスして読み上げだけを
        // 落とすため、バッジ加算するとユーザーに「コメントが消えた」と
        // 誤解させてしまう。
        if (_containsNgWord(message.content)) {
          _debugLog('[CommentScreen] submitComment: SKIP nicoad NG word');
          continue;
        }
        _submitGiftOrNicoadSpeech(platform, message);
        continue;
      }
      if (message.type != AppMessageType.chat) {
        continue;
      }
      // Skip NG users.
      final String? userId = message.userId;
      if (userId != null && widget.filterConfig.ngUserIds.contains(userId)) {
        _debugLogLazy(
          () => '[CommentScreen] submitComment: SKIP NG user=$userId',
        );
        continue;
      }
      // Skip star-prefix hidden comments.
      if (widget.filterConfig.starPrefixHidingEnabled &&
          message.content.startsWith('☆')) {
        _debugLog('[CommentScreen] submitComment: SKIP star-prefix');
        continue;
      }
      // Handle teach/unteach commands (owner only, never spoken).
      // Must run before the slash-prefix skip so that `/teach` / `/unteach`
      // commands still trigger the dictionary handler even when slash-prefix
      // skip is enabled.
      if (TeachCommandParser.isTeachCommand(message.content)) {
        if (message.userId == widget.programInfo.broadcasterUserId) {
          unawaited(_handleTeachCommand(message));
        }
        continue;
      }
      // Skip slash-prefix comments (shown in the list, but not read aloud).
      if (widget.filterConfig.slashPrefixSkipEnabled &&
          message.content.startsWith('/')) {
        _debugLog('[CommentScreen] submitComment: SKIP slash-prefix');
        continue;
      }
      // Skip comments containing NG words.
      if (_containsNgWord(message.content)) {
        _debugLog('[CommentScreen] submitComment: SKIP NG word');
        continue;
      }

      String speechText = message.content;
      if (widget.speechConfig.readUserName) {
        final String? displayName = _resolveSpeechDisplayName(message);
        if (displayName != null && displayName.isNotEmpty) {
          final String nameWithHonorific = _appendSan(displayName);
          if (nameWithHonorific.isNotEmpty) {
            speechText = '$speechText、$nameWithHonorific';
          }
        }
      }

      _debugLogLazy(() => '[CommentScreen] submitComment: $speechText');
      final RawComment comment = RawComment(
        id: message.id,
        text: speechText,
        userId: message.userId,
        postedAtEpochMs: message.timestamp.millisecondsSinceEpoch,
      );
      unawaited(
        platform.submitComment(comment).then((_) {}).catchError((Object e) {
          _errorLog('[CommentScreen] submitComment FAILED', error: e);
        }),
      );
    }
  }

  /// Submits a gift / ニコニ広告 message body to TTS.
  ///
  /// Only `message.content` is spoken — user-name prefixing, NG user,
  /// star/slash prefix handling, and teach-command parsing are intentionally
  /// skipped because gift / nicoad messages carry system-generated bodies
  /// (e.g. "xxx が yyy を購入しました") rather than user-authored chat.
  ///
  /// NG word filtering is applied *before* this helper is called for
  /// nicoad only (ad buyers can embed arbitrary text); gift bodies are
  /// system-fixed strings so NG filtering stays bypassed to avoid silencing
  /// legitimate monetization events. See the call site in
  /// [_submitNewCommentsForSpeech].
  void _submitGiftOrNicoadSpeech(
    CommentSpeechPlatform platform,
    AppMessage message,
  ) {
    if (message.content.isEmpty) {
      return;
    }
    _debugLogLazy(
      () =>
          '[CommentScreen] submitGiftOrNicoad: type=${message.type}, '
          'text=${message.content}',
    );
    final RawComment comment = RawComment(
      id: message.id,
      text: message.content,
      userId: message.userId,
      postedAtEpochMs: message.timestamp.millisecondsSinceEpoch,
    );
    unawaited(
      platform.submitComment(comment).then((_) {}).catchError((Object e) {
        _errorLog('[CommentScreen] submitGiftOrNicoad FAILED', error: e);
      }),
    );
  }

  /// Returns `true` when [content] contains any configured NG word.
  ///
  /// Delegates to [_matchedNgWord] so that normalization is done once per
  /// message (mirrors [AppSettings.containsNgWord] / [AppSettings.matchedNgWord]).
  bool _containsNgWord(String content) {
    return _matchedNgWord(content) != null;
  }

  Future<void> _handleTeachCommand(AppMessage message) async {
    final SettingsStore? store = widget.speechConfig.settingsStore;
    if (store == null) {
      return;
    }

    try {
      final AppSettings settings = await store.load();

      TeachCommandResult result;
      final TeachCommand? teach = TeachCommandParser.parseTeach(
        message.content,
      );
      if (teach != null) {
        result = TeachCommandHandler.executeTeach(
          command: teach,
          currentRules: settings.dictionaryRules,
          containsNgWord: settings.containsNgWord,
        );
      } else {
        final UnteachCommand? unteach = TeachCommandParser.parseUnteach(
          message.content,
        );
        if (unteach == null) {
          return;
        }
        result = TeachCommandHandler.executeUnteach(
          command: unteach,
          currentRules: settings.dictionaryRules,
        );
      }

      if (result.success && result.updatedRules != null) {
        final AppSettings updated = settings.copyWith(
          dictionaryRules: result.updatedRules,
        );
        await store.save(updated);
        widget.callbacks.onDictionaryRulesChanged?.call(updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on Object catch (e) {
      _errorLog('[CommentScreen] _handleTeachCommand FAILED', error: e);
    }
  }

  void _processNicknameComments(
    List<AppMessage> oldMessages,
    List<AppMessage> newMessages,
  ) {
    if (!widget.autoNicknameRegistration ||
        widget.callbacks.onNicknameChanged == null) {
      return;
    }

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
      final AppMessage message = newMessages[i];
      if (message.type != AppMessageType.chat) {
        continue;
      }
      final String? userId = message.userId;
      if (userId == null || userId.isEmpty) {
        continue;
      }
      final String content = message.content;
      if (!content.startsWith('@')) {
        continue;
      }
      final String nickname = content.substring(1).trim();
      if (nickname.isEmpty) {
        // `@` のみ → コテハン解除
        widget.callbacks.onNicknameRemoved?.call(userId);
      } else {
        widget.callbacks.onNicknameChanged!.call(userId, nickname);
      }
    }
  }

  /// Whether the comment-post FAB should be shown as a bottom-right overlay
  /// on the comment list.
  ///
  /// Shown when the feature is wired up, the user is logged in, and the
  /// input overlay is not already expanded.
  bool get _shouldShowCommentPostFab =>
      widget.commentPostController != null &&
      _commentPostUserSession.isNotEmpty &&
      !_commentInputExpanded;

  void _expandCommentInput() {
    if (_commentInputExpanded) {
      return;
    }
    setState(() {
      _commentInputExpanded = true;
    });
  }

  void _collapseCommentInput() {
    if (!_commentInputExpanded) {
      return;
    }
    setState(() {
      _commentInputExpanded = false;
    });
  }

  /// Resolves the user_session and broadcaster status used by the
  /// comment-post FAB. Called once in [initState] and again whenever
  /// [CommentScreen.programInfo.lv] changes in [didUpdateWidget].
  ///
  /// Uses [_commentPostContextGeneration] to discard stale results when a
  /// newer call has already started — without this guard, a slow first
  /// resolve completing after a faster second resolve would clobber the
  /// freshest broadcaster flag and leave the UI in an inconsistent state.
  Future<void> _resolveCommentPostContext() async {
    final Future<String> Function()? loader = widget.userSessionLoader;
    final CommentPostController? controller = widget.commentPostController;
    if (loader == null || controller == null) {
      return;
    }
    final int generation = ++_commentPostContextGeneration;
    final String session = await loader();
    if (!mounted || generation != _commentPostContextGeneration) {
      return;
    }
    final String trimmed = session.trim();
    if (_commentPostUserSession != trimmed) {
      setState(() {
        _commentPostUserSession = trimmed;
        // Reset broadcaster flag until re-checked against the new session.
        _isBroadcaster = false;
        // If the user logged out while the input was open, collapse it so
        // the stale UI does not accept submissions against an empty session.
        if (trimmed.isEmpty) {
          _commentInputExpanded = false;
        }
      });
    }
    if (trimmed.isEmpty) {
      return;
    }

    final BroadcasterCheckOutcome outcome = await controller
        .ensureBroadcasterStatus(
          lv: widget.programInfo.lv,
          userSession: trimmed,
        );
    if (!mounted || generation != _commentPostContextGeneration) {
      return;
    }
    final bool isBroadcaster = outcome == BroadcasterCheckOutcome.broadcaster;
    if (_isBroadcaster != isBroadcaster) {
      setState(() {
        _isBroadcaster = isBroadcaster;
      });
    }
  }

  Future<CommentSendResult> _handleCommentSend({
    required String text,
    required bool asOperator,
    required int maxLength,
    required bool isAnonymous,
  }) async {
    final CommentPostController? controller = widget.commentPostController;
    if (controller == null) {
      return const CommentSendResult.validation(
        CommentValidationError.missingProgram,
      );
    }
    final CommentSendResult result = await controller.postComment(
      lv: widget.programInfo.lv,
      userSession: _commentPostUserSession,
      text: text,
      asOperator: asOperator,
      beginAt: widget.programInfo.beginAt,
      maxLength: maxLength,
      isAnonymous: isAnonymous,
    );
    if (!mounted) {
      return result;
    }
    _showCommentPostFeedback(result, asOperator: asOperator);
    return result;
  }

  void _showCommentPostFeedback(
    CommentSendResult result, {
    required bool asOperator,
  }) {
    // Silently ignore duplicate submissions — the send button is already
    // disabled while a post is in flight, and showing a snackbar for this
    // case would be more confusing than helpful.
    if (result.validationError == CommentValidationError.inFlight) {
      return;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    // Hide only the currently-shown snackbar (not the queue) so that an
    // adjacent NG-protection snackbar from the merged main-side feature
    // is not silently dropped when a comment post completes.
    messenger.hideCurrentSnackBar();

    if (result.isSuccess) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('comment-post-success-snackbar'),
          content: Text(asOperator ? '運営コメントを送信しました' : 'コメントを送信しました'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final String message = _commentPostErrorMessage(result);
    messenger.showSnackBar(
      SnackBar(
        key: const Key('comment-post-error-snackbar'),
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _commentPostErrorMessage(CommentSendResult result) {
    final CommentValidationError? validation = result.validationError;
    if (validation != null) {
      switch (validation) {
        case CommentValidationError.empty:
          return 'コメントを入力してください';
        case CommentValidationError.tooLong:
          return '文字数が上限を超えています';
        case CommentValidationError.missingSession:
          return 'ログインが必要です';
        case CommentValidationError.missingProgram:
          return '番組情報が取得できません';
        case CommentValidationError.inFlight:
          // Unreachable in the UI because the send button is disabled while
          // sending; included for switch exhaustiveness.
          return '送信中です';
      }
    }
    final CommentPostResult? post = result.postResult;
    if (post == null) {
      return 'コメントの送信に失敗しました';
    }
    switch (post.errorCode) {
      case CommentPostErrorCode.invalidParams:
      case CommentPostErrorCode.unauthorized:
        return 'ログインが必要です';
      case CommentPostErrorCode.forbidden:
        return 'コメントの投稿権限がありません';
      case CommentPostErrorCode.notFound:
        return '番組が見つかりません';
      case CommentPostErrorCode.conflict:
        return '放送は終了しています';
      case CommentPostErrorCode.rateLimited:
        return 'しばらく待ってから再送信してください';
      case CommentPostErrorCode.networkError:
        return 'ネットワークエラーが発生しました';
      default:
        return 'コメントの送信に失敗しました';
    }
  }

  /// Announces NG-filter protection for comments appended since the last
  /// call. The badge counter always increases on every NG hit, while the
  /// snackbar is throttled to at most one per [_protectionSnackBarWindow].
  ///
  /// No-op when [CommentFilterConfig.ngProtectionNotificationEnabled] is
  /// false (existing silent behavior is preserved).
  void _processNgProtectionNotifications(List<AppMessage> newMessages) {
    if (!widget.filterConfig.ngProtectionNotificationEnabled) {
      // Keep the cursor advancing so that toggling ON later does not
      // retroactively announce historical NG hits.
      if (newMessages.isNotEmpty) {
        _lastProtectionInspectedMessageId = newMessages.last.id;
      }
      return;
    }

    // Locate the slice of messages appended since we last inspected.
    //
    // The message list behaves as a ring buffer at the data layer: when it
    // fills up, the oldest messages are dropped. If the cursor ID can no
    // longer be found in [newMessages] (it was evicted during rotation),
    // we fall back to inspecting the full tail so that NG hits occurring
    // while the buffer rotated are still announced. This trades off a
    // possible one-shot over-count for never silently losing a hit.
    int start = 0;
    final String? cursor = _lastProtectionInspectedMessageId;
    if (cursor != null && newMessages.isNotEmpty) {
      bool found = false;
      for (int i = newMessages.length - 1; i >= 0; i--) {
        if (newMessages[i].id == cursor) {
          start = i + 1;
          found = true;
          break;
        }
      }
      if (!found) {
        // Cursor rotated out of the ring buffer — process the full tail so
        // that we do not silently swallow NG hits during eviction.
        start = 0;
      }
    }

    int newHits = 0;
    String? latestSnackBarMessage;
    for (int i = start; i < newMessages.length; i++) {
      final AppMessage message = newMessages[i];
      switch (message.type) {
        case AppMessageType.gift:
        case AppMessageType.nicoad:
          continue;
        case AppMessageType.chat:
        case AppMessageType.operator:
        case AppMessageType.notification:
        case AppMessageType.system:
        case AppMessageType.emotion:
          break;
      }
      if (_isSystemBroadcastEndedMessage(message)) {
        continue;
      }

      final String? userId = message.userId;
      final bool isNgUser =
          userId != null && widget.filterConfig.ngUserIds.contains(userId);
      final String? matchedWord = _matchedNgWord(message.content);
      if (!isNgUser && matchedWord == null) {
        continue;
      }

      newHits += 1;
      // NG word takes priority when both match (design note: more actionable
      // for the broadcaster than a userId string).
      if (matchedWord != null) {
        latestSnackBarMessage = _buildNgWordProtectionMessage(matchedWord);
      } else {
        latestSnackBarMessage = _buildNgUserProtectionMessage(message);
      }
    }

    if (newMessages.isNotEmpty) {
      _lastProtectionInspectedMessageId = newMessages.last.id;
    }

    if (newHits == 0) {
      return;
    }

    final DateTime now = DateTime.now();
    final DateTime? last = _lastProtectionNotificationAt;
    // Guard against wall-clock skew (NTP sync, manual clock change): if
    // [elapsed] is negative the throttle window would otherwise stay closed
    // indefinitely. Treat a backwards clock as "fire now and reset".
    final bool windowElapsed;
    if (last == null) {
      windowElapsed = true;
    } else {
      final Duration elapsed = now.difference(last);
      windowElapsed =
          elapsed.isNegative || elapsed >= _protectionSnackBarWindow;
    }

    setState(() {
      _protectedCount += newHits;
    });

    if (windowElapsed && latestSnackBarMessage != null) {
      _lastProtectionNotificationAt = now;
      final String snackBarText = latestSnackBarMessage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              content: Row(
                children: <Widget>[
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      snackBarText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
      });
    }
  }

  /// Test-only: rewinds [_lastProtectionNotificationAt] by [offset] so that
  /// the throttle window appears to have elapsed. Exposed via the top-level
  /// [debugRewindProtectionNotificationClock] helper.
  ///
  /// Asserts that the throttle has fired at least once; otherwise calling
  /// this helper is almost certainly a test-ordering bug (the test tried to
  /// rewind a clock that was never started) and a silent no-op would mask
  /// the real issue.
  void _debugRewindProtectionNotificationClock(Duration offset) {
    assert(
      _lastProtectionNotificationAt != null,
      'debugRewindProtectionNotificationClock called before any NG '
      'protection snackbar was fired; rewinding a null timestamp is a '
      'no-op and usually indicates a test-setup mistake.',
    );
    final DateTime? last = _lastProtectionNotificationAt;
    if (last == null) {
      return;
    }
    _lastProtectionNotificationAt = last.subtract(offset);
  }

  /// Returns the matched NG word pattern in [content] (normalized, as used
  /// by [_containsNgWord]), or `null` when nothing matches.
  String? _matchedNgWord(String content) {
    if (_normalizedEffectiveNgWords.isEmpty) {
      return null;
    }
    final String normalizedContent = _normalizeNgWordText(content);
    for (final String word in _normalizedEffectiveNgWords) {
      if (normalizedContent.contains(word)) {
        return word;
      }
    }
    return null;
  }

  String _buildNgWordProtectionMessage(String ngWord) {
    final String sanitized = _sanitizeSingleLine(ngWord);
    if (sanitized.isEmpty) {
      // Fall back to a generic phrase when the NG word sanitizes to the
      // empty string (would otherwise render as "「」を含む..."). This
      // happens when the rule consists only of control/invisible chars.
      return 'コメントを保護しました';
    }
    return '「$sanitized」を含むコメントを保護しました';
  }

  String _buildNgUserProtectionMessage(AppMessage message) {
    final String? resolved = _resolveDisplayName(message);
    final String identifier = (resolved != null && resolved.isNotEmpty)
        ? resolved
        : (message.userId ?? '');
    final String sanitized = _sanitizeSingleLine(identifier);
    if (sanitized.isEmpty) {
      // Fall back to a generic phrase when neither a display name nor a
      // userId is available (would otherwise render as "ユーザー「」の…").
      return 'ユーザーのコメントを保護しました';
    }
    return 'ユーザー「$sanitized」のコメントを保護しました';
  }

  /// Collapses newlines and control characters so the snackbar label does
  /// not break layout if a malformed NG rule or resolved name contains
  /// unexpected whitespace, and strips invisible/bidi-control characters
  /// that could otherwise reorder the snackbar text.
  ///
  /// Truncation is grapheme-cluster aware via [Characters] so that emoji
  /// (including surrogate pairs and ZWJ sequences) are not split mid-codepoint.
  /// Only used for display; does not affect filtering.
  String _sanitizeSingleLine(String value) {
    // Strip C0/C1 controls, zero-width characters, and bidi / tag
    // controls that could otherwise spoof or reorder the snackbar text.
    // All such categories are centralized in [_removeControlAndInvisible].
    final String withoutControls = _removeControlAndInvisible(value);
    final String collapsed = withoutControls
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();
    // Limit length so the snackbar does not overflow on narrow screens.
    // Counting grapheme clusters (user-perceived characters) instead of
    // UTF-16 code units avoids breaking emoji across truncate boundary.
    final Characters chars = Characters(collapsed);
    if (chars.length > 40) {
      return '${chars.take(40)}…';
    }
    return collapsed;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        unawaited(_handleBackNavigation(didPop));
      },
      child: ListenableBuilder(
        listenable: widget.connectionSupervisor,
        builder: (BuildContext context, _) {
          final ConnectionStatus status = widget.connectionSupervisor.status;
          final List<AppMessage> visibleMessages = widget.messages
              .where(_shouldDisplayMessage)
              .toList(growable: false);

          // Apply keyword search filter on top of the NG filter.
          // When not searching or when the query is empty, this is a no-op.
          final List<AppMessage> searchedMessages = _isSearching
              ? visibleMessages
                    .where(_matchesSearchQuery)
                    .toList(growable: false)
              : visibleMessages;

          final List<AppMessage> sortedMessages = _applySortOrder(
            searchedMessages,
          );
          final bool showSearchEmptyState =
              _isSearching &&
              _normalizedSearchQuery.isNotEmpty &&
              searchedMessages.isEmpty;
          final AppThemeMode effectiveMode = AppTheme.resolveEffectiveMode(
            widget.themeMode,
            MediaQuery.platformBrightnessOf(context),
          );
          final AppThemeColors themeColors = AppTheme.colorsFor(effectiveMode);
          // Resolve the current text scaler once per CommentScreen build and
          // forward it to every _CommentRow via a prop. Reading
          // MediaQuery.textScalerOf(context) inside each row would subscribe
          // thousands of list items to the same MediaQuery change
          // notification, causing a storm of rebuilds when the user adjusts
          // OS-level font scaling. Passing it as a prop keeps the
          // accessibility behaviour while letting the ListView.builder
          // recycle rows cheaply.
          final TextScaler textScaler = MediaQuery.textScalerOf(context);

          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 44,
              leading: _isSearching
                  ? IconButton(
                      key: const Key('search-close-button'),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '検索を終了',
                      onPressed: _closeSearch,
                    )
                  : null,
              title: _isSearching
                  ? TextField(
                      key: const Key('comment-search-field'),
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      // Cap the query to a sensible length so users cannot
                      // paste arbitrarily large strings; hide the default
                      // counter since the AppBar has no room for it.
                      maxLength: _kSearchMaxLength,
                      // Reject control characters and bidi override code
                      // points so pasted payloads cannot smuggle hidden
                      // whitespace / direction overrides into the query.
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.deny(
                          RegExp(r'[\x00-\x1F\x7F\u202A-\u202E\u2066-\u2069]'),
                        ),
                      ],
                      style: const TextStyle(fontSize: 15),
                      // Hint uses the subtle color so empty-state text reads
                      // as placeholder, while the caret uses the foreground
                      // text color so focus/caret position stays visible in
                      // both light and dark themes.
                      cursorColor: Theme.of(context).colorScheme.onSurface,
                      decoration: InputDecoration(
                        hintText: 'コメントを検索',
                        hintStyle: TextStyle(
                          color: themeColors.subtleTextColor,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        counterText: '',
                      ),
                    )
                  : Text(
                      widget.programInfo.broadcasterName ??
                          widget.programInfo.lv,
                      key: const Key('appbar-title-text'),
                      style: const TextStyle(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
              actions: _isSearching
                  ? <Widget>[
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          key: const Key('search-clear-button'),
                          icon: const Icon(Icons.close),
                          tooltip: '検索キーワードをクリア',
                          onPressed: _clearSearchQuery,
                        ),
                    ]
                  : <Widget>[
                      if (widget.speechConfig.speechSettings.enabled)
                        _SpeechStatusIcon(
                          key: const Key('speech-status-icon'),
                          engineState: _speechEngineState,
                          isStarted: _speechStarted,
                          isInitialized: _speechInitialized,
                          isMuted: widget.speechConfig.isSpeechMuted,
                          themeColors: themeColors,
                          onTap: widget.callbacks.onSpeechMuteToggled,
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
                      if (widget.filterConfig.ngProtectionNotificationEnabled &&
                          _protectedCount > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Semantics(
                            key: const Key('ng-protection-badge'),
                            label: '保護件数 $_protectedCount 件',
                            container: true,
                            child: ExcludeSemantics(
                              // Prevent Badge.count + Icon from double-announcing
                              // (their semantics are already covered by the
                              // parent Semantics label above).
                              child: Badge.count(
                                count: _protectedCount,
                                // TODO(#244 follow-up): make this tappable to open
                                // a protection-log screen once that feature lands.
                                child: const Icon(Icons.shield_outlined),
                              ),
                            ),
                          ),
                        ),
                      // Consolidate low-frequency actions (search / save-log /
                      // settings) into an overflow menu so the AppBar keeps at
                      // most 3 trailing actions per Material guidance. Only
                      // these three actions are moved here; everything above
                      // stays visible because it conveys state at a glance.
                      _buildOverflowMenuButton(),
                    ],
            ),
            body: Column(
              children: <Widget>[
                if (widget.programInfo.programTitle != null)
                  _ProgramTitleBar(
                    key: const Key('program-title-bar'),
                    title: widget.programInfo.programTitle!,
                    broadcasterIconUrl: widget.programInfo.broadcasterIconUrl,
                    themeColors: themeColors,
                  ),
                _StatusBar(
                  key: const Key('status-bar'),
                  lv: widget.programInfo.lv,
                  supervisor: widget.connectionSupervisor,
                  debugMode: widget.debugMode,
                  connectionMethod: widget.programInfo.connectionMethod,
                  broadcasterName: widget.programInfo.broadcasterName,
                  broadcasterUserId: widget.programInfo.broadcasterUserId,
                  broadcasterIconUrl: widget.programInfo.broadcasterIconUrl,
                  beginAt: widget.programInfo.beginAt,
                  themeColors: themeColors,
                  statisticsEnabled: widget.statistics.enabled,
                  statisticsViewerCommentEnabled:
                      widget.statistics.viewerCommentEnabled,
                  statisticsActiveUserEnabled:
                      widget.statistics.activeUserEnabled,
                  viewerCount: widget.statistics.viewerCount,
                  totalCommentCount: widget.statistics.totalCommentCount,
                  activeUserCount: widget.statistics.activeUserCount,
                ),
                if (_pinnedMessageIds.isNotEmpty)
                  _PinnedCommentsSection(
                    key: const Key('pinned-comments-section'),
                    pinnedMessages: _pinnedMessages(visibleMessages),
                    themeColors: themeColors,
                    showUserName: widget.showUserName,
                    fontSize: widget.commentFontSize,
                    resolveDisplayName: _resolveDisplayName,
                    userColorMap: widget.filterConfig.userColorMap,
                    onUnpin: _unpinMessage,
                    beginAt: widget.programInfo.beginAt,
                    commentTwoLineEnabled: widget.commentTwoLineEnabled,
                  ),
                if (widget.speechConfig.speechSettings.enabled &&
                    widget.speechConfig.isSpeechMuted)
                  _MuteBanner(
                    key: const Key('mute-banner'),
                    themeColors: themeColors,
                    onTap: widget.callbacks.onSpeechMuteToggled,
                  ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      if (showSearchEmptyState)
                        Builder(
                          key: const Key('comment-search-empty'),
                          builder: (BuildContext context) {
                            // Show the user's query in the empty state so they
                            // can confirm what was searched for. Truncate long
                            // queries to keep the AppBar-below area tidy.
                            //
                            // Truncate by grapheme cluster (via the
                            // `characters` package) rather than UTF-16 code
                            // units so we never slice an emoji / surrogate
                            // pair in half and render `\uFFFD`.
                            final String trimmedQuery = _searchQuery.trim();
                            final Characters queryChars =
                                trimmedQuery.characters;
                            final String displayQuery = queryChars.length > 20
                                ? '${queryChars.take(20)}...'
                                : trimmedQuery;
                            final String emptyMessage =
                                '"$displayQuery" は見つかりません';
                            // The visible text keeps the quotes for visual
                            // emphasis, but the Semantics label drops them so
                            // screen readers (e.g. TalkBack) do not literally
                            // announce "double quote".
                            final String semanticsLabel =
                                '検索結果: $displayQuery は見つかりません';
                            return Center(
                              child: Semantics(
                                label: semanticsLabel,
                                child: Text(emptyMessage),
                              ),
                            );
                          },
                        )
                      else
                        Listener(
                          onPointerDown: (_) {
                            _touchActive = true;
                          },
                          onPointerUp: (_) {
                            _touchActive = false;
                            _checkAutoScrollResume();
                          },
                          onPointerCancel: (_) {
                            _touchActive = false;
                            _checkAutoScrollResume();
                          },
                          child: ListView.builder(
                            key: const Key('comment-list'),
                            controller: _scrollController,
                            itemCount: sortedMessages.length,
                            itemBuilder: (BuildContext context, int index) {
                              final AppMessage message = sortedMessages[index];
                              final int? userColor = message.userId != null
                                  ? widget.filterConfig.userColorMap[message
                                        .userId!]
                                  : null;
                              return _CommentRow(
                                message: message,
                                themeColors: themeColors,
                                resolvedUserName: _resolveDisplayName(message),
                                showUserName: widget.showUserName,
                                fontSize: widget.commentFontSize,
                                textScaler: textScaler,
                                starPrefixHidingEnabled:
                                    widget.filterConfig.starPrefixHidingEnabled,
                                commentTwoLineEnabled:
                                    widget.commentTwoLineEnabled,
                                zebraStripingEnabled:
                                    widget.commentZebraStripingEnabled,
                                emphasizeGiftNicoadComment: widget
                                    .filterConfig
                                    .emphasizeGiftNicoadComment,
                                commentIndex: index,
                                userColor: userColor != null
                                    ? colorFromARGB32(userColor)
                                    : null,
                                onLongPress: () => _showCommentActions(message),
                                onOpenUrl: _showUrlConfirmDialog,
                                beginAt: widget.programInfo.beginAt,
                              );
                            },
                          ),
                        ),
                      // Tap-outside-to-close backdrop. Active only while
                      // the input overlay is expanded so regular list taps
                      // (long-press, URL open, etc.) remain unaffected in
                      // the normal state. While a send is in flight the
                      // backdrop does not dismiss the bar — otherwise a
                      // stray tap would tear the expanded UI out from
                      // under an in-progress submission.
                      if (_commentInputExpanded)
                        Positioned.fill(
                          child: GestureDetector(
                            key: const Key('comment-input-backdrop'),
                            behavior: HitTestBehavior.translucent,
                            onTap: _commentInputSending
                                ? null
                                : _collapseCommentInput,
                          ),
                        ),
                      if (!_autoScrollEnabled)
                        Positioned(
                          right: 12,
                          // Raise the scroll-to-latest FAB above the
                          // comment-post FAB when the latter is visible, so
                          // the two do not overlap.
                          bottom: _shouldShowCommentPostFab ? 72 : 12,
                          child: FloatingActionButton.small(
                            key: const Key('scroll-to-latest-button'),
                            onPressed: _scrollToLatest,
                            tooltip: '最新までスクロール',
                            child: Icon(
                              _sortOrder == CommentSortOrder.ascending
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                            ),
                          ),
                        ),
                      if (_shouldShowCommentPostFab)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: CommentPostFab(onPressed: _expandCommentInput),
                        ),
                    ],
                  ),
                ),
                _buildBottomAction(status),
                if (_commentInputExpanded &&
                    widget.commentPostController != null)
                  CommentInputBar(
                    key: const Key('comment-input-bar'),
                    isBroadcaster: _isBroadcaster,
                    onSend: _handleCommentSend,
                    onCollapse: _collapseCommentInput,
                    onSendingChanged: (bool sending) {
                      if (!mounted || _commentInputSending == sending) {
                        return;
                      }
                      setState(() {
                        _commentInputSending = sending;
                      });
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showUserDetail(AppMessage message) {
    final String? userId = message.userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final bool isNg = widget.filterConfig.ngUserIds.contains(userId);
        return UserDetailSheet(
          userId: userId,
          resolvedUserName: _resolveDisplayName(message),
          allMessages: widget.messages,
          isNgUser: isNg,
          themeMode: widget.themeMode,
          beginAt: widget.programInfo.beginAt,
          currentColorValue: widget.filterConfig.userColorMap[userId],
          onColorChanged: widget.callbacks.onUserColorChanged != null
              ? (int colorValue) {
                  widget.callbacks.onUserColorChanged!.call(userId, colorValue);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onColorRemoved: widget.callbacks.onUserColorRemoved != null
              ? () {
                  widget.callbacks.onUserColorRemoved!.call(userId);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          nickname: widget.filterConfig.userNicknameMap[userId],
          onNicknameChanged: widget.callbacks.onNicknameChanged != null
              ? (String nickname) {
                  widget.callbacks.onNicknameChanged!.call(userId, nickname);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onNicknameRemoved: widget.callbacks.onNicknameRemoved != null
              ? () {
                  widget.callbacks.onNicknameRemoved!.call(userId);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onToggleNgUser: () {
            widget.callbacks.onToggleNgUser?.call(userId);
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  void _showCommentActions(AppMessage message) {
    final bool isPinned = _pinnedMessageIds.contains(message.id);
    final bool hasUserId = message.userId != null && message.userId!.isNotEmpty;
    final bool canCopy = message.content.isNotEmpty;

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            key: const Key('comment-actions-sheet'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                key: Key(
                  isPinned
                      ? 'action-unpin-${message.id}'
                      : 'action-pin-${message.id}',
                ),
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(isPinned ? 'ピン留め解除' : 'ピン留め'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (isPinned) {
                    _unpinMessage(message.id);
                  } else {
                    _pinMessage(message.id);
                  }
                },
              ),
              if (canCopy)
                ListTile(
                  key: const Key('action-copy-comment'),
                  leading: const Icon(Icons.copy),
                  title: const Text('コメントをコピー'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_copyCommentToClipboard(message));
                  },
                ),
              if (hasUserId)
                ListTile(
                  key: const Key('action-user-detail'),
                  leading: const Icon(Icons.person),
                  title: const Text('ユーザー詳細'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showUserDetail(message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyCommentToClipboard(AppMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        key: Key('comment-copied-snackbar'),
        content: Text('コメントをコピーしました'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Shows a confirmation dialog before handing a URL off to the OS browser.
  ///
  /// The dialog is the sole entry point through which comment text is allowed
  /// to launch an external browser. Only `http(s)` URLs that pass
  /// [isSafeHttpUrl] are launched, so tapping a comment that happens to
  /// contain `javascript:` or `file:` text never leaves the app.
  Future<void> _showUrlConfirmDialog(AppMessage message) async {
    final List<UrlMatch> matches = findUrls(message.content);
    if (matches.isEmpty) {
      return;
    }

    final String? selected = matches.length == 1
        ? await _confirmSingleUrl(matches.first.url)
        : await _pickUrl(
            matches.map((UrlMatch match) => match.url).toList(growable: false),
          );
    if (selected == null) {
      return;
    }
    if (!isSafeHttpUrl(selected)) {
      return;
    }
    await _launchExternalUrl(selected);
  }

  Future<String?> _confirmSingleUrl(String url) {
    // Parse the host upfront so it can be shown in a larger font than the
    // full URL. Highlighting the host helps users spot spoofed subdomains
    // such as `https://example.com.evil.co.jp/...`.
    final String host = Uri.tryParse(url)?.host ?? '';
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ThemeData theme = Theme.of(dialogContext);
        return AlertDialog(
          key: const Key('url-confirm-dialog'),
          icon: const Icon(Icons.open_in_new),
          title: const Text('外部サイトを開きますか？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('ブラウザでリンクを開きます。接続先のホスト名を確認してください。'),
              const SizedBox(height: 12),
              if (host.isNotEmpty)
                SelectableText(
                  host,
                  key: const Key('url-confirm-host-text'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(height: 4),
              SelectableText(
                url,
                key: const Key('url-confirm-url-text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('url-confirm-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('キャンセル'),
            ),
            TextButton(
              key: const Key('url-confirm-open'),
              onPressed: () => Navigator.of(dialogContext).pop(url),
              child: const Text('開く'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _pickUrl(List<String> urls) {
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          key: const Key('url-picker-dialog'),
          title: const Text('開くリンクを選択'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: urls.length,
              itemBuilder: (BuildContext listContext, int index) {
                final String url = urls[index];
                return ListTile(
                  key: Key('url-picker-option-$index'),
                  dense: true,
                  leading: const Icon(Icons.open_in_browser),
                  title: Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(url),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              key: const Key('url-picker-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchExternalUrl(String url) async {
    bool launched = false;
    final Uri? uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } on Object catch (error, stackTrace) {
        _debugLogLazy(
          () => '[CommentScreen] launchUrl failed: $error\n$stackTrace',
        );
      }
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('url-launch-failed-snackbar'),
          content: Text('リンクを開けませんでした'),
        ),
      );
    }
  }

  void _pinMessage(String messageId) {
    setState(() {
      _pinnedMessageIds.add(messageId);
    });
  }

  void _unpinMessage(String messageId) {
    setState(() {
      _pinnedMessageIds.remove(messageId);
    });
  }

  void _cleanUpStalePinnedIds() {
    final Set<String> currentIds = widget.messages
        .map((AppMessage m) => m.id)
        .toSet();
    _pinnedMessageIds.removeWhere((String id) => !currentIds.contains(id));
  }

  List<AppMessage> _pinnedMessages(List<AppMessage> visibleMessages) {
    return visibleMessages
        .where((AppMessage message) => _pinnedMessageIds.contains(message.id))
        .toList(growable: false);
  }

  /// Resolves the display name for a comment message.
  ///
  /// Priority: nickname (コテハン) > protobuf name > API-resolved name.
  /// Keep in sync with [_resolveSpeechDisplayName] which follows the same
  /// priority chain for TTS output.
  String? _resolveDisplayName(AppMessage message) {
    final String? userId = message.userId;
    // Nickname (コテハン) takes highest priority.
    if (userId != null && userId.isNotEmpty) {
      final String? nickname = widget.filterConfig.userNicknameMap[userId];
      if (nickname != null && nickname.isNotEmpty) {
        return nickname;
      }
    }
    if (message.userName != null && message.userName!.isNotEmpty) {
      return message.userName;
    }
    if (userId == null || userId.isEmpty) {
      return null;
    }
    final String? resolvedName = widget.userNameResolution?.resolve(userId);
    if (resolvedName != null && resolvedName.isNotEmpty) {
      return resolvedName;
    }
    return null;
  }

  /// Resolves the display name for TTS speech output.
  ///
  /// Same priority as [_resolveDisplayName] but returns null when no name
  /// is available (the caller decides what to speak in that case).
  String? _resolveSpeechDisplayName(AppMessage message) {
    final String? userId = message.userId;
    if (userId != null && userId.isNotEmpty) {
      final String? nickname = widget.filterConfig.userNicknameMap[userId];
      if (nickname != null && nickname.isNotEmpty) {
        return nickname;
      }
    }

    final String? userName = message.userName;
    if (userName != null && userName.isNotEmpty) {
      return userName;
    }

    if (userId == null || userId.isEmpty) {
      return null;
    }

    final String? resolvedName = widget.userNameResolution?.resolve(userId);
    if (resolvedName != null && resolvedName.isNotEmpty) {
      return resolvedName;
    }

    return null;
  }

  String _appendSan(String displayName) {
    final String trimmedName = displayName.trim();
    if (trimmedName.isEmpty ||
        trimmedName.endsWith('さん') ||
        trimmedName.endsWith('ちゃん')) {
      return trimmedName;
    }
    return '$trimmedNameさん';
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
              await widget.callbacks.onReconnectSameLv();
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
      await widget.callbacks.onStopAllConnections();
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
    _syncWakelockForStatus(currentStatus);

    if (widget.logConfig.autoSaveCommentLog &&
        _isAutoSaveTrigger(currentStatus)) {
      unawaited(_saveLogAuto());
    }

    if (!_isStoppingForExit && _isStatsTrigger(currentStatus)) {
      _showStatsSheet();
    }

    if (_lastStatus != ConnectionStatus.ended &&
        currentStatus == ConnectionStatus.ended) {
      unawaited(_stopSpeech());
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
    final String compactDetail = detail.isEmpty
        ? '-'
        : _compactSingleLine(detail);

    if (widget.debugMode) {
      final String code = errorCode?.code ?? 'UNKNOWN_ERROR';
      return '$base [code: $code] 原因: $compactDetail 再接続ボタンで再試行できます。';
    }

    final String detailSuffix = detail.isEmpty
        ? ''
        : ' 原因: ${_compactSingleLine(detail)}';
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
    if (nearBottom && !_autoScrollEnabled && !_touchActive) {
      setState(() {
        _autoScrollEnabled = true;
      });
      return;
    }

    if (_autoScrollEnabled &&
        !nearBottom &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.forward) {
      setState(() {
        _autoScrollEnabled = false;
      });
    }
  }

  void _handleScrollDescending() {
    final bool nearTop = _isNearTop();
    if (nearTop && !_autoScrollEnabled && !_touchActive) {
      setState(() {
        _autoScrollEnabled = true;
      });
      return;
    }

    if (_autoScrollEnabled &&
        !nearTop &&
        _scrollController.position.userScrollDirection ==
            ScrollDirection.reverse) {
      setState(() {
        _autoScrollEnabled = false;
      });
    }
  }

  /// Decides whether [message] should be rendered in the comment list.
  ///
  /// Responsibilities (combined here by design):
  ///   * Type-based visibility: system broadcast-ended messages always show,
  ///     and gift / nicoad messages bypass the NG user / NG word filters so
  ///     they are never accidentally silenced by a matching NG word (e.g. an
  ///     advertiser name). Their visual emphasis (shaded background + leading
  ///     icon) is controlled separately by
  ///     `filterConfig.emphasizeGiftNicoadComment` at render time.
  ///   * NG user / NG word filtering for chat / operator / notification.
  ///
  /// NOTE: `AppMessageType.gift` / `.nicoad` are not produced by the current
  /// normalizer pipeline. This branch exists so that when a future protobuf
  /// or legacy path starts emitting those types, gift / nicoad events cannot
  /// be hidden by NG filters. See also `_shouldIncludeInStatsAndLogs`, which
  /// keeps them out of stats and saved comment logs.
  bool _shouldDisplayMessage(AppMessage message) {
    // Type-based visibility toggles (operator / system / emotion /
    // gift / nicoad). When a gift/nicoad toggle is OFF, the message is
    // suppressed entirely from the list. When ON, emphasis styling is
    // separately controlled by `filterConfig.emphasizeGiftNicoadComment`
    // at render time.
    switch (message.type) {
      case AppMessageType.chat:
      case AppMessageType.notification:
        break;
      case AppMessageType.gift:
        if (!widget.filterConfig.showGiftComment) {
          return false;
        }
        break;
      case AppMessageType.nicoad:
        if (!widget.filterConfig.showNicoadComment) {
          return false;
        }
        break;
      case AppMessageType.operator:
        if (!widget.filterConfig.showOperatorComment) {
          return false;
        }
        break;
      case AppMessageType.system:
        if (!widget.filterConfig.showSystemMessage) {
          return false;
        }
        break;
      case AppMessageType.emotion:
        if (!widget.filterConfig.showEmotion) {
          return false;
        }
        break;
    }

    if (_isSystemBroadcastEndedMessage(message)) {
      return true;
    }

    // gift / nicoad bypass NG user / NG word filters so that important
    // monetization events are not accidentally hidden. Issue #108 is a
    // single "emphasize ON/OFF" toggle; a dedicated show/hide toggle is
    // intentionally out of scope.
    //
    // TODO(follow-up): 将来 protobuf/legacy 由来の AppMessageType が user payload
    // によって偽装される攻撃面を想定し、NG バイパス条件に「type の由来保証」
    // (例: raw フィールドの metadata 検証、userId === null など) を追加する。
    if (message.type == AppMessageType.gift ||
        message.type == AppMessageType.nicoad) {
      return true;
    }

    final String? userId = message.userId;
    if (userId != null && widget.filterConfig.ngUserIds.contains(userId)) {
      return false;
    }

    if (_containsNgWord(message.content)) {
      return false;
    }

    return true;
  }

  // ---- AppBar overflow menu ----

  /// Build the AppBar overflow menu that groups low-frequency actions
  /// (search / save-log / settings). Extracted from the main [build] method
  /// to keep the AppBar `actions` list readable; behavior is identical to an
  /// inline `PopupMenuButton` and stays bound to this State so that
  /// `_isSavingLog` / `setState` interactions remain local.
  Widget _buildOverflowMenuButton() {
    return PopupMenuButton<_AppBarMenuAction>(
      key: const Key('appbar-overflow-menu'),
      icon: const Icon(Icons.more_vert),
      tooltip: 'メニュー',
      onSelected: (_AppBarMenuAction action) {
        switch (action) {
          case _AppBarMenuAction.search:
            _openSearch();
          case _AppBarMenuAction.saveLog:
            // `enabled: !_isSavingLog` on the menu item already prevents a
            // disabled tap from reaching here; the guard is a belt-and-
            // suspenders check in case the underlying material state
            // flips between menu open and selection.
            if (!_isSavingLog) {
              unawaited(_saveLogManual());
            }
          case _AppBarMenuAction.settings:
            final Future<void> Function()? onOpen =
                widget.callbacks.onOpenSettings;
            if (onOpen != null) {
              unawaited(onOpen());
            }
        }
      },
      itemBuilder: (BuildContext context) {
        final bool hasLogWriter = widget.logConfig.commentLogWriter != null;
        final bool hasSettings = widget.callbacks.onOpenSettings != null;
        // Only insert a divider between action-group items (search /
        // save-log) and the navigation item (settings) when settings is
        // visible. Search is always present, so the divider never becomes
        // the first entry of the menu.
        final bool showDividerBeforeSettings = hasSettings;
        return <PopupMenuEntry<_AppBarMenuAction>>[
          PopupMenuItem<_AppBarMenuAction>(
            key: const Key('comment-search-button'),
            value: _AppBarMenuAction.search,
            child: const _OverflowMenuRow(icon: Icons.search, label: 'コメントを検索'),
          ),
          if (hasLogWriter)
            PopupMenuItem<_AppBarMenuAction>(
              key: const Key('save-comment-log-button'),
              value: _AppBarMenuAction.saveLog,
              enabled: !_isSavingLog,
              child: _OverflowMenuRow(
                icon: Icons.archive_outlined,
                label: 'コメントログを保存',
                enabled: !_isSavingLog,
              ),
            ),
          if (showDividerBeforeSettings) const PopupMenuDivider(),
          if (hasSettings)
            PopupMenuItem<_AppBarMenuAction>(
              key: const Key('settings-button'),
              value: _AppBarMenuAction.settings,
              child: const _OverflowMenuRow(icon: Icons.settings, label: '設定'),
            ),
        ];
      },
    );
  }

  // ---- Keyword search ----

  void _openSearch() {
    // The TextField uses `autofocus: true`, so we rely on that to raise the
    // keyboard instead of manually calling requestFocus after the frame.
    setState(() {
      _isSearching = true;
    });
  }

  void _closeSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _normalizedSearchQuery = '';
      // Leaving search should re-arm live-tail so any subsequent new comment
      // pulls the list back to the newest message. We deliberately do NOT
      // force a jump-to-end here: if the user scrolled up during search to
      // read older context, respecting their current position matters more
      // than snapping to the tail. The existing auto-scroll logic will
      // catch up naturally on the next incoming message.
      _autoScrollEnabled = true;
    });
  }

  void _clearSearchQuery() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    // Explicitly sync state here so the clear (x) button in the AppBar `actions`
    // disappears in the same frame as the text being cleared. Relying only on
    // the TextEditingController listener risks a one-frame flash because the
    // listener fires after the current build completes.
    setState(() {
      _searchQuery = '';
      _normalizedSearchQuery = '';
    });
  }

  void _handleSearchTextChanged() {
    final String next = _searchController.text;
    if (next == _searchQuery) {
      return;
    }
    // Sync `_searchQuery` inside setState so the AppBar `actions` (e.g. the
    // clear-x button that is conditional on `_searchQuery.isNotEmpty`) update
    // in the same frame as the text itself. The heavier normalized-query
    // update stays inside the debounced timer below so rapid typing does not
    // trigger O(N) filter work on every keystroke.
    setState(() {
      _searchQuery = next;
    });
    // Debounce the actual filter recomputation. 150ms feels instantaneous
    // to users while collapsing bursts of input into a single rebuild.
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _normalizedSearchQuery = _searchQuery.trim().toLowerCase();
      });
    });
  }

  /// Returns true when [message] matches the active search query.
  ///
  /// Matching is case-insensitive and applied to the comment body
  /// (`content`) only. When the query is empty, all messages match.
  ///
  /// Uses the pre-normalized [_normalizedSearchQuery] to avoid recomputing
  /// `trim().toLowerCase()` on every message during list rebuilds.
  bool _matchesSearchQuery(AppMessage message) {
    if (_normalizedSearchQuery.isEmpty) {
      return true;
    }
    return message.content.toLowerCase().contains(_normalizedSearchQuery);
  }

  bool _hasNewMessages(List<AppMessage> previous, List<AppMessage> current) {
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

    final double distanceToBottom =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    return distanceToBottom <= _autoScrollResumeThreshold;
  }

  bool _isNearTop() {
    if (!_scrollController.hasClients) {
      return true;
    }

    return _scrollController.position.pixels <= _autoScrollResumeThreshold;
  }

  Future<void> _loadPresetNgWordsFromAsset() async {
    try {
      final String jsonText = await rootBundle.loadString(
        'android/app/src/main/assets/preset_ng_words.json',
      );
      final Object decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final Object? categoriesObject = decoded['categories'];
      if (categoriesObject is! Map<String, dynamic>) {
        return;
      }
      final List<String> words = <String>[];
      for (final Object? categoryObject in categoriesObject.values) {
        if (categoryObject is! Map<String, dynamic>) {
          continue;
        }
        final Object? wordsObject = categoryObject['words'];
        if (wordsObject is! List<dynamic>) {
          continue;
        }
        for (final Object? wordObject in wordsObject) {
          if (wordObject is String && wordObject.trim().isNotEmpty) {
            words.add(wordObject.trim());
          }
        }
      }
      if (!mounted || widget.filterConfig.presetNgWords.isNotEmpty) {
        return;
      }
      _effectivePresetNgWords = words;
      _refreshNormalizedNgWords();
      setState(() {});
    } catch (_) {
      // Keep empty preset list when asset is unavailable (e.g. tests without bundle).
    }
  }

  void _refreshNormalizedNgWords() {
    final List<String> source = <String>[
      ..._effectivePresetNgWords,
      ...widget.filterConfig.ngWords,
    ];
    final List<String> normalized = source
        .where((String word) => word.trim().isNotEmpty)
        .map(_normalizeNgWordText)
        .where((String word) => word.isNotEmpty)
        .toSet()
        .toList(growable: false);
    _normalizedEffectiveNgWords = normalized;
  }

  bool _listEqualsShallow(List<String> a, List<String> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  String _normalizeNgWordText(String text) {
    String result = text;
    result = _normalizeFullWidthAscii(result);
    result = _normalizeHalfWidthKatakana(result);
    result = _removeControlAndInvisible(result);
    result = _applyLookAlikeTable(result);
    result = _katakanaToHiragana(result);
    result = result.toLowerCase();
    result = _removeSpacesAndSymbols(result);
    result = _compressDuplicates(result);
    return result;
  }

  String _normalizeFullWidthAscii(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      if (cp == 0x3000) {
        sb.write(' ');
      } else if (cp >= 0xFF10 && cp <= 0xFF19) {
        sb.writeCharCode(cp - 0xFEE0);
      } else if (cp >= 0xFF21 && cp <= 0xFF3A) {
        sb.writeCharCode(cp - 0xFEE0);
      } else if (cp >= 0xFF41 && cp <= 0xFF5A) {
        sb.writeCharCode(cp - 0xFEE0);
      } else {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  String _normalizeHalfWidthKatakana(String text) {
    if (text.isEmpty) {
      return text;
    }
    const Map<String, String> map = <String, String>{
      'ｱ': 'ア',
      'ｲ': 'イ',
      'ｳ': 'ウ',
      'ｴ': 'エ',
      'ｵ': 'オ',
      'ｶ': 'カ',
      'ｷ': 'キ',
      'ｸ': 'ク',
      'ｹ': 'ケ',
      'ｺ': 'コ',
      'ｻ': 'サ',
      'ｼ': 'シ',
      'ｽ': 'ス',
      'ｾ': 'セ',
      'ｿ': 'ソ',
      'ﾀ': 'タ',
      'ﾁ': 'チ',
      'ﾂ': 'ツ',
      'ﾃ': 'テ',
      'ﾄ': 'ト',
      'ﾅ': 'ナ',
      'ﾆ': 'ニ',
      'ﾇ': 'ヌ',
      'ﾈ': 'ネ',
      'ﾉ': 'ノ',
      'ﾊ': 'ハ',
      'ﾋ': 'ヒ',
      'ﾌ': 'フ',
      'ﾍ': 'ヘ',
      'ﾎ': 'ホ',
      'ﾏ': 'マ',
      'ﾐ': 'ミ',
      'ﾑ': 'ム',
      'ﾒ': 'メ',
      'ﾓ': 'モ',
      'ﾔ': 'ヤ',
      'ﾕ': 'ユ',
      'ﾖ': 'ヨ',
      'ﾗ': 'ラ',
      'ﾘ': 'リ',
      'ﾙ': 'ル',
      'ﾚ': 'レ',
      'ﾛ': 'ロ',
      'ﾜ': 'ワ',
      'ｦ': 'ヲ',
      'ﾝ': 'ン',
      'ｧ': 'ァ',
      'ｨ': 'ィ',
      'ｩ': 'ゥ',
      'ｪ': 'ェ',
      'ｫ': 'ォ',
      'ｯ': 'ッ',
      'ｬ': 'ャ',
      'ｭ': 'ュ',
      'ｮ': 'ョ',
      'ｰ': 'ー',
    };
    const Map<String, String> voiced = <String, String>{
      'ｳ': 'ヴ',
      'ｶ': 'ガ',
      'ｷ': 'ギ',
      'ｸ': 'グ',
      'ｹ': 'ゲ',
      'ｺ': 'ゴ',
      'ｻ': 'ザ',
      'ｼ': 'ジ',
      'ｽ': 'ズ',
      'ｾ': 'ゼ',
      'ｿ': 'ゾ',
      'ﾀ': 'ダ',
      'ﾁ': 'ヂ',
      'ﾂ': 'ヅ',
      'ﾃ': 'デ',
      'ﾄ': 'ド',
      'ﾊ': 'バ',
      'ﾋ': 'ビ',
      'ﾌ': 'ブ',
      'ﾍ': 'ベ',
      'ﾎ': 'ボ',
      'ﾜ': 'ヷ',
      'ｦ': 'ヺ',
    };
    const Map<String, String> semiVoiced = <String, String>{
      'ﾊ': 'パ',
      'ﾋ': 'ピ',
      'ﾌ': 'プ',
      'ﾍ': 'ペ',
      'ﾎ': 'ポ',
    };
    final List<String> chars = text.split('');
    final StringBuffer sb = StringBuffer();
    int i = 0;
    while (i < chars.length) {
      final String ch = chars[i];
      final String? next = i + 1 < chars.length ? chars[i + 1] : null;
      if (next == 'ﾞ') {
        final String? combined = voiced[ch];
        if (combined != null) {
          sb.write(combined);
          i += 2;
          continue;
        }
      } else if (next == 'ﾟ') {
        final String? combined = semiVoiced[ch];
        if (combined != null) {
          sb.write(combined);
          i += 2;
          continue;
        }
      }
      sb.write(map[ch] ?? ch);
      i++;
    }
    return sb.toString();
  }

  /// Strips characters that would corrupt UI rendering or allow spoofing
  /// of displayed text, while preserving characters that are semantically
  /// part of user-perceived glyphs.
  ///
  /// Removed:
  ///  - C0 / C1 control characters (except space)
  ///  - Zero-width joiners that are *not* ZWJ (U+200B, U+200C, U+FEFF, U+00AD)
  ///  - Bidi override / isolate controls that could reorder display text:
  ///    - U+061C (Arabic Letter Mark)
  ///    - U+180E (Mongolian Vowel Separator)
  ///    - U+202A-U+202E (LRE/RLE/PDF/LRO/RLO)
  ///    - U+2066-U+2069 (LRI/RLI/FSI/PDI)
  ///    - U+E0000-U+E007F (Tag Characters; Trojan Source defense)
  ///
  /// Preserved:
  ///  - ZWJ (U+200D): required to keep ZWJ-composed emoji sequences
  ///    (family, profession, flag, etc.) as a single glyph in display.
  ///  - Variation selectors (U+FE00-U+FE0F, U+E0100-U+E01EF): required
  ///    to keep emoji presentation selectors intact.
  String _removeControlAndInvisible(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      final bool invisible =
          cp == 0x200B ||
          cp == 0x200C ||
          cp == 0xFEFF ||
          cp == 0x00AD ||
          cp == 0x061C ||
          cp == 0x180E ||
          (cp >= 0x202A && cp <= 0x202E) ||
          (cp >= 0x2066 && cp <= 0x2069) ||
          (cp >= 0xE0000 && cp <= 0xE007F) ||
          ((cp >= 0x0000 && cp <= 0x001F) && cp != 0x0020) ||
          (cp >= 0x007F && cp <= 0x009F);
      if (!invisible) {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  String _applyLookAlikeTable(String text) {
    const Map<String, String> lookAlike = <String, String>{
      '工': 'エ',
      '口': 'ロ',
      '冂': 'ロ',
      '力': 'カ',
      '夕': 'タ',
      '二': 'ニ',
      '卜': 'ト',
      '八': 'ハ',
      '千': 'チ',
      '十': 'ジ',
      '人': 'ヒ',
      '入': 'イ',
      '匕': 'ヒ',
      '乃': 'ノ',
      '又': 'マ',
      '丁': 'テ',
      '己': 'コ',
      '匚': 'コ',
      '巳': 'ミ',
      '也': 'ヤ',
      '刀': 'カ',
    };
    return text.split('').map((String ch) => lookAlike[ch] ?? ch).join();
  }

  String _katakanaToHiragana(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      if (cp >= 0x30A1 && cp <= 0x30F6) {
        sb.writeCharCode(cp - 0x60);
      } else if (cp == 0x30F7) {
        sb.write('わ');
      } else if (cp == 0x30F8) {
        sb.write('ゐ');
      } else if (cp == 0x30F9) {
        sb.write('ゑ');
      } else if (cp == 0x30FA) {
        sb.write('を');
      } else {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  String _removeSpacesAndSymbols(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      if (_isLetterOrDigitCodePoint(cp)) {
        sb.writeCharCode(cp);
      }
    }
    return sb.toString();
  }

  bool _isLetterOrDigitCodePoint(int cp) {
    final bool asciiAlphaNum =
        (cp >= 0x30 && cp <= 0x39) ||
        (cp >= 0x41 && cp <= 0x5A) ||
        (cp >= 0x61 && cp <= 0x7A);
    if (asciiAlphaNum) {
      return true;
    }
    final bool fullWidthAlphaNum =
        (cp >= 0xFF10 && cp <= 0xFF19) ||
        (cp >= 0xFF21 && cp <= 0xFF3A) ||
        (cp >= 0xFF41 && cp <= 0xFF5A);
    if (fullWidthAlphaNum) {
      return true;
    }
    final bool jpLetters = (cp >= 0x3040 && cp <= 0x30FF);
    if (jpLetters) {
      return true;
    }
    final bool cjk = (cp >= 0x3400 && cp <= 0x9FFF);
    return cjk;
  }

  String _compressDuplicates(String text) {
    if (text.length < 3) {
      return text;
    }
    final List<int> codePoints = text.runes.toList(growable: false);
    if (codePoints.length < 3) {
      return text;
    }
    final StringBuffer sb = StringBuffer();
    int i = 0;
    while (i < codePoints.length) {
      final int cp = codePoints[i];
      int count = 1;
      int j = i + 1;
      while (j < codePoints.length && codePoints[j] == cp) {
        count++;
        j++;
      }
      final int output = count > 2 ? 2 : count;
      for (int k = 0; k < output; k++) {
        sb.writeCharCode(cp);
      }
      i = j;
    }
    return sb.toString();
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

  bool _isStatsTrigger(ConnectionStatus status) {
    if (_lastStatus == status) {
      return false;
    }
    switch (status) {
      case ConnectionStatus.stopped:
      case ConnectionStatus.ended:
        return true;
      case ConnectionStatus.idle:
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
      case ConnectionStatus.failed:
        return false;
    }
  }

  void _syncWakelockForStatus(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connectingSessionWs:
      case ConnectionStatus.resolvingEndpoints:
      case ConnectionStatus.streamingNdgr:
      case ConnectionStatus.streamingLegacy:
      case ConnectionStatus.reconnecting:
        _stopWakelockReleaseTimer();
        unawaited(WakelockPlus.enable());
        break;
      case ConnectionStatus.ended:
        _scheduleWakelockRelease();
        break;
      case ConnectionStatus.idle:
      case ConnectionStatus.stopped:
      case ConnectionStatus.failed:
        _stopWakelockReleaseTimer();
        break;
    }
  }

  void _scheduleWakelockRelease() {
    if (_wakelockReleaseTimer?.isActive ?? false) {
      return;
    }

    _wakelockReleaseTimer = Timer(_wakelockReleaseDelay, () {
      _wakelockReleaseTimer = null;
      if (!mounted ||
          widget.connectionSupervisor.status != ConnectionStatus.ended) {
        return;
      }
      unawaited(WakelockPlus.disable());
    });
  }

  void _stopWakelockReleaseTimer() {
    _wakelockReleaseTimer?.cancel();
    _wakelockReleaseTimer = null;
  }

  void _showStatsSheet() {
    final List<AppMessage> messagesForStatsAndLogs = _messagesForStatsAndLogs();
    final bool hasMessages = messagesForStatsAndLogs.isNotEmpty;
    if (!hasMessages) {
      return;
    }

    final CommentLogStats stats = CommentLogStats.fromMessages(
      messagesForStatsAndLogs,
      ngUserIds: widget.filterConfig.ngUserIds,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext sheetContext) {
          return CommentLogStatsSheet(
            stats: stats,
            themeMode: widget.themeMode,
            programTitle: widget.programInfo.programTitle,
            lv: widget.programInfo.lv,
            highlightPickupEnabled: widget.statistics.highlightPickupEnabled,
            messages: messagesForStatsAndLogs,
            ngUserIds: widget.filterConfig.ngUserIds,
            onBarTapped: (int minuteOffset) {
              Navigator.of(sheetContext).pop();
              _scrollToMinuteOffset(minuteOffset);
            },
            onPeakTapped: (int minuteOffset) {
              Navigator.of(sheetContext).pop();
              _scrollToMinuteOffset(minuteOffset);
            },
          );
        },
      );
    });
  }

  void _scrollToMinuteOffset(int minuteOffset) {
    final List<AppMessage> visibleMessages = widget.messages
        .where(_shouldDisplayMessage)
        .toList(growable: false);
    final List<AppMessage> sorted = _applySortOrder(visibleMessages);
    if (sorted.isEmpty) {
      return;
    }

    // Use the first message in chronological order (before sorting).
    final DateTime first = visibleMessages.first.timestamp;

    int targetIndex = -1;
    for (int i = 0; i < sorted.length; i++) {
      final int minute = sorted[i].timestamp.difference(first).inMinutes;
      if (minute >= minuteOffset) {
        targetIndex = i;
        break;
      }
    }

    if (targetIndex < 0) {
      return;
    }

    if (!_scrollController.hasClients) {
      return;
    }

    // Estimate position: each comment row is roughly commentFontSize * 2.5.
    final double estimatedRowHeight = widget.commentFontSize * 2.5;
    final double targetOffset = (targetIndex * estimatedRowHeight).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _saveLogManual() async {
    final List<AppMessage> messagesForStatsAndLogs = _messagesForStatsAndLogs();
    final bool hasMessages = messagesForStatsAndLogs.isNotEmpty;
    if (!hasMessages) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('保存するコメントがありません')));
      }
      return;
    }

    final CommentLogWriter? writer = widget.logConfig.commentLogWriter;
    if (writer == null) {
      return;
    }

    setState(() {
      _isSavingLog = true;
    });

    try {
      final String? tempPath = await writer.writeToTempFile(
        lv: widget.programInfo.lv,
        messages: messagesForStatsAndLogs,
      );
      if (tempPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(content: Text('コメントログの保存に失敗しました')));
        }
        return;
      }

      if (mounted) {
        final String fileName = tempPath.split('/').last;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text('コメントログを保存しました: $fileName')));
      }
      await SharePlus.instance.share(
        ShareParams(files: <XFile>[XFile(tempPath)]),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLog = false;
        });
      }
    }
  }

  Future<void> _saveLogAuto() async {
    final CommentLogWriter? writer = widget.logConfig.commentLogWriter;
    if (writer == null) {
      return;
    }

    final List<AppMessage> messagesForStatsAndLogs = _messagesForStatsAndLogs();

    final Directory? customDir =
        widget.logConfig.autoSaveCommentLogPath.isNotEmpty
        ? Directory(widget.logConfig.autoSaveCommentLogPath)
        : null;

    String? savedPath;
    try {
      savedPath = await writer.save(
        lv: widget.programInfo.lv,
        messages: messagesForStatsAndLogs,
        customDirectory: customDir,
      );
    } on Object {
      // savedPath remains null; fall through to error notification.
    }

    if (!mounted) {
      return;
    }

    if (savedPath != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('コメントログを保存しました: $savedPath')));
    } else if (messagesForStatsAndLogs.isNotEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('コメントログの自動保存に失敗しました')));
    }
  }

  bool _isSystemBroadcastEndedMessage(AppMessage message) {
    return message.id.startsWith(kSystemBroadcastEndedMessageIdPrefix);
  }

  List<AppMessage> _messagesForStatsAndLogs() {
    return widget.messages
        .where(_shouldIncludeInStatsAndLogs)
        .toList(growable: false);
  }

  /// Decides whether [message] contributes to in-app statistics and to the
  /// saved / shared comment log file.
  ///
  /// This is a stats/log-only predicate that is intentionally independent
  /// from [_shouldDisplayMessage] so that UI-facing display rules cannot
  /// accidentally leak into stats / persisted logs.
  ///
  /// Evaluation order (the order is load-bearing — see notes below):
  ///   1. system broadcast-ended system rows are excluded (they are UI
  ///      affordances, not real comments).
  ///   2. gift / nicoad messages are excluded to preserve the documented
  ///      contract of `CommentLogWriter` ("Callers are responsible for
  ///      filtering messages, e.g. excluding gift / nicoad types").
  ///   3. NG user messages are excluded.
  ///   4. NG word messages are excluded (this is stricter than
  ///      `CommentLogStats._filterDisplayable`, which drops only gift /
  ///      nicoad + NG user; the stats sheet recomputes from the same
  ///      underlying list so the stricter filter here is safe).
  ///
  /// Difference from `CommentLogStats._filterDisplayable`:
  ///   * `_filterDisplayable` excludes gift / nicoad and NG user only; it
  ///     does NOT consult the NG word list.
  ///   * This predicate additionally excludes NG word matches so that the
  ///     saved comment log / shared log file never contains content the
  ///     user has explicitly filtered out. Intentional divergence; the
  ///     stats sheet uses its own path and does not rely on this method.
  ///
  /// NOTE: changing step order changes behaviour (e.g. swapping steps 1 and
  /// 2 would not change results, but swapping step 2 with steps 3–4 would
  /// cause gift / nicoad to be checked against NG user / NG word first).
  /// Keep early excludes before NG checks.
  bool _shouldIncludeInStatsAndLogs(AppMessage message) {
    // Step 1: system broadcast-ended rows are UI-only.
    if (_isSystemBroadcastEndedMessage(message)) {
      return false;
    }
    // Step 2: gift / nicoad are never persisted, matching CommentLogWriter's
    // contract. Evaluated before NG checks so that the decision does not
    // depend on NG configuration.
    if (message.type == AppMessageType.gift ||
        message.type == AppMessageType.nicoad) {
      return false;
    }
    // Step 3: NG user.
    final String? userId = message.userId;
    if (userId != null && widget.filterConfig.ngUserIds.contains(userId)) {
      return false;
    }
    // Step 4: NG word. Stricter than `_filterDisplayable`, which does not
    // consider NG words; log / stats use this predicate directly.
    if (_containsNgWord(message.content)) {
      return false;
    }
    return true;
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

  void _scrollToLatest() {
    setState(() {
      _autoScrollEnabled = true;
    });
    _scrollToEdge();
  }

  void _checkAutoScrollResume() {
    if (_autoScrollEnabled) return;
    final bool atEdge = _sortOrder == CommentSortOrder.ascending
        ? _isNearBottom()
        : _isNearTop();
    if (atEdge) {
      setState(() {
        _autoScrollEnabled = true;
      });
    }
  }
}

/// Visual row used inside AppBar overflow menu items. Factored out so the
/// leading-icon + label layout stays consistent across all entries and future
/// menu additions do not diverge.
///
/// Accessibility:
/// - [MergeSemantics] collapses the icon + label into a single semantic node
///   so screen readers announce the item once instead of reading the icon and
///   label as separate children.
/// - [Tooltip] satisfies the issue acceptance criterion of attaching a
///   tooltip to each menu entry (long-press on mobile, hover on desktop) and
///   also contributes an accessible hint on platforms that surface tooltips.
/// - [ExcludeSemantics] around the visual row avoids duplicate announcement
///   of the inner [Text] because the outer [Semantics.label] already carries
///   the spoken label.
class _OverflowMenuRow extends StatelessWidget {
  const _OverflowMenuRow({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Tooltip(
          message: label,
          child: ExcludeSemantics(
            child: Row(
              children: <Widget>[
                Icon(icon),
                const SizedBox(width: 12),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgramTitleBar extends StatelessWidget {
  const _ProgramTitleBar({
    super.key,
    required this.title,
    this.broadcasterIconUrl,
    required this.themeColors,
  });

  final String title;
  final String? broadcasterIconUrl;
  final AppThemeColors themeColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: themeColors.programTitleBarBackground,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: <Widget>[
          if (broadcasterIconUrl != null &&
              broadcasterIconUrl!.isNotEmpty) ...<Widget>[
            _BroadcasterIcon(url: broadcasterIconUrl, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              key: const Key('program-title-text'),
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  const _StatusBar({
    super.key,
    required this.lv,
    required this.supervisor,
    required this.debugMode,
    required this.connectionMethod,
    this.broadcasterName,
    this.broadcasterUserId,
    this.broadcasterIconUrl,
    this.beginAt,
    required this.themeColors,
    this.statisticsEnabled = false,
    this.statisticsViewerCommentEnabled = true,
    this.statisticsActiveUserEnabled = true,
    this.viewerCount,
    this.totalCommentCount = 0,
    this.activeUserCount = 0,
  });

  final String lv;
  final ConnectionSupervisor supervisor;
  final bool debugMode;
  final ConnectionMethod? connectionMethod;
  final String? broadcasterName;
  final String? broadcasterUserId;
  final String? broadcasterIconUrl;
  final DateTime? beginAt;
  final AppThemeColors themeColors;
  final bool statisticsEnabled;
  final bool statisticsViewerCommentEnabled;
  final bool statisticsActiveUserEnabled;
  final int? viewerCount;
  final int totalCommentCount;
  final int activeUserCount;

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  bool _collapsed = false;
  Timer? _autoCollapseTimer;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _autoCollapseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _collapsed = true;
        });
      }
    });
    if (widget.beginAt != null) {
      _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant _StatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beginAt != widget.beginAt) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      if (widget.beginAt != null) {
        _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() {});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String? _elapsedLabel() => formatElapsed(widget.beginAt);

  void _toggle() {
    setState(() {
      _collapsed = !_collapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color wifiColor =
        widget.supervisor.wifiIndicatorColor == WifiIndicatorColor.green
        ? widget.themeColors.statusConnected
        : widget.themeColors.statusDisconnected;

    return Semantics(
      button: true,
      label: _collapsed ? 'ステータスバーを展開' : 'ステータスバーを折りたたみ',
      child: GestureDetector(
        onTap: _toggle,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            color: widget.themeColors.statusBarBackground,
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
                    if (widget.broadcasterName != null) ...<Widget>[
                      if (widget.broadcasterIconUrl != null &&
                          widget.broadcasterIconUrl!.isNotEmpty) ...<Widget>[
                        _BroadcasterIcon(
                          url: widget.broadcasterIconUrl,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          widget.broadcasterName!,
                          key: const Key('status-broadcaster-name'),
                          style: TextStyle(
                            color: widget.themeColors.statusConnected,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        'lv: ${widget.lv}',
                        key: const Key('status-lv'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_elapsedLabel() case final String elapsed) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        elapsed,
                        key: const Key('status-elapsed'),
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.themeColors.subtleTextColor,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 16,
                      color: widget.themeColors.subtleTextColor,
                    ),
                  ],
                ),
                if (!_collapsed) ...<Widget>[
                  if (widget.broadcasterUserId != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '放送者ID: ${widget.broadcasterUserId}',
                      key: const Key('status-broadcaster-user-id'),
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.themeColors.subtleTextColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: <Widget>[
                      Text(
                        '最終受信: ${_formatHmsOrDash(widget.supervisor.lastReceivedAt)}',
                        key: const Key('status-last-received'),
                      ),
                      Text(
                        '再接続: ${widget.supervisor.reconnectCount}回',
                        key: const Key('status-reconnect-count'),
                      ),
                      Text(
                        'エラー: ${_errorLabel(widget.supervisor.lastError)}',
                        key: const Key('status-last-error'),
                      ),
                    ],
                  ),
                  if (widget.statisticsEnabled) ...<Widget>[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: <Widget>[
                        if (widget.statisticsViewerCommentEnabled) ...<Widget>[
                          Text(
                            'リスナー: ${widget.viewerCount ?? '-'}',
                            key: const Key('status-viewer-count'),
                          ),
                          Text(
                            'コメント: ${widget.totalCommentCount}',
                            key: const Key('status-comment-count'),
                          ),
                        ],
                        if (widget.statisticsActiveUserEnabled)
                          Text(
                            '5分アクティブ: ${widget.activeUserCount}',
                            key: const Key('status-active-user-count'),
                          ),
                      ],
                    ),
                  ],
                  if (widget.debugMode) ...<Widget>[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: <Widget>[
                        Text(
                          '方式: ${_connectionMethodLabel(widget.connectionMethod)}',
                          key: const Key('status-connection-method'),
                        ),
                        Text(
                          'フェーズ: ${widget.supervisor.status.code}',
                          key: const Key('status-phase'),
                        ),
                        if ((widget.supervisor.lastErrorDetail ?? '')
                            .isNotEmpty)
                          Text(
                            'エラー詳細: ${widget.supervisor.lastErrorDetail}',
                            key: const Key('status-last-error-detail'),
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
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

class _BroadcasterIcon extends StatelessWidget {
  const _BroadcasterIcon({required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                cacheHeight: (size * 2).round(),
                errorBuilder: (_, _, _) => Icon(Icons.person, size: size),
              )
            : Icon(Icons.person, size: size),
      ),
    );
  }
}

class _PinnedCommentsSection extends StatelessWidget {
  const _PinnedCommentsSection({
    super.key,
    required this.pinnedMessages,
    required this.themeColors,
    required this.showUserName,
    required this.fontSize,
    required this.resolveDisplayName,
    required this.userColorMap,
    required this.onUnpin,
    this.beginAt,
    this.commentTwoLineEnabled = false,
  });

  final List<AppMessage> pinnedMessages;
  final AppThemeColors themeColors;
  final bool showUserName;
  final double fontSize;
  final String? Function(AppMessage) resolveDisplayName;
  final Map<String, int> userColorMap;
  final void Function(String messageId) onUnpin;
  final DateTime? beginAt;
  final bool commentTwoLineEnabled;

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: themeColors.pinnedMessageBackground,
        border: Border(
          bottom: BorderSide(
            color: themeColors.subtleTextColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.push_pin,
                  size: 14,
                  color: themeColors.subtleTextColor,
                ),
                const SizedBox(width: 4),
                Text(
                  'ピン留め',
                  style: TextStyle(
                    fontSize: 12,
                    color: themeColors.subtleTextColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          for (final AppMessage message in pinnedMessages)
            _PinnedCommentRow(
              key: Key('pinned-row-${message.id}'),
              message: message,
              themeColors: themeColors,
              resolvedUserName: resolveDisplayName(message),
              showUserName: showUserName,
              fontSize: fontSize,
              commentTwoLineEnabled: commentTwoLineEnabled,
              userColor:
                  message.userId != null &&
                      userColorMap.containsKey(message.userId!)
                  ? colorFromARGB32(userColorMap[message.userId!]!)
                  : null,
              onUnpin: () => onUnpin(message.id),
              beginAt: beginAt,
            ),
        ],
      ),
    );
  }
}

class _PinnedCommentRow extends StatelessWidget {
  const _PinnedCommentRow({
    super.key,
    required this.message,
    required this.themeColors,
    this.resolvedUserName,
    this.showUserName = true,
    required this.fontSize,
    this.commentTwoLineEnabled = false,
    this.userColor,
    required this.onUnpin,
    this.beginAt,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final bool commentTwoLineEnabled;
  final Color? userColor;
  final VoidCallback onUnpin;
  final DateTime? beginAt;

  @override
  Widget build(BuildContext context) {
    final bool useTwoLine = commentTwoLineEnabled && showUserName;
    // Operator (運営) rows must keep the theme's operator text color even when
    // pinned; the per-user [userColor] is null for operator messages because
    // they normalize with userId=null, which previously caused the red
    // "warning" tone to degrade to the default text color inside the pinned
    // panel.
    final Color? effectiveUserColor = message.type == AppMessageType.operator
        ? themeColors.operatorTextColor
        : userColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: useTwoLine
                ? _buildTwoLinePinned(context)
                : Text(
                    _commentLineText(
                      message: message,
                      showUserName: showUserName,
                      resolvedUserName: resolvedUserName,
                      beginAt: beginAt,
                    ),
                    style: TextStyle(
                      fontSize: fontSize,
                      color: effectiveUserColor,
                    ),
                  ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              key: Key('unpin-button-${message.id}'),
              onPressed: onUnpin,
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(Icons.close, color: themeColors.subtleTextColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a two-line layout for a pinned comment.
  ///
  /// Shares the same font ratio constants as
  /// [_CommentRowState._buildTwoLineComment] but uses a simpler layout
  /// because pinned rows don't support star-prefix hiding or hidden state.
  Widget _buildTwoLinePinned(BuildContext context) {
    final String timestamp = _formatHms(message.timestamp, beginAt: beginAt);
    final double metaFontSize = (fontSize * _twoLineMetaFontRatio).clamp(
      _twoLineMinMetaFontSize,
      fontSize,
    );
    final Color metaColor = themeColors.subtleTextColor;
    // Operator rows use the theme's operator text color (typically red) for
    // the body and the displayName label, matching _CommentRow behavior so
    // the "warning" semantic survives the pin action.
    final Color? effectiveUserColor = message.type == AppMessageType.operator
        ? themeColors.operatorTextColor
        : userColor;

    // Use the shared display-name resolver so operator (運営) rows that
    // normalize with userId=null still render their label.
    final String? displayName = _displayNameForMessage(
      message,
      resolvedUserName: resolvedUserName,
    );

    final List<InlineSpan> metaSpans = <InlineSpan>[
      TextSpan(
        text: timestamp,
        style: TextStyle(fontSize: metaFontSize, color: metaColor),
      ),
    ];
    if (displayName != null) {
      metaSpans.add(
        TextSpan(
          text: '  ',
          style: TextStyle(fontSize: metaFontSize, color: metaColor),
        ),
      );
      metaSpans.add(
        TextSpan(
          text: displayName,
          style: TextStyle(
            fontSize: metaFontSize,
            color: effectiveUserColor ?? metaColor,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(TextSpan(children: metaSpans)),
        const SizedBox(height: 2),
        Text(
          message.content,
          style: TextStyle(fontSize: fontSize, color: effectiveUserColor),
        ),
      ],
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.message,
    required this.themeColors,
    this.resolvedUserName,
    this.showUserName = true,
    required this.fontSize,
    this.textScaler = TextScaler.noScaling,
    this.starPrefixHidingEnabled = false,
    this.commentTwoLineEnabled = false,
    this.zebraStripingEnabled = false,
    this.emphasizeGiftNicoadComment = true,
    this.commentIndex = 0,
    this.userColor,
    this.onLongPress,
    this.onOpenUrl,
    this.beginAt,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;

  /// Forwarded text scaler from the parent. Passed in rather than read from
  /// `MediaQuery.textScalerOf(context)` at build time so that a text scaler
  /// change does not trigger a rebuild of every row in the comment list.
  final TextScaler textScaler;
  final bool starPrefixHidingEnabled;
  final bool commentTwoLineEnabled;
  final bool zebraStripingEnabled;

  /// When true and the message is gift/nicoad, render with a shaded
  /// background and a small leading type icon. When false, gift/nicoad rows
  /// render with the same styling as regular chat messages.
  final bool emphasizeGiftNicoadComment;
  final int commentIndex;
  final Color? userColor;
  final VoidCallback? onLongPress;
  final ValueChanged<AppMessage>? onOpenUrl;
  final DateTime? beginAt;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _revealed = false;

  /// Cached URL matches for [widget.message.content].
  ///
  /// Computed lazily on demand and invalidated whenever the row is recycled
  /// for a different [AppMessage] (tracked via [didUpdateWidget]). Avoiding a
  /// fresh regex scan on every rebuild keeps comment list scrolling cheap,
  /// since [_CommentRow] is rebuilt on every frame when new messages arrive.
  List<UrlMatch>? _cachedUrlMatches;

  bool get _isStarHidden =>
      widget.starPrefixHidingEnabled &&
      widget.message.content.startsWith('☆') &&
      !_revealed;

  List<UrlMatch> _resolveUrlMatches() {
    return _cachedUrlMatches ??= findUrls(widget.message.content);
  }

  @override
  void didUpdateWidget(covariant _CommentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _revealed = false;
      _cachedUrlMatches = null;
    } else if (oldWidget.message.content != widget.message.content) {
      _cachedUrlMatches = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hidden = _isStarHidden;
    // URL detection is skipped for hidden (star-prefixed) comments because
    // the rendered body is the placeholder, not the original text.
    final List<UrlMatch> urlMatches = hidden
        ? const <UrlMatch>[]
        : _resolveUrlMatches();
    final bool hasUrl = urlMatches.isNotEmpty;
    final Color? specialBg = _backgroundColor(widget.message);
    final Color? effectiveBg =
        specialBg ??
        (widget.zebraStripingEnabled && widget.commentIndex.isOdd
            ? Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: _zebraStripingAlpha)
            : null);

    VoidCallback? onTap;
    if (hidden) {
      onTap = () => setState(() => _revealed = true);
    } else if (hasUrl && widget.onOpenUrl != null) {
      onTap = () => widget.onOpenUrl!.call(widget.message);
    }

    return GestureDetector(
      key: Key('comment-row-${widget.message.id}'),
      onLongPress: widget.onLongPress,
      onTap: onTap,
      child: Container(
        color: effectiveBg,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: _buildRichCommentLine(context, hidden, urlMatches),
      ),
    );
  }

  Widget _buildRichCommentLine(
    BuildContext context,
    bool hidden,
    List<UrlMatch> urlMatches,
  ) {
    final AppMessage message = widget.message;
    final String timestamp = _formatHms(
      message.timestamp,
      beginAt: widget.beginAt,
    );
    final String content = hidden ? 'ネタバレ防止: タップで表示' : message.content;
    final double fontSize = widget.fontSize;
    final Color timestampColor = widget.themeColors.subtleTextColor;
    final Color idColor = widget.themeColors.subtleTextColor;
    // Operator (運営) comments are rendered in the theme's operator text color
    // (typically red) regardless of the per-user color, so broadcaster
    // announcements stand out. (Issue #322)
    final Color? effectiveUserColor = message.type == AppMessageType.operator
        ? widget.themeColors.operatorTextColor
        : widget.userColor;
    const double minSubFontSize = 9.0;
    final double timestampFontSize = hidden
        ? fontSize
        : (fontSize * 0.85).clamp(minSubFontSize, fontSize);
    final double idFontSize = hidden
        ? fontSize
        : (fontSize * 0.9).clamp(minSubFontSize, fontSize);

    // Two-line mode is only useful when the username is shown (line 1 holds
    // timestamp + username). When the username column is hidden, the first
    // line would contain only a timestamp, wasting vertical space -- so fall
    // back to single-line rendering.
    if (widget.commentTwoLineEnabled && widget.showUserName) {
      final double twoLineMetaSize = hidden
          ? fontSize
          : (fontSize * _twoLineMetaFontRatio).clamp(
              _twoLineMinMetaFontSize,
              fontSize,
            );
      return _buildTwoLineComment(
        context: context,
        timestamp: timestamp,
        content: content,
        hidden: hidden,
        urlMatches: urlMatches,
        fontSize: fontSize,
        timestampFontSize: twoLineMetaSize,
        idFontSize: twoLineMetaSize,
        timestampColor: timestampColor,
        idColor: idColor,
        effectiveUserColor: effectiveUserColor,
      );
    }

    final List<InlineSpan> spans = <InlineSpan>[];
    final InlineSpan? leadingIconSpan = _buildLeadingTypeIconSpan(
      context,
      fontSize,
    );
    if (leadingIconSpan != null) {
      spans.add(leadingIconSpan);
      spans.add(const TextSpan(text: ' '));
    }
    spans.add(
      TextSpan(
        text: timestamp,
        style: TextStyle(
          fontSize: timestampFontSize,
          color: hidden ? Colors.grey : timestampColor,
          fontStyle: hidden ? FontStyle.italic : null,
        ),
      ),
    );

    if (widget.showUserName) {
      final String? displayName = _displayNameFor(message);
      if (displayName != null) {
        spans.add(const TextSpan(text: '  '));
        spans.add(
          TextSpan(
            text: displayName,
            style: TextStyle(
              fontSize: idFontSize,
              color: hidden ? Colors.grey : (effectiveUserColor ?? idColor),
              fontWeight: hidden ? null : FontWeight.w500,
              fontStyle: hidden ? FontStyle.italic : null,
            ),
          ),
        );
      }
    }

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : effectiveUserColor,
      fontStyle: hidden ? FontStyle.italic : null,
    );

    spans.add(const TextSpan(text: '  '));
    spans.addAll(
      _buildContentSpans(
        context: context,
        content: content,
        urlMatches: urlMatches,
        baseStyle: contentStyle,
      ),
    );

    return Text.rich(TextSpan(children: spans));
  }

  /// Resolves the display name string for the comment-row header.
  ///
  /// Thin instance wrapper around the top-level [_displayNameForMessage];
  /// kept here to preserve the existing call sites inside `_CommentRowState`.
  String? _displayNameFor(AppMessage message) {
    return _displayNameForMessage(
      message,
      resolvedUserName: widget.resolvedUserName,
    );
  }

  /// Builds a [WidgetSpan] rendering the leading type icon for gift / nicoad
  /// messages. Returns `null` when no leading icon should be rendered (either
  /// emphasis is disabled or the message is not gift/nicoad).
  InlineSpan? _buildLeadingTypeIconSpan(BuildContext context, double fontSize) {
    final IconData? iconData = _leadingTypeIcon(widget.message);
    if (iconData == null) {
      return null;
    }
    final Color iconColor =
        widget.userColor ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurface;
    // Icon tracks the chat font size but stays slightly smaller so it reads
    // as a modest type marker rather than dominating the row. The base size
    // is clamped for layout stability, then scaled by the user's text scaler
    // so it remains legible at larger accessibility font settings.
    //
    // The text scaler is forwarded from the parent as a prop (see
    // [_CommentRow.textScaler]) so that a text scaler change notification
    // does not invalidate every row at once.
    final double baseIconSize = (fontSize * 0.95).clamp(10.0, 20.0);
    final double iconSize = widget.textScaler.scale(baseIconSize);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Icon(
        iconData,
        size: iconSize,
        color: iconColor,
        semanticLabel: _semanticLabelForLeadingIcon(widget.message.type),
      ),
    );
  }

  /// Resolves the semantic label for the leading type icon. Using a switch
  /// (rather than a ternary) so that adding a new `AppMessageType` surfaces
  /// a compile-time warning here instead of silently picking the fallback.
  ///
  /// Returning `null` is the documented way to say "this message type does
  /// not show a leading icon, and therefore has no associated semantic
  /// label". Any fallback to `null` for a *new* type is a bug: reviewers
  /// adding a new [AppMessageType] must update this function (and
  /// [_leadingTypeIcon]) to either provide a label or explicitly mark the
  /// type as icon-less. The exhaustive switch above is the enforcement
  /// point — do not introduce a `default` branch.
  String? _semanticLabelForLeadingIcon(AppMessageType type) {
    switch (type) {
      case AppMessageType.gift:
        return 'ギフト';
      case AppMessageType.nicoad:
        return 'ニコニ広告';
      case AppMessageType.chat:
      case AppMessageType.operator:
      case AppMessageType.notification:
      case AppMessageType.system:
      case AppMessageType.emotion:
        return null;
    }
  }

  Widget _buildTwoLineComment({
    required BuildContext context,
    required String timestamp,
    required String content,
    required bool hidden,
    required List<UrlMatch> urlMatches,
    required double fontSize,
    required double timestampFontSize,
    required double idFontSize,
    required Color timestampColor,
    required Color idColor,
    Color? effectiveUserColor,
  }) {
    final List<InlineSpan> metaSpans = <InlineSpan>[];
    final InlineSpan? leadingIconSpan = _buildLeadingTypeIconSpan(
      context,
      timestampFontSize,
    );
    if (leadingIconSpan != null) {
      metaSpans.add(leadingIconSpan);
      metaSpans.add(const TextSpan(text: ' '));
    }
    metaSpans.add(
      TextSpan(
        text: timestamp,
        style: TextStyle(
          fontSize: timestampFontSize,
          color: hidden ? Colors.grey : timestampColor,
          fontStyle: hidden ? FontStyle.italic : null,
        ),
      ),
    );

    if (widget.showUserName) {
      final String? displayName = _displayNameFor(widget.message);
      if (displayName != null) {
        metaSpans.add(const TextSpan(text: '  '));
        metaSpans.add(
          TextSpan(
            text: displayName,
            style: TextStyle(
              fontSize: idFontSize,
              color: hidden ? Colors.grey : (effectiveUserColor ?? idColor),
              fontWeight: hidden ? null : FontWeight.w500,
              fontStyle: hidden ? FontStyle.italic : null,
            ),
          ),
        );
      }
    }

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : effectiveUserColor,
      fontStyle: hidden ? FontStyle.italic : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(TextSpan(children: metaSpans)),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: _buildContentSpans(
              context: context,
              content: content,
              urlMatches: urlMatches,
              baseStyle: contentStyle,
            ),
          ),
        ),
      ],
    );
  }

  /// Splits the comment body into alternating plain-text and URL spans so
  /// that URLs stand out visually while sharing the same base text style.
  ///
  /// When [urlMatches] is empty the result is a single [TextSpan] with the
  /// full content, preserving the previous rendering behavior for non-URL
  /// comments.
  List<InlineSpan> _buildContentSpans({
    required BuildContext context,
    required String content,
    required List<UrlMatch> urlMatches,
    required TextStyle baseStyle,
  }) {
    if (urlMatches.isEmpty) {
      return <InlineSpan>[TextSpan(text: content, style: baseStyle)];
    }
    final Color linkColor = Theme.of(context).colorScheme.primary;
    final TextStyle linkStyle = baseStyle.copyWith(
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final UrlMatch match in urlMatches) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: content.substring(cursor, match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: content.substring(match.start, match.end),
          style: linkStyle,
        ),
      );
      cursor = match.end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor), style: baseStyle));
    }
    return spans;
  }

  Color? _backgroundColor(AppMessage message) {
    if (_isLegacyUnsupportedSystemMessage(message)) {
      return widget.themeColors.notificationMessageBackground;
    }

    if (_isBroadcastEndedMessage(message)) {
      return widget.themeColors.broadcastEndedBackground;
    }

    switch (message.type) {
      case AppMessageType.operator:
        return widget.themeColors.operatorMessageBackground;
      case AppMessageType.notification:
      case AppMessageType.system:
      case AppMessageType.emotion:
        return widget.themeColors.notificationMessageBackground;
      case AppMessageType.gift:
        return _shouldEmphasizeGiftNicoad(
              message,
              emphasize: widget.emphasizeGiftNicoadComment,
            )
            ? widget.themeColors.giftMessageBackground
            : null;
      case AppMessageType.nicoad:
        return _shouldEmphasizeGiftNicoad(
              message,
              emphasize: widget.emphasizeGiftNicoadComment,
            )
            ? widget.themeColors.nicoadMessageBackground
            : null;
      case AppMessageType.chat:
        return null;
    }
  }

  /// Returns the Material icon to render at the start of the row for
  /// gift / nicoad messages when emphasis is enabled. Returns `null` for all
  /// other cases (no leading icon).
  ///
  /// NOTE: this switch intentionally does not provide a `default` branch.
  /// `null` is the documented meaning of "this message type does not have a
  /// leading icon", so any newly added [AppMessageType] will cause a
  /// compile-time warning here, prompting reviewers to decide whether the
  /// new type needs a leading icon rather than silently falling through to
  /// `null`. Reviewers: when extending [AppMessageType], update this
  /// function explicitly.
  IconData? _leadingTypeIcon(AppMessage message) {
    if (!_shouldEmphasizeGiftNicoad(
      message,
      emphasize: widget.emphasizeGiftNicoadComment,
    )) {
      return null;
    }
    switch (message.type) {
      case AppMessageType.gift:
        return Icons.card_giftcard;
      case AppMessageType.nicoad:
        // ニコニ広告は「広告・宣伝」のメタファとしてメガホン (Icons.campaign)
        // を採用。`Icons.monetization_on` は通貨性が強調されすぎるため不採用。
        return Icons.campaign;
      case AppMessageType.chat:
      case AppMessageType.operator:
      case AppMessageType.notification:
      case AppMessageType.system:
      case AppMessageType.emotion:
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

  bool _isBroadcastEndedMessage(AppMessage message) {
    return message.id.startsWith(kSystemBroadcastEndedMessageIdPrefix);
  }
}

class _MuteBanner extends StatelessWidget {
  const _MuteBanner({super.key, required this.themeColors, this.onTap});

  final AppThemeColors themeColors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: themeColors.statusConnected.withAlpha(25),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.volume_off,
              size: 16,
              color: themeColors.statusConnected,
            ),
            const SizedBox(width: 6),
            Text(
              'ミュート中（タップで解除）',
              style: TextStyle(
                fontSize: 12,
                color: themeColors.statusConnected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechStatusIcon extends StatelessWidget {
  const _SpeechStatusIcon({
    super.key,
    required this.engineState,
    required this.isStarted,
    required this.isInitialized,
    required this.isMuted,
    required this.themeColors,
    this.onTap,
  });

  final String engineState;
  final bool isStarted;
  final bool isInitialized;
  final bool isMuted;
  final AppThemeColors themeColors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String tooltip;

    if (!isInitialized) {
      icon = Icons.hourglass_top;
      color = themeColors.subtleTextColor;
      tooltip = '読み上げ: 初期化中';
    } else if (!isStarted) {
      icon = Icons.pause_circle_outline;
      color = themeColors.subtleTextColor;
      tooltip = '読み上げ: 停止中';
    } else if (engineState == 'ERROR') {
      icon = Icons.error_outline;
      color = themeColors.statusDisconnected;
      tooltip = '読み上げ: エラー';
    } else if (isMuted) {
      icon = Icons.volume_off;
      color = themeColors.statusConnected;
      tooltip = 'ミュート解除';
    } else {
      icon = Icons.volume_up;
      color = themeColors.statusConnected;
      tooltip = 'ミュート';
    }

    final bool canToggleMute =
        isInitialized && isStarted && engineState != 'ERROR';

    if (canToggleMute && onTap != null) {
      return Semantics(
        label: isMuted ? '読み上げミュート中' : '読み上げ有効',
        button: true,
        enabled: true,
        child: IconButton(
          icon: Icon(icon, size: 24, color: color),
          tooltip: tooltip,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            onTap!();
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(isMuted ? 'ミュート解除しました' : 'ミュートしました'),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      );
    }

    return Semantics(
      label: tooltip,
      enabled: false,
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Opacity(
            opacity: 0.5,
            child: Icon(icon, size: 24, color: color),
          ),
        ),
      ),
    );
  }
}

/// Test-only helper: rewinds the NG-protection snackbar throttle timestamp
/// of the [CommentScreen] hosting [element] by [offset]. Used to verify the
/// re-fire behavior without sleeping for the full window in wall-clock time.
///
/// Asserts that the throttle has already fired at least once; calling this
/// before the first snackbar is a test-ordering bug rather than a silent
/// no-op.
///
/// In addition to the `@visibleForTesting` static check, this helper is
/// gated on [kDebugMode] at runtime: release builds refuse to run it so
/// that accidental callers cannot manipulate user-visible throttle state
/// in production.
@visibleForTesting
void debugRewindProtectionNotificationClock(Element element, Duration offset) {
  assert(
    kDebugMode,
    'debugRewindProtectionNotificationClock must only be invoked from '
    'tests / debug builds.',
  );
  if (!kDebugMode) {
    return;
  }
  _CommentScreenState? found;
  void visit(Element el) {
    if (found != null) {
      return;
    }
    if (el is StatefulElement && el.state is _CommentScreenState) {
      found = el.state as _CommentScreenState;
      return;
    }
    el.visitChildren(visit);
  }

  if (element is StatefulElement && element.state is _CommentScreenState) {
    found = element.state as _CommentScreenState;
  } else {
    element.visitChildren(visit);
  }
  if (found == null) {
    throw StateError(
      'debugRewindProtectionNotificationClock: no CommentScreen state found under element',
    );
  }
  found!._debugRewindProtectionNotificationClock(offset);
}
