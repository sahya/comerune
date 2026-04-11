import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app_logging.dart';
import '../../application/settings/settings_store.dart';
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

/// Builds a [Text.rich] widget showing timestamp, optional user name, and
/// comment content with per-segment styling.
///
/// Shared by both [_PinnedCommentRow] and [_CommentRow].
Text _buildCommentLineRichText({
  required AppMessage message,
  required bool showUserName,
  required double fontSize,
  required Color timestampColor,
  required Color idColor,
  String? resolvedUserName,
  Color? userColor,
  DateTime? beginAt,
  bool hidden = false,
  bool pinned = false,
}) {
  final String timestamp = _formatHms(message.timestamp, beginAt: beginAt);
  final String content = hidden ? 'ネタバレ防止: タップで表示' : message.content;
  const double minSubFontSize = 9.0;
  final double timestampFontSize =
      hidden || pinned
          ? fontSize
          : (fontSize * 0.85).clamp(minSubFontSize, fontSize);
  final double idFontSize =
      hidden || pinned
          ? fontSize
          : (fontSize * 0.9).clamp(minSubFontSize, fontSize);

  final List<InlineSpan> spans = <InlineSpan>[
    TextSpan(
      text: timestamp,
      style: TextStyle(
        fontSize: timestampFontSize,
        color: hidden ? Colors.grey : timestampColor,
        fontStyle: hidden ? FontStyle.italic : null,
      ),
    ),
  ];

  if (showUserName) {
    final String? userId = message.userId;
    if (userId != null && userId.isNotEmpty) {
      final String displayName =
          resolvedUserName != null ? '$resolvedUserName ($userId)' : userId;
      spans.add(const TextSpan(text: '  '));
      spans.add(
        TextSpan(
          text: displayName,
          style: TextStyle(
            fontSize: idFontSize,
            color: hidden ? Colors.grey : (userColor ?? idColor),
            fontWeight: hidden || pinned ? null : FontWeight.w500,
            fontStyle: hidden ? FontStyle.italic : null,
          ),
        ),
      );
    }
  }

  spans.add(const TextSpan(text: '  '));
  spans.add(
    TextSpan(
      text: content,
      style: TextStyle(
        fontSize: fontSize,
        color: hidden ? Colors.grey : userColor,
        fontStyle: hidden ? FontStyle.italic : null,
      ),
    ),
  );

  return Text.rich(TextSpan(children: spans));
}

enum CommentSortOrder { ascending, descending }

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

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  static const double _autoScrollResumeThreshold = 50;
  static const Duration _wakelockReleaseDelay = Duration(seconds: 45);

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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _lastStatus = widget.connectionSupervisor.status;
    widget.connectionSupervisor.addListener(_handleConnectionChanged);

    // Keep screen on while viewing comments.
    unawaited(WakelockPlus.enable());
    _syncWakelockForStatus(_lastStatus);

    _requestUserNameResolution(widget.messages);
    _effectivePresetNgWords = widget.filterConfig.presetNgWords;
    _refreshNormalizedNgWords();
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
      unawaited(
        widget.callbacks.onDifferentLvConnected(
          oldWidget.programInfo.lv,
          widget.programInfo.lv,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEdge(animated: false);
      });
    }

    if (_pinnedMessageIds.isNotEmpty) {
      _cleanUpStalePinnedIds();
    }

    final String lastId =
        widget.messages.isNotEmpty ? widget.messages.last.id : 'empty';
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
      if (_autoScrollEnabled && !_touchActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToEdge();
        });
      } else if (!_touchActive && !_autoScrollEnabled) {
        // Re-check whether the user has scrolled back to the edge.
        // The scroll listener may not fire when maxScrollExtent changes
        // due to new messages, so we check here to resume auto-scroll.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _autoScrollEnabled) return;
          final bool atEdge =
              _sortOrder == CommentSortOrder.ascending
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
      // Skip comments containing NG words.
      if (_containsNgWord(message.content)) {
        _debugLog('[CommentScreen] submitComment: SKIP NG word');
        continue;
      }

      // Handle teach/unteach commands (owner only, never spoken).
      if (TeachCommandParser.isTeachCommand(message.content)) {
        if (message.userId == widget.programInfo.broadcasterUserId) {
          unawaited(_handleTeachCommand(message));
        }
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

  /// Returns `true` when [content] contains any configured NG word.
  bool _containsNgWord(String content) {
    if (_normalizedEffectiveNgWords.isEmpty) {
      return false;
    }
    final String normalizedContent = _normalizeNgWordText(content);
    return _normalizedEffectiveNgWords.any(normalizedContent.contains);
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

          final List<AppMessage> sortedMessages = _applySortOrder(
            visibleMessages,
          );
          final AppThemeMode effectiveMode = AppTheme.resolveEffectiveMode(
            widget.themeMode,
            MediaQuery.platformBrightnessOf(context),
          );
          final AppThemeColors themeColors = AppTheme.colorsFor(effectiveMode);

          return Scaffold(
            appBar: AppBar(
              toolbarHeight: 44,
              title: Text(
                widget.programInfo.broadcasterName ?? widget.programInfo.lv,
                key: const Key('appbar-title-text'),
                style: const TextStyle(fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
              actions: <Widget>[
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
                if (widget.logConfig.commentLogWriter != null)
                  IconButton(
                    key: const Key('save-comment-log-button'),
                    icon: const Icon(Icons.archive_outlined),
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
                  tooltip:
                      _sortOrder == CommentSortOrder.ascending
                          ? '新しい順に切替'
                          : '古い順に切替',
                  onPressed: _toggleSortOrder,
                ),
                if (widget.callbacks.onOpenSettings != null)
                  IconButton(
                    key: const Key('settings-button'),
                    icon: const Icon(Icons.settings),
                    tooltip: '設定',
                    onPressed: () async {
                      await widget.callbacks.onOpenSettings!.call();
                    },
                  ),
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
                            final int? userColor =
                                message.userId != null
                                    ? widget.filterConfig.userColorMap[message
                                        .userId!]
                                    : null;
                            return _CommentRow(
                              message: message,
                              themeColors: themeColors,
                              resolvedUserName: _resolveDisplayName(message),
                              showUserName: widget.showUserName,
                              fontSize: widget.commentFontSize,
                              starPrefixHidingEnabled:
                                  widget.filterConfig.starPrefixHidingEnabled,
                              commentTwoLineEnabled:
                                  widget.commentTwoLineEnabled,
                              zebraStripingEnabled:
                                  widget.commentZebraStripingEnabled,
                              commentIndex: index,
                              userColor:
                                  userColor != null
                                      ? colorFromARGB32(userColor)
                                      : null,
                              onLongPress: () => _showCommentActions(message),
                              onOpenUrl: _showUrlConfirmDialog,
                              beginAt: widget.programInfo.beginAt,
                            );
                          },
                        ),
                      ),
                      if (!_autoScrollEnabled)
                        Positioned(
                          right: 12,
                          bottom: 12,
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
                    ],
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
          onColorChanged:
              widget.callbacks.onUserColorChanged != null
                  ? (int colorValue) {
                    widget.callbacks.onUserColorChanged!.call(
                      userId,
                      colorValue,
                    );
                    Navigator.of(sheetContext).pop();
                  }
                  : null,
          onColorRemoved:
              widget.callbacks.onUserColorRemoved != null
                  ? () {
                    widget.callbacks.onUserColorRemoved!.call(userId);
                    Navigator.of(sheetContext).pop();
                  }
                  : null,
          nickname: widget.filterConfig.userNicknameMap[userId],
          onNicknameChanged:
              widget.callbacks.onNicknameChanged != null
                  ? (String nickname) {
                    widget.callbacks.onNicknameChanged!.call(userId, nickname);
                    Navigator.of(sheetContext).pop();
                  }
                  : null,
          onNicknameRemoved:
              widget.callbacks.onNicknameRemoved != null
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

    final String? selected =
        matches.length == 1
            ? await _confirmSingleUrl(matches.first.url)
            : await _pickUrl(
              matches
                  .map((UrlMatch match) => match.url)
                  .toList(growable: false),
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
    final Set<String> currentIds =
        widget.messages.map((AppMessage m) => m.id).toSet();
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
      _sortOrder =
          _sortOrder == CommentSortOrder.ascending
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
          onPressed:
              _isStopEnabled(status)
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

  bool _shouldDisplayMessage(AppMessage message) {
    switch (message.type) {
      case AppMessageType.chat:
      case AppMessageType.operator:
      case AppMessageType.notification:
        break;
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return false;
    }

    if (_isSystemBroadcastEndedMessage(message)) {
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

  String _removeControlAndInvisible(String text) {
    final StringBuffer sb = StringBuffer();
    for (final int cp in text.runes) {
      final bool invisible =
          cp == 0x200B ||
          cp == 0x200C ||
          cp == 0x200D ||
          cp == 0xFEFF ||
          cp == 0x00AD ||
          (cp >= 0xFE00 && cp <= 0xFE0F) ||
          (cp >= 0xE0100 && cp <= 0xE01EF) ||
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

  bool _shouldIncludeInStatsAndLogs(AppMessage message) {
    if (_isSystemBroadcastEndedMessage(message)) {
      return false;
    }
    return _shouldDisplayMessage(message);
  }

  void _scrollToEdge({bool animated = true}) {
    if (!_scrollController.hasClients) {
      return;
    }

    final double offset =
        _sortOrder == CommentSortOrder.ascending
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
    final bool atEdge =
        _sortOrder == CommentSortOrder.ascending
            ? _isNearBottom()
            : _isNearTop();
    if (atEdge) {
      setState(() {
        _autoScrollEnabled = true;
      });
    }
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
        child:
            url != null && url!.isNotEmpty
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child:
                useTwoLine
                    ? _buildTwoLinePinned(context)
                    : _buildCommentLineRichText(
                      message: message,
                      showUserName: showUserName,
                      fontSize: fontSize,
                      timestampColor: themeColors.subtleTextColor,
                      idColor: themeColors.subtleTextColor,
                      resolvedUserName: resolvedUserName,
                      userColor: userColor,
                      beginAt: beginAt,
                      pinned: true,
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
    final String? userId = message.userId;
    final double metaFontSize = (fontSize * _twoLineMetaFontRatio).clamp(
      _twoLineMinMetaFontSize,
      fontSize,
    );
    final Color metaColor = themeColors.subtleTextColor;

    final StringBuffer metaBuffer = StringBuffer(timestamp);
    if (userId != null && userId.isNotEmpty) {
      final String displayName =
          resolvedUserName != null ? '$resolvedUserName ($userId)' : userId;
      metaBuffer.write('  $displayName');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          metaBuffer.toString(),
          style: TextStyle(fontSize: metaFontSize, color: metaColor),
        ),
        const SizedBox(height: 2),
        Text(
          message.content,
          style: TextStyle(fontSize: fontSize, color: userColor),
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
    this.starPrefixHidingEnabled = false,
    this.commentTwoLineEnabled = false,
    this.zebraStripingEnabled = false,
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
  final bool starPrefixHidingEnabled;
  final bool commentTwoLineEnabled;
  final bool zebraStripingEnabled;
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
    final List<UrlMatch> urlMatches =
        hidden ? const <UrlMatch>[] : _resolveUrlMatches();
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
    // Two-line mode is only useful when the username is shown (line 1 holds
    // timestamp + username). When the username column is hidden, the first
    // line would contain only a timestamp, wasting vertical space -- so fall
    // back to single-line rendering.
    if (widget.commentTwoLineEnabled && widget.showUserName) {
      final AppMessage message = widget.message;
      final String timestamp = _formatHms(
        message.timestamp,
        beginAt: widget.beginAt,
      );
      final String content = hidden ? 'ネタバレ防止: タップで表示' : message.content;
      final double fontSize = widget.fontSize;
      final Color timestampColor = widget.themeColors.subtleTextColor;
      final Color idColor = widget.themeColors.subtleTextColor;
      final double twoLineMetaSize =
          hidden
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
      );
    }

    // Single-line rendering: delegate to the shared top-level helper when
    // there are no clickable URLs.  When URLs are present, build inline
    // so that _buildContentSpans can produce tappable link spans.
    if (urlMatches.isEmpty) {
      return _buildCommentLineRichText(
        message: widget.message,
        showUserName: widget.showUserName,
        fontSize: widget.fontSize,
        timestampColor: widget.themeColors.subtleTextColor,
        idColor: widget.themeColors.subtleTextColor,
        resolvedUserName: widget.resolvedUserName,
        userColor: widget.userColor,
        beginAt: widget.beginAt,
        hidden: hidden,
      );
    }

    // URL-aware single-line path.
    final AppMessage message = widget.message;
    final String timestamp = _formatHms(
      message.timestamp,
      beginAt: widget.beginAt,
    );
    final String content = hidden ? 'ネタバレ防止: タップで表示' : message.content;
    final double fontSize = widget.fontSize;
    final Color timestampColor = widget.themeColors.subtleTextColor;
    final Color idColor = widget.themeColors.subtleTextColor;
    const double minSubFontSize = 9.0;
    final double timestampFontSize =
        hidden ? fontSize : (fontSize * 0.85).clamp(minSubFontSize, fontSize);
    final double idFontSize =
        hidden ? fontSize : (fontSize * 0.9).clamp(minSubFontSize, fontSize);

    final List<InlineSpan> spans = <InlineSpan>[
      TextSpan(
        text: timestamp,
        style: TextStyle(
          fontSize: timestampFontSize,
          color: hidden ? Colors.grey : timestampColor,
          fontStyle: hidden ? FontStyle.italic : null,
        ),
      ),
    ];

    if (widget.showUserName) {
      final String? userId = message.userId;
      if (userId != null && userId.isNotEmpty) {
        final String displayName =
            widget.resolvedUserName != null
                ? '${widget.resolvedUserName} ($userId)'
                : userId;
        spans.add(const TextSpan(text: '  '));
        spans.add(
          TextSpan(
            text: displayName,
            style: TextStyle(
              fontSize: idFontSize,
              color: hidden ? Colors.grey : (widget.userColor ?? idColor),
              fontWeight: hidden ? null : FontWeight.w500,
              fontStyle: hidden ? FontStyle.italic : null,
            ),
          ),
        );
      }
    }

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : widget.userColor,
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
  }) {
    final List<InlineSpan> metaSpans = <InlineSpan>[
      TextSpan(
        text: timestamp,
        style: TextStyle(
          fontSize: timestampFontSize,
          color: hidden ? Colors.grey : timestampColor,
          fontStyle: hidden ? FontStyle.italic : null,
        ),
      ),
    ];

    if (widget.showUserName) {
      final String? userId = widget.message.userId;
      if (userId != null && userId.isNotEmpty) {
        final String displayName =
            widget.resolvedUserName != null
                ? '${widget.resolvedUserName} ($userId)'
                : userId;
        metaSpans.add(const TextSpan(text: '  '));
        metaSpans.add(
          TextSpan(
            text: displayName,
            style: TextStyle(
              fontSize: idFontSize,
              color: hidden ? Colors.grey : (widget.userColor ?? idColor),
              fontWeight: hidden ? null : FontWeight.w500,
              fontStyle: hidden ? FontStyle.italic : null,
            ),
          ),
        );
      }
    }

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : widget.userColor,
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
        return widget.themeColors.notificationMessageBackground;
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
