import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app_logging.dart';
import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/teach_command.dart';
import '../../domain/models/teach_command_handler.dart';
import '../../domain/utils/elapsed_formatter.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/user_name_resolution.dart';
import '../theme/app_theme.dart';
import 'comment_log_stats_sheet.dart';
import 'user_detail_sheet.dart';

const String kLegacyUnsupportedFormatMessage = 'legacy: 未対応フォーマット';

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

String _commentLineText({
  required AppMessage message,
  required bool showUserName,
  String? resolvedUserName,
  String? contentOverride,
  DateTime? beginAt,
}) {
  final String timestamp = _formatHms(message.timestamp, beginAt: beginAt);
  final String content = contentOverride ?? message.content;

  if (!showUserName) {
    return '$timestamp  $content';
  }

  final String userId = message.userId ?? '';

  if (userId.isEmpty) {
    return '$timestamp  $content';
  }

  final String displayName = resolvedUserName != null
      ? '$resolvedUserName ($userId)'
      : userId;

  return '$timestamp  $displayName  $content';
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
    this.broadcasterUserId,
    this.broadcasterIconUrl,
    this.beginAt,
    this.showUserName = true,
    this.commentFontSize = commentFontSizeDefault,
    this.userNameResolution,
    this.commentLogWriter,
    this.autoSaveCommentLog = false,
    this.autoSaveCommentLogPath = '',
    this.ngUserIds = const <String>{},
    this.ngWords = const <String>[],
    this.presetNgWords = const <String>[],
    this.onToggleNgUser,
    this.starPrefixHidingEnabled = false,
    this.userColorMap = const <String, int>{},
    this.onUserColorChanged,
    this.onUserColorRemoved,
    this.userNicknameMap = const <String, String>{},
    this.onNicknameChanged,
    this.onNicknameRemoved,
    this.autoNicknameRegistration = true,
    required this.themeMode,
    this.statisticsEnabled = false,
    this.statisticsViewerCommentEnabled = true,
    this.statisticsActiveUserEnabled = true,
    this.highlightPickupEnabled = false,
    this.viewerCount,
    this.totalCommentCount = 0,
    this.activeUserCount = 0,
    this.speechPlatform,
    this.speechSettings = const SpeechSettings(enabled: false),
    this.readUserName = false,
    this.settingsStore,
    this.onDictionaryRulesChanged,
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
  final String? broadcasterUserId;
  final String? broadcasterIconUrl;
  final DateTime? beginAt;
  final bool showUserName;
  final double commentFontSize;

  /// Bundles user-name resolution callbacks and listenable updates.
  final UserNameResolution? userNameResolution;

  final CommentLogWriter? commentLogWriter;
  final bool autoSaveCommentLog;
  final String autoSaveCommentLogPath;

  /// Set of user IDs marked as NG (blocked).
  final Set<String> ngUserIds;

  /// List of NG words for content-based filtering (case-insensitive).
  final List<String> ngWords;

  /// System preset NG words (non-user editable in UI).
  ///
  /// When empty, the widget attempts to load `preset_ng_words.json` from assets.
  final List<String> presetNgWords;

  /// Called to toggle NG status for a user.
  final void Function(String userId)? onToggleNgUser;

  /// When true, comments starting with `☆` have their body hidden
  /// and can be revealed by tapping.
  final bool starPrefixHidingEnabled;

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
  final bool statisticsEnabled;
  final bool statisticsViewerCommentEnabled;
  final bool statisticsActiveUserEnabled;
  final bool highlightPickupEnabled;
  final int? viewerCount;
  final int totalCommentCount;
  final int activeUserCount;

  /// The platform channel bridge for VoiceVox speech synthesis.
  /// Null when the speech plugin is not available.
  final CommentSpeechPlatform? speechPlatform;

  /// VoiceVox speech configuration. [SpeechSettings.enabled] reflects
  /// whether auto-read is active with the VoiceVox engine.
  final SpeechSettings speechSettings;

  /// When true, the user name is prepended to the comment text for TTS.
  final bool readUserName;

  /// Settings store for persisting teach command dictionary changes.
  final SettingsStore? settingsStore;

  /// Called when dictionary rules are updated by a teach/unteach command.
  final void Function(AppSettings updated)? onDictionaryRulesChanged;

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

    _debugLogLazy(
      () =>
          '[CommentScreen] initState: speech.enabled=${widget.speechSettings.enabled}, '
          'platform=${widget.speechPlatform != null ? "ok" : "null"}',
    );
    if (widget.speechSettings.enabled && widget.speechPlatform != null) {
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

    if (oldWidget.lv != widget.lv) {
      _autoScrollEnabled = true;
      _pinnedMessageIds.clear();
      unawaited(widget.onDifferentLvConnected(oldWidget.lv, widget.lv));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToEdge(animated: false);
      });
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

    if (oldWidget.speechSettings != widget.speechSettings) {
      _debugLogLazy(
        () =>
            '[CommentScreen] didUpdate: speechSettings changed: '
            'enabled ${oldWidget.speechSettings.enabled}→${widget.speechSettings.enabled}',
      );
      unawaited(_handleSpeechSettingsChanged(oldWidget.speechSettings));
    }

    // Speech: detect new messages independently of _hasNewMessages because
    // the message list may be mutable (oldWidget and widget share the same
    // data). Track progress via _lastSpeechMessageId instead.
    if (_speechStarted && widget.speechSettings.enabled) {
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
      if (_autoScrollEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToEdge();
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
      unawaited(widget.speechPlatform?.stop(clearQueue: true));
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
    final CommentSpeechPlatform? platform = widget.speechPlatform;
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
      await platform.updateSettings(widget.speechSettings);
      await platform.start();

      final ConnectionStatus currentStatus = widget.connectionSupervisor.status;
      if (!mounted ||
          !widget.speechSettings.enabled ||
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
          '${widget.speechSettings.enabled}, started=$_speechStarted',
    );
    if (!oldSettings.enabled && widget.speechSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → enabling speech');
      await _initializeAndStartSpeech();
    } else if (oldSettings.enabled && !widget.speechSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → disabling speech');
      await _stopSpeech();
    } else if (widget.speechSettings.enabled && _speechStarted) {
      _debugLog('[CommentScreen] settingsChanged: → pushing update to engine');
      try {
        await widget.speechPlatform?.updateSettings(widget.speechSettings);
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
        await widget.speechPlatform?.stop(clearQueue: true);
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

      if (_speechStarted && widget.speechSettings.enabled) {
        _submitNewCommentsForSpeech(widget.messages);
      }
    });
  }

  void _stopSpeechPollTimer() {
    _speechPollTimer?.cancel();
    _speechPollTimer = null;
  }

  void _submitNewCommentsForSpeech(List<AppMessage> messages) {
    final CommentSpeechPlatform? platform = widget.speechPlatform;
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
      if (userId != null && widget.ngUserIds.contains(userId)) {
        _debugLogLazy(
          () => '[CommentScreen] submitComment: SKIP NG user=$userId',
        );
        continue;
      }
      // Skip star-prefix hidden comments.
      if (widget.starPrefixHidingEnabled && message.content.startsWith('☆')) {
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
        if (message.userId == widget.broadcasterUserId) {
          unawaited(_handleTeachCommand(message));
        }
        continue;
      }

      String speechText = message.content;
      if (widget.readUserName) {
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
    if (widget.ngWords.isEmpty) {
      return false;
    }
    final String lowerContent = content.toLowerCase();
    for (final String rawWord in widget.ngWords) {
      final String normalizedWord = rawWord.trim().toLowerCase();
      if (normalizedWord.isEmpty) {
        continue;
      }
      if (lowerContent.contains(normalizedWord)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleTeachCommand(AppMessage message) async {
    final SettingsStore? store = widget.settingsStore;
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
        widget.onDictionaryRulesChanged?.call(updated);
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
    if (!widget.autoNicknameRegistration || widget.onNicknameChanged == null) {
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
        widget.onNicknameRemoved?.call(userId);
      } else {
        widget.onNicknameChanged!.call(userId, nickname);
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
                widget.broadcasterName ?? widget.lv,
                key: const Key('appbar-title-text'),
                style: const TextStyle(fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
              actions: <Widget>[
                if (widget.speechSettings.enabled)
                  _SpeechStatusIcon(
                    key: const Key('speech-status-icon'),
                    engineState: _speechEngineState,
                    isStarted: _speechStarted,
                    isInitialized: _speechInitialized,
                    themeColors: themeColors,
                  ),
                if (widget.commentLogWriter != null)
                  IconButton(
                    key: const Key('save-comment-log-button'),
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'コメントログを保存',
                    onPressed: _isSavingLog
                        ? null
                        : () => unawaited(_saveLogManual()),
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
                if (widget.onOpenSettings != null)
                  IconButton(
                    key: const Key('settings-button'),
                    icon: const Icon(Icons.settings),
                    tooltip: '設定',
                    onPressed: () async {
                      await widget.onOpenSettings!.call();
                    },
                  ),
              ],
            ),
            body: Column(
              children: <Widget>[
                if (widget.programTitle != null)
                  _ProgramTitleBar(
                    key: const Key('program-title-bar'),
                    title: widget.programTitle!,
                    broadcasterIconUrl: widget.broadcasterIconUrl,
                    themeColors: themeColors,
                  ),
                _StatusBar(
                  key: const Key('status-bar'),
                  lv: widget.lv,
                  supervisor: widget.connectionSupervisor,
                  debugMode: widget.debugMode,
                  connectionMethod: widget.connectionMethod,
                  broadcasterName: widget.broadcasterName,
                  broadcasterUserId: widget.broadcasterUserId,
                  broadcasterIconUrl: widget.broadcasterIconUrl,
                  beginAt: widget.beginAt,
                  themeColors: themeColors,
                  statisticsEnabled: widget.statisticsEnabled,
                  statisticsViewerCommentEnabled:
                      widget.statisticsViewerCommentEnabled,
                  statisticsActiveUserEnabled:
                      widget.statisticsActiveUserEnabled,
                  viewerCount: widget.viewerCount,
                  totalCommentCount: widget.totalCommentCount,
                  activeUserCount: widget.activeUserCount,
                ),
                if (_pinnedMessageIds.isNotEmpty)
                  _PinnedCommentsSection(
                    key: const Key('pinned-comments-section'),
                    pinnedMessages: _pinnedMessages(visibleMessages),
                    themeColors: themeColors,
                    showUserName: widget.showUserName,
                    fontSize: widget.commentFontSize,
                    resolveDisplayName: _resolveDisplayName,
                    userColorMap: widget.userColorMap,
                    onUnpin: _unpinMessage,
                    beginAt: widget.beginAt,
                  ),
                Expanded(
                  child: ListView.builder(
                    key: const Key('comment-list'),
                    controller: _scrollController,
                    itemCount: sortedMessages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final AppMessage message = sortedMessages[index];
                      final int? userColor = message.userId != null
                          ? widget.userColorMap[message.userId!]
                          : null;
                      return _CommentRow(
                        message: message,
                        themeColors: themeColors,
                        resolvedUserName: _resolveDisplayName(message),
                        showUserName: widget.showUserName,
                        fontSize: widget.commentFontSize,
                        starPrefixHidingEnabled: widget.starPrefixHidingEnabled,
                        userColor: userColor != null
                            ? colorFromARGB32(userColor)
                            : null,
                        onLongPress: () => _showCommentActions(message),
                        beginAt: widget.beginAt,
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

  void _showUserDetail(AppMessage message) {
    final String? userId = message.userId;
    if (userId == null || userId.isEmpty) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        final bool isNg = widget.ngUserIds.contains(userId);
        return UserDetailSheet(
          userId: userId,
          resolvedUserName: _resolveDisplayName(message),
          allMessages: widget.messages,
          isNgUser: isNg,
          themeMode: widget.themeMode,
          beginAt: widget.beginAt,
          currentColorValue: widget.userColorMap[userId],
          onColorChanged: widget.onUserColorChanged != null
              ? (int colorValue) {
                  widget.onUserColorChanged!.call(userId, colorValue);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onColorRemoved: widget.onUserColorRemoved != null
              ? () {
                  widget.onUserColorRemoved!.call(userId);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          nickname: widget.userNicknameMap[userId],
          onNicknameChanged: widget.onNicknameChanged != null
              ? (String nickname) {
                  widget.onNicknameChanged!.call(userId, nickname);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onNicknameRemoved: widget.onNicknameRemoved != null
              ? () {
                  widget.onNicknameRemoved!.call(userId);
                  Navigator.of(sheetContext).pop();
                }
              : null,
          onToggleNgUser: () {
            widget.onToggleNgUser?.call(userId);
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }

  void _showCommentActions(AppMessage message) {
    final bool isPinned = _pinnedMessageIds.contains(message.id);
    final bool hasUserId = message.userId != null && message.userId!.isNotEmpty;

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

  String? _resolveDisplayName(AppMessage message) {
    final String? userId = message.userId;
    // Nickname (コテハン) takes highest priority.
    if (userId != null && widget.userNicknameMap.containsKey(userId)) {
      return widget.userNicknameMap[userId];
    }
    if (message.userName != null) {
      return message.userName;
    }
    if (userId == null) {
      return null;
    }
    return widget.userNameResolution?.resolve(userId);
  }

  String? _resolveSpeechDisplayName(AppMessage message) {
    final String? userId = message.userId;
    if (userId != null && userId.isNotEmpty) {
      final String? nickname = widget.userNicknameMap[userId];
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
    _syncWakelockForStatus(currentStatus);

    if (widget.autoSaveCommentLog && _isAutoSaveTrigger(currentStatus)) {
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
        break;
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return false;
    }

    if (_isSystemBroadcastEndedMessage(message)) {
      return true;
    }

    final String? userId = message.userId;
    if (userId != null && widget.ngUserIds.contains(userId)) {
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
      ngUserIds: widget.ngUserIds,
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
            programTitle: widget.programTitle,
            lv: widget.lv,
            highlightPickupEnabled: widget.highlightPickupEnabled,
            messages: messagesForStatsAndLogs,
            ngUserIds: widget.ngUserIds,
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

    final CommentLogWriter? writer = widget.commentLogWriter;
    if (writer == null) {
      return;
    }

    setState(() {
      _isSavingLog = true;
    });

    try {
      final String? tempPath = await writer.writeToTempFile(
        lv: widget.lv,
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
      await Share.shareXFiles(<XFile>[XFile(tempPath)]);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLog = false;
        });
      }
    }
  }

  Future<void> _saveLogAuto() async {
    final CommentLogWriter? writer = widget.commentLogWriter;
    if (writer == null) {
      return;
    }

    final List<AppMessage> messagesForStatsAndLogs = _messagesForStatsAndLogs();

    final Directory? customDir = widget.autoSaveCommentLogPath.isNotEmpty
        ? Directory(widget.autoSaveCommentLogPath)
        : null;

    String? savedPath;
    try {
      savedPath = await writer.save(
        lv: widget.lv,
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
                errorBuilder: (_, __, ___) => Icon(Icons.person, size: size),
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
  });

  final List<AppMessage> pinnedMessages;
  final AppThemeColors themeColors;
  final bool showUserName;
  final double fontSize;
  final String? Function(AppMessage) resolveDisplayName;
  final Map<String, int> userColorMap;
  final void Function(String messageId) onUnpin;
  final DateTime? beginAt;

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
    this.userColor,
    required this.onUnpin,
    this.beginAt,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final Color? userColor;
  final VoidCallback onUnpin;
  final DateTime? beginAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _commentLineText(
                message: message,
                showUserName: showUserName,
                resolvedUserName: resolvedUserName,
                beginAt: beginAt,
              ),
              style: TextStyle(fontSize: fontSize, color: userColor),
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
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
    required this.message,
    required this.themeColors,
    this.resolvedUserName,
    this.showUserName = true,
    required this.fontSize,
    this.starPrefixHidingEnabled = false,
    this.userColor,
    this.onLongPress,
    this.beginAt,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final bool starPrefixHidingEnabled;
  final Color? userColor;
  final VoidCallback? onLongPress;
  final DateTime? beginAt;

  @override
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
  bool _revealed = false;

  bool get _isStarHidden =>
      widget.starPrefixHidingEnabled &&
      widget.message.content.startsWith('☆') &&
      !_revealed;

  @override
  void didUpdateWidget(covariant _CommentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _revealed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hidden = _isStarHidden;
    return GestureDetector(
      key: Key('comment-row-${widget.message.id}'),
      onLongPress: widget.onLongPress,
      onTap: hidden ? () => setState(() => _revealed = true) : null,
      child: Container(
        color: _backgroundColor(widget.message),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Text(
          _commentLineText(
            message: widget.message,
            showUserName: widget.showUserName,
            resolvedUserName: widget.resolvedUserName,
            contentOverride: hidden ? 'ネタバレ防止: タップで表示' : null,
            beginAt: widget.beginAt,
          ),
          style: TextStyle(
            fontSize: widget.fontSize,
            color: hidden ? Colors.grey : widget.userColor,
            fontStyle: hidden ? FontStyle.italic : null,
          ),
        ),
      ),
    );
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

class _SpeechStatusIcon extends StatelessWidget {
  const _SpeechStatusIcon({
    super.key,
    required this.engineState,
    required this.isStarted,
    required this.isInitialized,
    required this.themeColors,
  });

  final String engineState;
  final bool isStarted;
  final bool isInitialized;
  final AppThemeColors themeColors;

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
      icon = Icons.volume_off;
      color = themeColors.subtleTextColor;
      tooltip = '読み上げ: 停止中';
    } else if (engineState == 'ERROR') {
      icon = Icons.volume_off;
      color = themeColors.statusDisconnected;
      tooltip = '読み上げ: エラー';
    } else {
      icon = Icons.volume_up;
      color = themeColors.statusConnected;
      tooltip = '読み上げ: 準備完了';
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }
}
