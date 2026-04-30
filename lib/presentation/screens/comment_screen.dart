import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app_logging.dart';
import '../../application/comment_post/comment_post_controller.dart';
import '../../application/timeshift_fetch/timeshift_fetch_controller.dart';
import '../../application/settings/settings_store.dart';
import '../../application/speech/speech_availability_notifier.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/broadcast/broadcast_control_repository.dart';
import '../../data/comment_log/comment_log_tag.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/comment_log/comment_log_stats.dart';
import '../../domain/models/teach_command.dart';
import '../../domain/models/teach_command_handler.dart';
import '../../domain/utils/elapsed_formatter.dart';
import '../../domain/utils/search_normalizer.dart';
import '../../domain/utils/unicode_sanitizer.dart';
import '../../domain/utils/url_extractor.dart';
import '../../domain/connection/connection_supervisor.dart';
import '../../domain/matchers/ng_matcher.dart';
import '../../domain/normalizers/ng_word_text_normalizer.dart';
import '../../domain/models/app_message.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_display_subcategory.dart';
import '../../domain/models/ng_policy.dart';
import '../../domain/models/ng_preset_category.dart';
import '../../domain/models/user_name_resolution.dart';
import '../errors/user_facing_error_messages.dart';
import '../strings/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/comment_input_bar.dart';
import '../widgets/display_subcategory_warning_dialog.dart';
import 'comment_log_stats_sheet.dart';
import 'comment_screen_config.dart';
import 'tts_settings_screen.dart';
import '../widgets/timeshift_fetch_panel.dart';
import 'user_detail_sheet.dart';

const String kLegacyUnsupportedFormatMessage = 'legacy: 未対応フォーマット';

/// Two-line mode: minimum meta font size in logical pixels.
///
/// The configurable [AppSettings.commentTwoLineMetaFontPercent] is allowed
/// down to [commentTwoLineMetaFontPercentMin]% (currently 20%), which at the
/// minimum body size could otherwise produce sub-pixel meta text. This
/// floor keeps the timestamp + username row legible regardless of the
/// percentage chosen.
const double _twoLineMinMetaFontSize = 9.0;

/// Computes the rendered font size of the two-line mode meta row
/// (timestamp + username) for a given body [bodyFontSize] and
/// configured [percent] (e.g. 40 for 40%).
///
/// Centralizes the percent→ratio conversion and the 9px absolute floor
/// so the regular comment row and the pinned comment row stay in
/// lock-step. If [_twoLineMinMetaFontSize] ever changes, only this
/// function needs updating.
double _resolveTwoLineMetaFontSize(double bodyFontSize, int percent) {
  return (bodyFontSize * commentTwoLineMetaFontPercentToRatio(percent)).clamp(
    _twoLineMinMetaFontSize,
    bodyFontSize,
  );
}

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

/// Builds the timestamp + optional user-ID display-name spans shared by the
/// pinned two-line layout, the single-line URL-aware layout, and the
/// two-line main comment layout.
///
/// The caller is responsible for:
/// - resolving [displayName] via [_displayNameForMessage] (the operator vs.
///   chat fallback logic is not duplicated here).
/// - computing font sizes and colors so that this helper stays a pure UI
///   builder and never reads `Theme.of(context)`.
///
/// [hidden] maps the star-prefix "spoiler hidden" state in the regular row
/// (always `false` for pinned rows, which don't support star-prefix hiding):
/// it forces grey text, italic, and drops [idFontWeight].
///
/// [idFontWeight] is the weight applied to the display-name span when not
/// hidden. Pinned rows pass `null` to keep the existing pre-refactor look;
/// the regular row passes `FontWeight.w500`.
///
/// Returns the spans in order: `[timestamp, ('  ', displayName)?]`. No
/// trailing whitespace span or content span is appended — the caller owns
/// the transition into the comment body so URL-aware vs plain paths stay
/// separated.
List<InlineSpan> _buildMetaSpans({
  required String timestamp,
  required bool showUserName,
  String? displayName,
  required double timestampFontSize,
  required double idFontSize,
  required Color timestampColor,
  required Color idColor,
  Color? effectiveUserColor,
  required bool hidden,
  FontWeight? idFontWeight,
}) {
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
  if (showUserName && displayName != null) {
    // Explicitly size the whitespace separator so an inherited
    // DefaultTextStyle (typically ~14px body text) cannot inflate the meta
    // line height beyond the adjacent spans. Pre-refactor, the pinned row
    // styled this separator with the metaFontSize; keeping the separator
    // bounded to the larger of the two meta spans preserves that line
    // height for every call site.
    final double separatorFontSize = timestampFontSize > idFontSize
        ? timestampFontSize
        : idFontSize;
    spans.add(
      TextSpan(
        text: '  ',
        style: TextStyle(fontSize: separatorFontSize),
      ),
    );
    spans.add(
      TextSpan(
        text: displayName,
        style: TextStyle(
          fontSize: idFontSize,
          color: hidden ? Colors.grey : (effectiveUserColor ?? idColor),
          fontWeight: hidden ? null : idFontWeight,
          fontStyle: hidden ? FontStyle.italic : null,
        ),
      ),
    );
  }
  return spans;
}

/// Test-only accessor for [_buildMetaSpans].
///
/// Exposed so widget-free unit tests can pin the timestamp + display-name
/// span construction without rendering a comment row. The real helper stays
/// private to this library.
@visibleForTesting
List<InlineSpan> buildMetaSpansForTesting({
  required String timestamp,
  required bool showUserName,
  String? displayName,
  required double timestampFontSize,
  required double idFontSize,
  required Color timestampColor,
  required Color idColor,
  Color? effectiveUserColor,
  required bool hidden,
  FontWeight? idFontWeight,
}) {
  return _buildMetaSpans(
    timestamp: timestamp,
    showUserName: showUserName,
    displayName: displayName,
    timestampFontSize: timestampFontSize,
    idFontSize: idFontSize,
    timestampColor: timestampColor,
    idColor: idColor,
    effectiveUserColor: effectiveUserColor,
    hidden: hidden,
    idFontWeight: idFontWeight,
  );
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

/// Test-only harness exposing [_CommentRow] to widget tests.
///
/// The private row class intentionally stays private to prevent call sites
/// outside this file from constructing it directly. Tests need to pump one
/// row at a time to verify the read-skipped badge / opacity / semantics
/// without spinning up the full [CommentScreen], so this thin wrapper
/// forwards every prop 1:1. Behavior must match the production call site
/// (see the `_CommentRow(` instantiation inside the ListView.builder).
@visibleForTesting
class CommentRowHarness extends StatelessWidget {
  const CommentRowHarness({
    super.key,
    required this.message,
    required this.themeColors,
    this.resolvedUserName,
    this.showUserName = true,
    required this.fontSize,
    this.textScaler = TextScaler.noScaling,
    this.starPrefixHidingEnabled = false,
    this.commentTwoLineEnabled = false,
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.zebraStripingEnabled = false,
    this.emphasizeGiftNicoadComment = true,
    this.commentIndex = 0,
    this.userColor,
    this.onLongPress,
    this.onOpenUrl,
    this.beginAt,
    this.ngMatcher,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final TextScaler textScaler;
  final bool starPrefixHidingEnabled;
  final bool commentTwoLineEnabled;
  final int commentTwoLineMetaFontPercent;
  final bool zebraStripingEnabled;
  final bool emphasizeGiftNicoadComment;
  final int commentIndex;
  final Color? userColor;
  final VoidCallback? onLongPress;
  final ValueChanged<AppMessage>? onOpenUrl;
  final DateTime? beginAt;
  final NgMatcher? ngMatcher;

  @override
  Widget build(BuildContext context) {
    return _CommentRow(
      message: message,
      themeColors: themeColors,
      resolvedUserName: resolvedUserName,
      showUserName: showUserName,
      fontSize: fontSize,
      textScaler: textScaler,
      starPrefixHidingEnabled: starPrefixHidingEnabled,
      commentTwoLineEnabled: commentTwoLineEnabled,
      commentTwoLineMetaFontPercent: commentTwoLineMetaFontPercent,
      zebraStripingEnabled: zebraStripingEnabled,
      emphasizeGiftNicoadComment: emphasizeGiftNicoadComment,
      commentIndex: commentIndex,
      userColor: userColor,
      onLongPress: onLongPress,
      onOpenUrl: onOpenUrl,
      beginAt: beginAt,
      ngMatcher: ngMatcher,
    );
  }
}

/// Test-only harness exposing [_PinnedCommentRow]. See [CommentRowHarness]
/// for rationale.
@visibleForTesting
class PinnedCommentRowHarness extends StatelessWidget {
  const PinnedCommentRowHarness({
    super.key,
    required this.message,
    required this.themeColors,
    this.resolvedUserName,
    this.showUserName = true,
    required this.fontSize,
    this.commentTwoLineEnabled = false,
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.userColor,
    required this.onUnpin,
    this.beginAt,
    this.textScaler = TextScaler.noScaling,
    this.ngMatcher,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final bool commentTwoLineEnabled;
  final int commentTwoLineMetaFontPercent;
  final Color? userColor;
  final VoidCallback onUnpin;
  final DateTime? beginAt;
  final TextScaler textScaler;
  final NgMatcher? ngMatcher;

  @override
  Widget build(BuildContext context) {
    return _PinnedCommentRow(
      message: message,
      themeColors: themeColors,
      resolvedUserName: resolvedUserName,
      showUserName: showUserName,
      fontSize: fontSize,
      commentTwoLineEnabled: commentTwoLineEnabled,
      commentTwoLineMetaFontPercent: commentTwoLineMetaFontPercent,
      userColor: userColor,
      onUnpin: onUnpin,
      beginAt: beginAt,
      textScaler: textScaler,
      ngMatcher: ngMatcher,
    );
  }
}

/// Actions reachable through the AppBar overflow menu. Kept private to the
/// screen because the menu's wiring lives entirely inside [CommentScreen].
enum _AppBarMenuAction { endBroadcast, search, saveLog, settings }

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

/// Public test-only interface exposing the comment-log branch of the
/// [CommentScreen] state.
///
/// Exists so widget integration tests for `_messagesForLog()` can invoke the
/// real production code path without the screen's state class being made
/// public. Tests reach this interface via
/// `tester.state<State<CommentScreen>>(...) as CommentScreenTestAccess`.
///
/// Do not add members for non-test reasons — that would reintroduce the
/// encapsulation leak this indirection is designed to avoid.
@visibleForTesting
abstract interface class CommentScreenTestAccess {
  /// Delegates to the private `_messagesForLog()` method and returns the
  /// list of messages that would be written to the auto-saved comment log.
  List<AppMessage> messagesForLogForTesting();

  /// Test-only: directly sets the `_isBroadcaster` flag (and optionally
  /// the cached `_commentPostUserSession`), bypassing the async
  /// `ensureBroadcasterStatus` pipeline that would otherwise require a
  /// real `CommentPostController` + `MyProgramRepository`. Triggers a
  /// rebuild so widgets gated on broadcaster mode (e.g. the
  /// "配信を終了" overflow menu entry) appear immediately.
  ///
  /// [userSession] is the value to seed for `_commentPostUserSession`;
  /// pass an empty string to exercise the "session required" branch in
  /// `_endBroadcastFromMenu`.
  void setBroadcasterForTesting({
    required bool isBroadcaster,
    String userSession = 'test-user-session',
  });
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
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.commentZebraStripingEnabled = false,
    this.commentSortOrder = CommentSortOrder.ascending,
    this.userColorMap = const <String, int>{},
    this.onUserColorChanged,
    this.onUserColorRemoved,
    this.userNicknameMap = const <String, String>{},
    this.onNicknameChanged,
    this.onNicknameRemoved,
    this.autoNicknameRegistration = true,
    required this.themeMode,
    this.statistics = const CommentStatisticsConfig(),
    this.contentFilter = const ContentFilterConfig(),
    this.messageTypeVisibility = const MessageTypeVisibilityConfig(),
    this.logConfig = const CommentLogConfig(),
    this.speechConfig = const CommentSpeechConfig(),
    this.commentPostController,
    this.userSessionLoader,
    this.timeshiftFetchController,
    this.broadcastControlRepository,
    this.clock,
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

  /// Two-line mode: meta-row (timestamp + username) font size as a percentage
  /// of [commentFontSize]. Ignored when [commentTwoLineEnabled] is false.
  final int commentTwoLineMetaFontPercent;

  /// When true, alternating comment rows have a subtle background tint
  /// for easier visual scanning.
  final bool commentZebraStripingEnabled;

  /// 初期スクロール方向。永続化された値（[AppSettings.commentSortOrder]）から
  /// `_CommentScreenState._sortOrder` の初期化に使う。AppBar のソート切替
  /// ボタンが押されたら `CommentCallbacks.onSortOrderChanged` を呼んで
  /// 上位レイヤーで永続化される（Issue #774）。
  final CommentSortOrder commentSortOrder;

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

  /// Content-based filters + per-user rendering attributes
  /// (NG users, NG words, colors, nicknames, prefix toggles, emphasis).
  final ContentFilterConfig contentFilter;

  /// Message-type visibility toggles
  /// (運営 / system / emotion / gift / nicoad list visibility).
  final MessageTypeVisibilityConfig messageTypeVisibility;

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

  final TimeshiftFetchController? timeshiftFetchController;

  /// Optional repository used to end the user's own broadcast from the
  /// AppBar overflow menu. When `null`, the "配信を終了" menu entry is
  /// hidden regardless of [_CommentScreenState._isBroadcaster].
  ///
  /// Wired by [SelectScreen] to the same instance it uses for the
  /// slide-to-end control on the program list, so both entry points share
  /// the same niconico segment API client.
  final BroadcastControlRepository? broadcastControlRepository;

  /// Clock abstraction used for the NG-protection snackbar throttle window.
  ///
  /// In production this is `null` and the implementation falls back to the
  /// top-level [clock] getter from `package:clock`, which delegates to
  /// `DateTime.now()`. Tests can inject a fixed or fake clock (for example
  /// via `withClock`) to verify the 10-second throttle without sleeping on
  /// the wall clock.
  final Clock? clock;

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen>
    implements CommentScreenTestAccess {
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

  /// In-flight guard for the AppBar overflow "配信を終了" entry. While
  /// `true` the menu item is rendered disabled and re-tapping after
  /// re-opening the menu cannot trigger a second `endBroadcast` API call.
  bool _isEndingBroadcast = false;

  /// Timestamp at which the broadcast transitioned to ended/stopped.
  /// Used to freeze the status-bar elapsed timer display.
  DateTime? _endedAt;

  /// Stats captured when the broadcast ends. Non-null implies the
  /// post-broadcast stats panel is rendered; null means it is not.
  /// Held so the user can re-open the panel after minimizing or
  /// dismissing the end-of-broadcast SnackBar.
  CommentLogStats? _pendingStats;
  List<AppMessage> _pendingStatsMessages = const <AppMessage>[];

  /// Whether the stats panel is expanded (full content) or minimized
  /// (header bar only, tappable to restore). Only consulted when
  /// [_pendingStats] is non-null.
  bool _statsPanelExpanded = false;
  late CommentSortOrder _sortOrder = widget.commentSortOrder;
  final Set<String> _pinnedMessageIds = <String>{};
  bool _touchActive = false;

  bool _speechInitializing = false;

  /// Issue #741 (Problem 2): replaces the previous `bool _speechInitialized`
  /// magic-boolean with a typed marker that records WHICH engine the
  /// platform was last brought to ready state for. The boolean form
  /// silently survived an `engineType` switch — the user toggled from
  /// VOICEVOX to Android TTS, the value stayed `true`, and the init
  /// branch in [_initializeAndStartSpeech] was skipped even though
  /// nothing on the native side had been initialised for the new engine.
  ///
  /// All readers should go through [_isInitializedForCurrentEngine] so
  /// the comparison against [SpeechSettings.engineType] is centralised.
  /// Writers set this to `widget.speechConfig.speechSettings.engineType`
  /// on success and to `null` on teardown / retry.
  ///
  /// TODO(#741 follow-up — Problem 3): the Flutter-side `_speechStarted`
  /// flag is still maintained independently of the native
  /// `SpeechRuntimeStatus`. Once the native side exposes a `started`
  /// field via getStatus(), this screen should reconcile both flags
  /// instead of trusting only the local one.
  String? _initializedEngineType;
  bool _speechStarted = false;

  /// True when [_initializedEngineType] matches the engine type currently
  /// configured in `widget.speechConfig.speechSettings`. The previous
  /// `_speechInitialized` boolean answered the weaker question "did we
  /// ever finish init?" — this getter answers the question that the
  /// init / retry branches actually care about: "is the engine we are
  /// configured to speak with right now in a ready state?"
  bool get _isInitializedForCurrentEngine =>
      _initializedEngineType == widget.speechConfig.speechSettings.engineType;
  // Issue #717 (ARCH-2): replaced inline magic strings (`'' / 'READY' /
  // 'ERROR'`) with [SpeechEngineState] so the 4 source paths
  // (native event / cross-screen notifier / init failure / recovery
  // heuristic) all funnel through a single typed setter
  // [_setSpeechEngineState] and a single comparison surface.
  SpeechEngineState _speechEngineState = SpeechEngineState.unknown;

  /// Issue #712 (UX-1): tracks whether the SnackBar has already been
  /// shown for the current ERROR episode. Set to true when the engine
  /// transitions into `'ERROR'` from a non-ERROR state, reset back to
  /// false on any transition out of ERROR. Subsequent ERROR re-entries
  /// during the same episode are silenced to avoid SnackBar spam.
  bool _speechErrorNotified = false;

  /// Number of consecutive Android-TTS `speech_failed` events received with
  /// no `speech_completed` in between. When this reaches
  /// [_androidTtsErrorThreshold] the screen surfaces ERROR via the
  /// AppBar status icon (Issue #695). Single transient failures are not
  /// surfaced to avoid false positives — only a sustained inability to
  /// speak is treated as a runtime degradation.
  int _consecutiveAndroidTtsFailures = 0;

  /// Number of consecutive Android-TTS speak failures required before the
  /// screen flips `_speechEngineState` to `'ERROR'`. Tuned high enough to
  /// ride out a one-off CPU spike or transient platform-channel hiccup but
  /// low enough that an ongoing failure (OS settings → voice data deleted
  /// while connected, engine switched to a non-Japanese-capable engine,
  /// native TextToSpeech instance invalidated) reaches the user within
  /// ~3 dropped comments.
  static const int _androidTtsErrorThreshold = 3;

  Timer? _wakelockReleaseTimer;

  /// Periodic timer that ensures new comments are submitted for speech
  /// even when the widget tree is not rebuilt (e.g. while the app is
  /// backgrounded and [didUpdateWidget] is not called).
  Timer? _speechPollTimer;
  StreamSubscription<SpeechEvent>? _speechEventSub;

  /// Issue #739: countdown that delays the broadcast-end speech-stop so the
  /// remaining queue can drain. Non-null only between
  /// `ConnectionStatus.ended` and the moment grace expires (or is
  /// cancelled). When [_isInSpeechGrace] is `true` the queue must NOT be
  /// cleared yet — see [_endSpeechGrace] for the deferred stop call.
  Timer? _speechGraceTimer;
  bool _isInSpeechGrace = false;

  /// The ID of the last message processed for speech.
  /// Initialized when speech starts (baseline), then updated after each
  /// submission. This avoids depending on oldWidget.messages which may
  /// reference the same mutable list as widget.messages.
  String? _lastSpeechMessageId;

  /// ID of the message that was `.last` when auto-scroll last reacted to a
  /// new arrival. Used to detect a newly appended latest message without
  /// depending on `oldWidget.messages` vs `widget.messages`, which may be
  /// two `UnmodifiableListView` instances over the same mutable list in
  /// [TimelineStore] (so diff-based detection would see equal snapshots).
  /// Auto-scroll worked coincidentally when the timeline was capped at the
  /// past-comment fetch count, because trimming kept the list length stable
  /// and the visible tail refreshed in place. After capacity was widened to
  /// preserve fetched history, that illusion broke — hence this explicit
  /// tracker.
  String? _lastAutoScrollObservedLastId;

  /// ID of the tail message that the shared "did a new message arrive?"
  /// gate last processed. Used by [_logNewComments],
  /// [_requestUserNameResolutionForNewMessages] and
  /// [_processNicknameComments] to slice the freshly arrived suffix out of
  /// `widget.messages` (Issue #670).
  ///
  /// [_processNgProtectionNotifications] is called from the same gate but
  /// keeps its own dedicated cursor [_lastProtectionInspectedMessageId]
  /// because it has additional cursor-advance semantics on the OFF→ON
  /// toggle path that the shared cursor cannot express.
  ///
  /// A diff between `oldWidget.messages` and `widget.messages` is unreliable
  /// here because [TimelineStore.messages] returns an [UnmodifiableListView]
  /// over the same mutable underlying list, so both values resolve to the
  /// current state at the moment `didUpdateWidget` runs. This cursor is
  /// genuinely state-local and therefore decoupled from that aliasing.
  ///
  /// Re-seeded on initial mount, on lv switch, and on transition to an
  /// empty messages list (timeline clear) so historic backfill is not
  /// retroactively replayed through the gated callbacks. Supervisor swap
  /// is intentionally NOT a re-seed trigger — see the swap branch in
  /// [didUpdateWidget] for the rationale.
  String? _lastProcessedTailMessageId;

  /// Set of message IDs that have already been emitted to the nickname
  /// callback within the current screen lifetime. Defends against the
  /// "ring-buffer rotation" path in [_sliceStartFromCursor] that falls back
  /// to processing the full tail when the cursor message has been evicted
  /// — without de-duplication, a `@nickname` comment that survives across
  /// the rotation could fire `onNicknameChanged` more than once and
  /// silently overwrite a newer registration set by a later message.
  ///
  /// **Trade-off (round-2 sage review)**: a message id is added to this
  /// set BEFORE its dispatch to the nickname callback, so if the callback
  /// itself throws, the message will be marked processed and not retried
  /// on a subsequent rebuild. We accept this in exchange for guaranteeing
  /// the no-overwrite invariant. The callback is a simple state-update in
  /// the upstream owner and is not expected to throw in practice.
  ///
  /// NG-protection is intentionally NOT de-duplicated this way: that
  /// pipeline maintains a cumulative badge count, where a one-shot
  /// over-count during ring rotation is preferable to silently dropping a
  /// genuine NG hit. See [_processNgProtectionNotifications].
  ///
  /// Bounded eviction policy: once the set reaches
  /// [_kRecentlyProcessedNicknameIdsCap] entries we clear it wholesale.
  /// This is simpler than a true LRU and acceptable because the cap is
  /// large enough that legitimate re-firing is statistically unreachable
  /// during normal operation; the worst case after a clear is identical
  /// to the no-de-dup baseline (one possible duplicate registration), and
  /// recovery is automatic on the next non-duplicate message.
  final Set<String> _recentlyProcessedNicknameMessageIds = <String>{};

  /// Cap for [_recentlyProcessedNicknameMessageIds]. 200 covers a comfortable
  /// rotation depth on the chat path (typical viewer chat ring is ≪ 200
  /// comments deep before rotation evicts the earliest one).
  static const int _kRecentlyProcessedNicknameIdsCap = 200;

  /// One-shot flag: when `true`, the NEXT non-empty observation in
  /// [didUpdateWidget] silently seeds [_lastProcessedTailMessageId] with
  /// the current tail instead of processing the slice through the gated
  /// callbacks. Cleared after the seed. Set whenever the messages list
  /// transitions from non-empty to empty (timeline clear via
  /// `onReconnectSameLv` etc.) so that the subsequent backfill is not
  /// retroactively replayed (Issue #670 round-1 review).
  bool _seedNextTailObservationSilently = false;

  /// Timestamp recorded just before the speech engine starts. Messages with a
  /// timestamp before this value are skipped, ensuring that only comments
  /// arriving after speech initialization are read aloud.
  DateTime? _speechBaselineTimestamp;
  List<String> _effectivePresetNgWords = const <String>[];

  /// Structured preset categories loaded from the asset, when available.
  /// Remains empty when the caller passes a pre-populated flat
  /// `contentFilter.presetNgWords` (legacy path) or when the asset failed
  /// to load. The matcher falls back to treating flat preset words as
  /// `blockSpeechOnly` with no subcategory in that case, which keeps the
  /// v1 behavior (matched comments are both silenced and hidden because
  /// [NgDisplayPreferences] defaults to "allow nothing" in #613).
  List<NgPresetCategory> _effectivePresetCategories =
      const <NgPresetCategory>[];

  /// Matcher rebuilt whenever the preset / user NG word list changes.
  /// Initial value is an empty matcher using the default domain-layer
  /// [normalizeNgWordText]; [_rebuildNgMatcher] replaces it in `initState`.
  NgMatcher _ngMatcher = NgMatcher.fromFlatWords(words: const <String>[]);

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
  // Tracked only when [ContentFilterConfig.ngProtectionNotificationEnabled]
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

  /// Cached pattern used by [_sanitizeSingleLine] to collapse any residual
  /// CR / LF / TAB runs into a single space.  Defensive: the shared
  /// [removeControlAndInvisibleChars] already strips these C0 controls,
  /// but keeping the replacement guards against a future refactor that
  /// preserves them.  `static final` avoids recompiling the pattern on
  /// every snackbar label build, matching the style of the whitespace
  /// pattern in [ndgr_message_normalizer.dart].
  static final RegExp _singleLineWhitespacePattern = RegExp(r'[\r\n\t]+');

  // Comment keyword search state.
  bool _isSearching = false;
  String _searchQuery = '';
  // Normalized form of [_searchQuery] (trim + NFKC-style fold via
  // [normalizeForSearch]), cached so that the per-message match check
  // stays O(L) per message instead of recomputing normalization on every
  // list rebuild. See Issue #472.
  String _normalizedSearchQuery = '';

  // Memoized normalized message content (Issue #472 perf note).
  //
  // The issue explicitly flagged per-message normalization on every
  // rebuild as a perf concern. We keep a bounded LRU-style cache keyed
  // by the message id (AppMessage.id is immutable once constructed, so
  // entries never need invalidation). The ceiling prevents unbounded
  // growth on very long sessions; when exceeded we drop the whole
  // cache (cheapest approach — normalization itself is O(L) so the
  // worst-case repopulation cost is acceptable vs. the complexity of
  // a real LRU).
  static const int _kNormalizedContentCacheCeiling = 4096;
  final Map<String, String> _normalizedContentCache = <String, String>{};
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
    _effectivePresetNgWords = widget.contentFilter.presetNgWords;
    _rebuildNgMatcher();

    // Seed the NG-protection cursor with the current tail so that messages
    // already in the list (e.g. past-comment backfill) are not announced
    // retroactively when the broadcaster opens the screen.
    if (widget.messages.isNotEmpty) {
      _lastProtectionInspectedMessageId = widget.messages.last.id;
    }

    // Seed the auto-scroll cursor with the current tail so that the initial
    // post-mount `_scrollToEdge` below is the only jump; subsequent
    // `didUpdateWidget` calls will only re-scroll when a truly newer
    // message lands at the tail.
    if (widget.messages.isNotEmpty) {
      _lastAutoScrollObservedLastId = widget.messages.last.id;
    }

    // Issue #670: seed the shared "did a new tail arrive?" cursor with the
    // current tail so that history backfill already in `widget.messages`
    // does not retroactively replay nickname/NG-protection/userName-resolve
    // logic on first frame. Subsequent `didUpdateWidget` calls only fire
    // when a genuinely newer message lands at the tail.
    if (widget.messages.isNotEmpty) {
      _lastProcessedTailMessageId = widget.messages.last.id;
    }
    if (widget.contentFilter.presetNgWords.isEmpty) {
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

    // Issue #694 cycle-2-new review: clear a stale local ERROR state when
    // the cross-screen notifier publishes that the engine is available
    // again (e.g. user re-installed Japanese voice data via TTS settings).
    // Without this listener, the AppBar would stay on the
    // `error_outline` icon even after recovery because the OR-condition
    // `engineState == 'ERROR' || treatAsError` keeps firing on the local
    // `_speechEngineState` half (the `treatAsError` half flips correctly
    // via `AnimatedBuilder`).
    widget.speechConfig.androidTtsAvailability?.addListener(
      _onAndroidTtsAvailabilityChanged,
    );

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
      // Issue #670 round-1 review (変化) note: we intentionally do NOT
      // re-seed the shared tail cursor on a supervisor swap. In production
      // the supervisor is created once at app start and never replaced,
      // so this branch is reached only by tests (some of which build a
      // fresh supervisor on every widget rebuild). The genuine "different
      // data source" signal is the lv change branch below; lv change
      // handles the cursor / de-dup reset there.
    }

    // Issue #694 cycle-2-new (round 2) review: when the parent rebuilds
    // CommentScreen with a different cross-screen availability notifier,
    // re-attach the listener so we (a) stop receiving updates from the
    // old notifier and (b) respond to changes on the new one. Without
    // this swap the listener would silently leak references to the
    // previous notifier instance.
    final SpeechAvailabilityNotifier? oldNotifier =
        oldWidget.speechConfig.androidTtsAvailability;
    final SpeechAvailabilityNotifier? newNotifier =
        widget.speechConfig.androidTtsAvailability;
    if (!identical(oldNotifier, newNotifier)) {
      oldNotifier?.removeListener(_onAndroidTtsAvailabilityChanged);
      newNotifier?.addListener(_onAndroidTtsAvailabilityChanged);
    }

    if (!_listEqualsShallow(
          oldWidget.contentFilter.ngWords,
          widget.contentFilter.ngWords,
        ) ||
        !_listEqualsShallow(
          oldWidget.contentFilter.presetNgWords,
          widget.contentFilter.presetNgWords,
        )) {
      if (widget.contentFilter.presetNgWords.isNotEmpty) {
        _effectivePresetNgWords = widget.contentFilter.presetNgWords;
        // Flat list provided by the caller loses category info; drop any
        // previously loaded structured categories so the matcher does not
        // mix stale subcategory metadata with a fresh flat word list.
        // The log will fall back to dropping preset matches without a
        // [filtered:<sub>] tag, since NgMatcher.match()?.matchedSubcategory
        // returns null for flat-fallback entries.
        _effectivePresetCategories = const <NgPresetCategory>[];
        _rebuildNgMatcher();
      } else if (oldWidget.contentFilter.presetNgWords.isNotEmpty &&
          widget.contentFilter.presetNgWords.isEmpty) {
        _effectivePresetNgWords = const <String>[];
        _effectivePresetCategories = const <NgPresetCategory>[];
        _rebuildNgMatcher();
        unawaited(_loadPresetNgWordsFromAsset());
      } else {
        _rebuildNgMatcher();
      }
    }

    // NG protection notification OFF→ON transition: re-seed the cursor so
    // that only NG hits *after* the user toggles the feature on contribute
    // to the badge / snackbar. Without this, if the ring buffer rotated out
    // the stale cursor during OFF, the fallback path (start = 0) would
    // replay the entire tail on the first ON pass and produce a sudden
    // spike in the badge count from historical messages the user never
    // intended to be "protected". ON→OFF leaves the cursor where it is so
    // that re-enabling later still picks up from the current tail.
    if (!oldWidget.contentFilter.ngProtectionNotificationEnabled &&
        widget.contentFilter.ngProtectionNotificationEnabled) {
      _lastProtectionInspectedMessageId = widget.messages.isNotEmpty
          ? widget.messages.last.id
          : null;
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
      // Re-seed the auto-scroll cursor so that the first arrival on the
      // new lv is treated as "new" (triggering a scroll to the tail) only
      // once, not repeatedly for messages already in the refreshed list.
      _lastAutoScrollObservedLastId = widget.messages.isNotEmpty
          ? widget.messages.last.id
          : null;
      // Issue #670: re-seed the shared tail cursor on lv switch so that the
      // backfilled history of the new program does not retroactively trigger
      // nickname / userName / log gates. Also clear the nickname de-dup set
      // so message ids from the prior program do not block legitimate
      // re-registration on the new program (id collisions are theoretical
      // but cheap to defend against).
      _lastProcessedTailMessageId = widget.messages.isNotEmpty
          ? widget.messages.last.id
          : null;
      _recentlyProcessedNicknameMessageIds.clear();
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

    // Speech: detect new messages with a state-local cursor because the
    // message list may be mutable (oldWidget and widget share the same data).
    // Track progress via _lastSpeechMessageId instead.
    if (_speechStarted && widget.speechConfig.speechSettings.enabled) {
      _submitNewCommentsForSpeech(widget.messages);
    }

    // Issue #670: gate nickname / userName-resolve / log / NG-protection on a
    // single state-local tail cursor instead of an oldWidget vs widget diff.
    // In production [TimelineStore.messages] returns an UnmodifiableListView
    // over the same mutable underlying list, so `oldWidget.messages` and
    // `widget.messages` always share identical contents at this point — the
    // diff-based gate would silently never fire (see PR #664 / Issue #670).
    //
    // Issue #670 round-1 review (変化): detect a transition to an empty
    // messages list (e.g. timeline clear on `onReconnectSameLv`) and arm a
    // one-shot silent seed for the next non-empty observation so backfill
    // is absorbed without retroactively firing the gated callbacks.
    //
    // Detection cannot rely on `oldWidget.messages.isNotEmpty` because in
    // production [TimelineStore.messages] is an [UnmodifiableListView] over
    // a single mutable list, so once the underlying backing is cleared,
    // BOTH `oldWidget.messages` and `widget.messages` resolve to the same
    // (empty) view. The state-local cursor is the only durable record of
    // "we previously saw a non-empty tail", so we test against it instead.
    if (widget.messages.isEmpty && _lastProcessedTailMessageId != null) {
      _lastProcessedTailMessageId = null;
      _seedNextTailObservationSilently = true;
      _recentlyProcessedNicknameMessageIds.clear();
    }
    final String? currentTailMessageId = widget.messages.isNotEmpty
        ? widget.messages.last.id
        : null;
    final bool hasNewTailMessage =
        currentTailMessageId != null &&
        currentTailMessageId != _lastProcessedTailMessageId;
    if (hasNewTailMessage) {
      if (_seedNextTailObservationSilently) {
        // First observation after an empty-transition: adopt the current
        // tail without retroactively replaying backfill through the gated
        // callbacks. Subsequent rebuilds compare against this seed and
        // only fire on genuinely newer arrivals.
        _seedNextTailObservationSilently = false;
        _lastProcessedTailMessageId = currentTailMessageId;
      } else {
        final String? cursor = _lastProcessedTailMessageId;
        // Log new comment texts for debugging.
        _logNewComments(cursor, widget.messages);
        _requestUserNameResolutionForNewMessages(cursor, widget.messages);
        _processNicknameComments(cursor, widget.messages);
        _processNgProtectionNotifications(widget.messages);
        _lastProcessedTailMessageId = currentTailMessageId;
      }
    }

    // Auto-scroll detection uses an independent, state-tracked cursor so
    // that newly arrived live comments reliably trigger a scroll-to-tail
    // even when `oldWidget.messages` and `widget.messages` are two views
    // over the same mutable list in [TimelineStore] (in which case
    // `_hasNewMessages` would see equal snapshots and return false).
    final String? currentLastId = widget.messages.isNotEmpty
        ? widget.messages.last.id
        : null;
    final bool hasNewLatestMessage =
        currentLastId != null && currentLastId != _lastAutoScrollObservedLastId;
    if (hasNewLatestMessage) {
      _lastAutoScrollObservedLastId = currentLastId;
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
    // Issue #739: cancel any in-flight broadcast-end grace timer so it
    // cannot fire after dispose and call into a torn-down widget.
    _speechGraceTimer?.cancel();
    _speechGraceTimer = null;
    _isInSpeechGrace = false;
    _speechEventSub?.cancel();
    widget.speechConfig.androidTtsAvailability?.removeListener(
      _onAndroidTtsAvailabilityChanged,
    );
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
    // Release memoization cache eagerly on tear-down. GC would reclaim
    // the map anyway, but explicit clear avoids holding onto potentially
    // many String entries until the next GC cycle.
    _normalizedContentCache.clear();
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
    String? cursorMessageId,
    List<AppMessage> newMessages,
  ) {
    final UserNameResolution? resolution = widget.userNameResolution;
    if (resolution == null) {
      return;
    }

    final int start = _sliceStartFromCursor(cursorMessageId, newMessages);
    for (int i = start; i < newMessages.length; i++) {
      final String? userId = newMessages[i].userId;
      if (userId != null && userId.isNotEmpty) {
        resolution.requestResolve(userId);
      }
    }
  }

  void _logNewComments(String? cursorMessageId, List<AppMessage> newMessages) {
    final int start = _sliceStartFromCursor(cursorMessageId, newMessages);
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

  /// Locates the slice index `start` such that `messages[start..]` are the
  /// items that arrived after [cursorMessageId].
  ///
  /// - `cursorMessageId == null` → process the whole list (first observation).
  /// - cursor found in [messages] → start one past it.
  /// - cursor missing (rotated out of the ring buffer) → fall back to `0` so
  ///   that hits during rotation are not silently swallowed. This trades a
  ///   possible one-shot over-process for never losing a message.
  int _sliceStartFromCursor(
    String? cursorMessageId,
    List<AppMessage> messages,
  ) {
    if (cursorMessageId == null || messages.isEmpty) {
      return 0;
    }
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == cursorMessageId) {
        return i + 1;
      }
    }
    return 0;
  }

  // ---------------------------------------------------------------------------
  // Speech (VoiceVox) integration
  // ---------------------------------------------------------------------------

  /// Single write point for [_speechEngineState] (Issue #717 / ARCH-2 +
  /// Issue #712 / UX-1).
  ///
  /// All 4 historical source paths funnel through here:
  ///   1. native engine event (`engine_state_changed`)
  ///   2. cross-screen notifier listener (PR #704)
  ///   3. local init failure (#695, #696)
  ///   4. `speech_completed` recovery heuristic (PR #707 / #695)
  ///
  /// Behavioural contract:
  ///   * No-op when [next] equals the current value (avoids spurious
  ///     setState rebuilds).
  ///   * When mounted, wraps the assignment in `setState` so the AppBar
  ///     icon rebuilds; otherwise updates the field without setState
  ///     so reads stay consistent during dispose.
  ///   * Issue #712: on a `prev != error && next == error` transition,
  ///     queues a SnackBar via [_showSpeechErrorSnackBar] (post-frame
  ///     so the ScaffoldMessenger is reachable) and sets
  ///     [_speechErrorNotified] to suppress duplicates inside the same
  ///     episode.
  ///   * Issue #712: on any transition out of error
  ///     (`prev == error && next != error`), resets
  ///     [_speechErrorNotified] so the next fresh ERROR episode can
  ///     fire a new SnackBar.
  ///
  /// Invoke from OUTSIDE any caller's own `setState` block — the helper
  /// performs its own `setState` only when needed.
  void _setSpeechEngineState(SpeechEngineState next) {
    final SpeechEngineState prev = _speechEngineState;
    if (prev == next) return;
    if (!mounted) {
      _speechEngineState = next;
      return;
    }
    setState(() {
      _speechEngineState = next;
    });
    final bool enteredError =
        prev != SpeechEngineState.error && next == SpeechEngineState.error;
    final bool leftError =
        prev == SpeechEngineState.error && next != SpeechEngineState.error;
    if (enteredError && !_speechErrorNotified) {
      _speechErrorNotified = true;
      _showSpeechErrorSnackBar();
    } else if (leftError) {
      _speechErrorNotified = false;
    }
  }

  /// Schedules a SnackBar that announces the TTS engine error and offers
  /// a one-tap shortcut into the read-aloud settings screen (Issue #712 /
  /// UX-1). Posted in a post-frame callback so callers from inside a
  /// build() / setState() can invoke us without violating Flutter's
  /// "ScaffoldMessenger.of(context) must not be called during build"
  /// invariant.
  void _showSpeechErrorSnackBar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Defensive re-check: between the setter setting the flag and
      // the post-frame callback firing, another mutation path could
      // have moved the engine out of ERROR (e.g. a `speech_completed`
      // recovery for Android TTS). Suppress the SnackBar if the
      // ERROR episode no longer applies, to avoid surprising the user
      // with a notification for a state they cannot observe.
      if (_speechEngineState != SpeechEngineState.error) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      // Hide only the currently-visible SnackBar, NOT the queue, so
      // unrelated NG-protection notifications already in flight are
      // not silently dropped (mirrors the comment-post feedback path).
      messenger.hideCurrentSnackBar();
      final SettingsStore? settingsStore = widget.speechConfig.settingsStore;
      messenger.showSnackBar(
        SnackBar(
          key: const Key('speech-error-snackbar'),
          content: const Text('読み上げエンジンでエラーが発生しました'),
          duration: const Duration(seconds: 6),
          action: settingsStore == null
              // When no SettingsStore is wired (rare, e.g. in tests
              // without persistence), drop the action button — there is
              // no destination to navigate to. The hint itself still
              // surfaces.
              ? null
              : SnackBarAction(
                  label: '設定を開く',
                  onPressed: () {
                    if (!mounted) return;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => TtsSettingsScreen(
                          settingsStore: settingsStore,
                          platform: widget.speechConfig.speechPlatform,
                          // `initialSettings: null` causes the screen
                          // to load fresh from `settingsStore` on
                          // mount — preferred here because the user
                          // came in from an ERROR notification and may
                          // have edited persisted state outside the
                          // current session.
                          androidTtsAvailability:
                              widget.speechConfig.androidTtsAvailability,
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
    });
  }

  /// Issue #713 (UX-2): retry handler wired to the AppBar speech icon
  /// when the engine is in ERROR. Resets [_initializedEngineType] so the
  /// next call to [_initializeAndStartSpeech] re-runs the full setup
  /// (model load + start) instead of short-circuiting on the cached
  /// "already initialised" branch.
  ///
  /// Multi-tap protection: [_initializeAndStartSpeech] early-returns
  /// when [_speechInitializing] is true, so rapid double-taps cannot
  /// re-enter the init path concurrently. We do NOT clear
  /// [_speechEngineState] here — the icon stays on ERROR until the
  /// init result determines the new state, mirroring the existing
  /// "toggle off/on" recovery flow.
  void _retrySpeechAfterError() {
    if (_speechInitializing) return;
    _initializedEngineType = null;
    unawaited(_initializeAndStartSpeech());
  }

  Future<void> _initializeAndStartSpeech() async {
    _debugLogLazy(
      () =>
          '[CommentScreen] initSpeech: enter '
          '(initializing=$_speechInitializing, '
          'initializedFor=$_initializedEngineType, '
          'currentEngine=${widget.speechConfig.speechSettings.engineType})',
    );
    if (_speechInitializing) return;
    final CommentSpeechPlatform? platform = widget.speechConfig.speechPlatform;
    if (platform == null) {
      _debugLog('[CommentScreen] initSpeech: platform=null, abort');
      return;
    }
    _speechInitializing = true;

    // Check if engine is already ready from a previous session.
    // We also surface a previously-stuck ERROR (e.g. VOICEVOX setup was
    // cancelled / failed in a prior call) to the AppBar icon so the user
    // does not see a perpetual "hourglass" while native already knows
    // initialization failed. See `_SpeechStatusIcon` for the icon priority.
    if (!_isInitializedForCurrentEngine) {
      _debugLog('[CommentScreen] initSpeech: checking engine status...');
      try {
        final SpeechRuntimeStatus status = await platform.getStatus();
        _debugLogLazy(
          () =>
              '[CommentScreen] initSpeech: engine=${status.engineState}, '
              'player=${status.playerState}, queue=${status.queueSize}',
        );
        if (status.engineState == 'READY') {
          _initializedEngineType =
              widget.speechConfig.speechSettings.engineType;
          _debugLog('[CommentScreen] initSpeech: engine already READY');
          // Round-2 post-merge review: clear any stale `_speechEngineState
          // == 'ERROR'` left over from a previous failed init attempt
          // (e.g. setup cancelled, then native recovered on its own and
          // now reports READY). Without this, the icon priority logic
          // would render `error_outline` even though the engine is
          // actually ready, because the start() success path that
          // normally sets state='READY' is reached only after a few
          // awaits and the icon would briefly flicker ERROR in between.
          if (_speechEngineState == SpeechEngineState.error) {
            _setSpeechEngineState(SpeechEngineState.unknown);
          }
        } else if (status.engineState == 'ERROR') {
          _setSpeechEngineState(SpeechEngineState.error);
        }
      } catch (e) {
        _errorLog('[CommentScreen] initSpeech: getStatus failed', error: e);
        // Issue #696 cycle-2-new review: a thrown getStatus is, from the
        // user's perspective, the same kind of "the engine is not usable"
        // signal as `engineState == 'ERROR'`. Without this branch the
        // AppBar would stay on the neutral "hourglass" icon while native
        // is in a broken state, which is the same hourglass-stuck bug
        // Issue #696 was supposed to eliminate.
        //
        // Round-2 review note: control intentionally falls through to the
        // setup dialog below. A getStatus failure does not necessarily
        // mean the engine is permanently broken — it may be a transient
        // platform-channel hiccup, in which case the setup dialog can
        // still bring the engine to ready and the success path further
        // down sets `_speechEngineState='READY'` again, naturally
        // clearing the ERROR we just set. An early return here would
        // remove the user's only recovery path within this init attempt.
        _setSpeechEngineState(SpeechEngineState.error);
      }
    }

    // Show setup dialog for first-time download & initialization.
    // Android TTS does not require VOICEVOX assets, so skip the dialog.
    final bool isAndroidTts =
        widget.speechConfig.speechSettings.engineType ==
        SpeechEngineType.androidTts;
    if (!_isInitializedForCurrentEngine && !isAndroidTts) {
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
        // VOICEVOX setup failed or was cancelled by the user. Mirror the
        // Android TTS branch below: surface ERROR to the AppBar icon so the
        // user can distinguish a real failure from "still initializing"
        // (Issue #696). _initializedEngineType stays null so toggling
        // speech off/on retries from scratch.
        _setSpeechEngineState(SpeechEngineState.error);
        _speechInitializing = false;
        return;
      }
      _initializedEngineType = widget.speechConfig.speechSettings.engineType;
    } else if (!_isInitializedForCurrentEngine && isAndroidTts) {
      // Android TTS does not need the setup dialog, but the native speaker
      // still has to be brought to ready state. Without this step
      // AndroidTtsSpeaker stays ready=false and later `start()` →
      // `processWithAndroidTts()` silently drops every comment
      // (`android_tts_not_ready`).
      //
      // We deliberately use `checkAndroidTtsAvailability()` instead of the
      // generic `platform.initialize()`. The native "initialize" handler
      // drives VOICEVOX engine init as well, which would (a) load tens of
      // megabytes of VVM files that an Android-TTS-only user never needs,
      // and (b) fail with `MissingAssetsException` for users who never
      // downloaded VOICEVOX dict/VVM — masking a perfectly functional
      // Android TTS as an error. `checkAndroidTtsAvailability` touches only
      // `AndroidTtsSpeaker.initialize()` on the native side (see
      // CommentSpeechPlugin.kt "checkAndroidTtsAvailability" handler), which
      // is exactly what this branch needs.
      _debugLog(
        '[CommentScreen] initSpeech: Android TTS → checkAndroidTtsAvailability()',
      );
      try {
        final bool available = await platform.checkAndroidTtsAvailability();
        // Issue #694: keep the cross-screen notifier in sync so the TTS
        // settings screen (and any other subscriber) sees the same result
        // without re-running the check.
        widget.speechConfig.androidTtsAvailability?.publish(
          available: available,
        );
        if (!mounted) {
          _speechInitializing = false;
          return;
        }
        if (!available) {
          _errorLog(
            '[CommentScreen] initSpeech: Android TTS not available '
            '(Japanese voice data missing or engine failed to initialize)',
          );
          // Surface the failure via the ERROR icon. The status icon widget
          // evaluates engineState=='ERROR' BEFORE !isInitialized, so the
          // user sees "エラー" (not a stuck hourglass) even though
          // _initializedEngineType stays null. Keeping it null also
          // preserves the retry path: if the user toggles speech off and
          // on again, this branch will run again and re-check.
          _setSpeechEngineState(SpeechEngineState.error);
          _speechInitializing = false;
          return;
        }
        _initializedEngineType = widget.speechConfig.speechSettings.engineType;
      } catch (e, stackTrace) {
        _errorLog(
          '[CommentScreen] initSpeech: Android TTS availability check FAILED',
          error: e,
          stackTrace: stackTrace,
        );
        // Treat a thrown availability check as unavailable for cross-screen
        // consumers — the user-visible outcome is the same (no usable TTS).
        widget.speechConfig.androidTtsAvailability?.publishUnavailable();
        // Same reasoning as the (!available) branch above: leave
        // _initializedEngineType=null so the user can retry by toggling
        // speech off/on. The ERROR engine state drives the icon regardless.
        _setSpeechEngineState(SpeechEngineState.error);
        _speechInitializing = false;
        return;
      }
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
        _setSpeechEngineState(SpeechEngineState.unknown);
        // Issue #695: counter must also be reset on abort, not just on the
        // _stopSpeech path. Otherwise a stale Android-TTS failure tally from
        // a previous session can spill into the next attempt.
        _consecutiveAndroidTtsFailures = 0;
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
        });
        _setSpeechEngineState(SpeechEngineState.ready);
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
      _setSpeechEngineState(SpeechEngineState.error);
    } finally {
      _speechInitializing = false;
    }
  }

  Future<void> _handleSpeechSettingsChanged(SpeechSettings oldSettings) async {
    final SpeechSettings newSettings = widget.speechConfig.speechSettings;
    _debugLogLazy(
      () =>
          '[CommentScreen] settingsChanged: enabled ${oldSettings.enabled}→'
          '${newSettings.enabled}, '
          'engine ${oldSettings.engineType}→${newSettings.engineType}, '
          'started=$_speechStarted',
    );
    // engineType changed → tear down and re-initialize for the new engine.
    // Without this branch, the flow falls through to updateSettings which
    // does NOT run engine.initialize() on the native side, leaving the new
    // engine uninitialized. See issue #734.
    //
    // Also reset the failure counter on the engine-type change so failures
    // from the old engine cannot accumulate into a false ERROR for the new
    // engine (Issue #695 review #8).
    if (oldSettings.engineType != newSettings.engineType) {
      _debugLog(
        '[CommentScreen] settingsChanged: → engineType changed, '
        're-initializing speech engine',
      );
      // Reset here covers the case where _speechStarted is false (then
      // _stopSpeech is skipped); when _speechStarted is true, _stopSpeech
      // also resets the counter — the duplication is intentional.
      _consecutiveAndroidTtsFailures = 0;
      if (_speechStarted) {
        await _stopSpeech();
      }
      // Drop the previous engine's "ready" state so _initializeAndStartSpeech
      // re-runs the full setup path (status check → setup dialog if needed
      // → updateSettings → start) for the new engine.
      _initializedEngineType = null;
      if (newSettings.enabled) {
        await _initializeAndStartSpeech();
      }
      return;
    }

    if (!oldSettings.enabled && newSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → enabling speech');
      await _initializeAndStartSpeech();
    } else if (oldSettings.enabled && !newSettings.enabled) {
      _debugLog('[CommentScreen] settingsChanged: → disabling speech');
      // Issue #739: an explicit user-driven "disable speech" must override
      // any in-flight grace and stop now, not 30 s later.
      _cancelSpeechGrace(reason: 'speech_disabled_by_user');
      await _stopSpeech();
    } else if (newSettings.enabled && _speechStarted) {
      _debugLog('[CommentScreen] settingsChanged: → pushing update to engine');
      try {
        await widget.speechConfig.speechPlatform?.updateSettings(newSettings);
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
      _consecutiveAndroidTtsFailures = 0;
      if (mounted) {
        setState(() {
          _speechStarted = false;
        });
        _setSpeechEngineState(SpeechEngineState.unknown);
      }
    }
  }

  /// Issue #739: maximum time we keep the speech queue alive after a
  /// broadcast ends, so the last few comments can finish reading. Matches
  /// [ForegroundServiceController]'s grace window (30 s) on purpose so the
  /// FGS notification and the speech queue tear down at roughly the same
  /// time.
  static const Duration _speechGraceDuration = Duration(seconds: 30);

  /// Called once on the `idle/reconnecting/streaming → ended` edge. Either
  /// stops speech immediately (grace disabled or no live queue) or arms
  /// [_speechGraceTimer] so the queue can drain naturally.
  void _onBroadcastEnded() {
    final bool graceEnabled = widget.speechConfig.playRemainingAfterEnded;
    if (!graceEnabled || !_speechStarted) {
      // Pre-#739 behaviour: stop immediately.
      unawaited(_stopSpeech());
      return;
    }
    _debugLog(
      '[CommentScreen] broadcastEnded: starting grace '
      '(${_speechGraceDuration.inSeconds}s)',
    );
    _speechGraceTimer?.cancel();
    _isInSpeechGrace = true;
    _speechGraceTimer = Timer(_speechGraceDuration, () {
      // Grace window expired — even if comments remain, force-stop so the
      // engine and the FGS do not linger forever.
      _endSpeechGrace(reason: 'timeout');
    });
  }

  /// Cancels the grace timer without firing the deferred stop. Used when
  /// the connection transitions to a non-ended status (reconnect / manual
  /// stop) — those branches drive their own teardown.
  void _cancelSpeechGrace({required String reason}) {
    if (!_isInSpeechGrace && _speechGraceTimer == null) {
      return;
    }
    _debugLog('[CommentScreen] grace: cancelled ($reason)');
    _speechGraceTimer?.cancel();
    _speechGraceTimer = null;
    _isInSpeechGrace = false;
  }

  /// Completes the grace window, firing the deferred `_stopSpeech` exactly
  /// once. [reason] is recorded in debug logs for AC4 traceability.
  void _endSpeechGrace({required String reason}) {
    if (!_isInSpeechGrace && _speechGraceTimer == null) {
      return;
    }
    _debugLog('[CommentScreen] grace: ending ($reason)');
    _speechGraceTimer?.cancel();
    _speechGraceTimer = null;
    _isInSpeechGrace = false;
    // Notify the FGS controller so its parallel grace timer can end early
    // too. The callback is no-op when not in FGS-grace, so calling on every
    // reason (timeout / queue_drained / cancel) is safe.
    widget.speechConfig.onSpeechQueueDrained?.call();
    if (!mounted) {
      // Widget already torn down — dispose() will (or did) call stop().
      return;
    }
    unawaited(_stopSpeech());
  }

  /// Listener for [SpeechAvailabilityNotifier] changes.
  ///
  /// Issue #694 cycle-2-new review: when the cross-screen notifier publishes
  /// `available` (e.g. user re-installed Japanese voice data via TTS
  /// settings), the local `_speechEngineState` may still hold the previous
  /// `'ERROR'` from this screen's own failed init. The icon's OR-condition
  /// then keeps it on `error_outline` even though `treatAsError` flipped to
  /// false. Clearing the local ERROR here lets the next user toggle (or
  /// `didUpdateWidget` retrigger) re-init from a clean slate.
  ///
  /// **State-double-management note (round-2 review):** `_speechEngineState`
  /// is normally written by native engine events. This listener writes to
  /// the same field as a *display-time* heuristic — only when the active
  /// engine is Android TTS AND a true recovery has been observed in another
  /// screen. The engineType gate is critical: without it, a stray publish
  /// during engine swap (or a future helper that publishes from VOICEVOX
  /// flows) would erase a real VOICEVOX ERROR.
  ///
  /// **Cross-PR integration note:** PR #695 (runtime failure counter) is
  /// now also in main, so this listener additionally resets
  /// `_consecutiveAndroidTtsFailures = 0`. Without that reset, a recovery
  /// published via settings would leave the counter at threshold and the
  /// next single transient failure would re-trip ERROR (= "fixed but
  /// immediately broken again" UX). Resolves Issue #711 (CR-1).
  void _onAndroidTtsAvailabilityChanged() {
    // Wrap the body so a single buggy listener invocation cannot tear
    // down the ChangeNotifier's listener list (which would silently
    // disable cross-screen propagation across the entire app for
    // subsequent publishes). MAQR ③ 堅牢の賢者 review.
    try {
      _onAndroidTtsAvailabilityChangedInner();
    } catch (e, stackTrace) {
      _errorLog(
        '[CommentScreen] _onAndroidTtsAvailabilityChanged: handler threw',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onAndroidTtsAvailabilityChangedInner() {
    final SpeechAvailabilityNotifier? notifier =
        widget.speechConfig.androidTtsAvailability;
    if (notifier == null) return;
    if (notifier.value != SpeechAvailability.available) return;
    // Engine-type gate: only the Android TTS engine has its availability
    // tracked by this notifier. Any local ERROR while VOICEVOX is the
    // active engine belongs to a different code path and must not be
    // silently cleared here (round-2 review #7 / #8).
    if (widget.speechConfig.speechSettings.engineType !=
        SpeechEngineType.androidTts) {
      return;
    }
    // Issue #711 (CR-1): #705's runtime failure counter must be reset on
    // cross-screen recovery, even when local ERROR was not yet set.
    // Otherwise a residual `_consecutiveAndroidTtsFailures == threshold`
    // would re-trip ERROR on the very next transient failure after the
    // user just observed a clean AppBar.
    _consecutiveAndroidTtsFailures = 0;
    if (_speechEngineState != SpeechEngineState.error) return;
    _setSpeechEngineState(SpeechEngineState.unknown);
  }

  // The literal wire-format strings for Android-TTS failure reasons live
  // in `SpeechFailureReason` (see lib/comment_speech/src/models/
  // speech_failure_reason.dart). That sealed class is the SSOT shared
  // with the Kotlin contract test (`PrefixContract`) and locks the
  // native↔Dart drift that PR #705 Cycle 2 originally surfaced.

  void _onSpeechEvent(SpeechEvent event) {
    // The events stream is shared with native and any exception in this
    // listener would tear down the StreamSubscription, silently breaking
    // all future event delivery. Wrap the entire body so a malformed
    // payload (e.g. wrong type for `state` / `reason`) cannot poison the
    // subscription (Issue #695 review #7).
    try {
      _onSpeechEventInner(event);
    } catch (e, stackTrace) {
      _errorLog(
        '[CommentScreen] _onSpeechEvent: handler threw',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _onSpeechEventInner(SpeechEvent event) {
    _debugLogLazy(
      () =>
          '[CommentScreen] speechEvent: ${event.type}, payload=${event.payload}',
    );
    // Issue #739: if we are in the broadcast-end grace window, an empty
    // queue means there is nothing left to read — finish immediately
    // instead of waiting out the full 30s.
    if (event.type == SpeechEventType.queueUpdated && _isInSpeechGrace) {
      final dynamic rawSize = event.payload['size'];
      final int? size = rawSize is num
          ? rawSize.toInt()
          : (rawSize is String ? int.tryParse(rawSize) : null);
      if (size == 0) {
        _endSpeechGrace(reason: 'queue_drained');
      }
    }
    if (event.type == SpeechEventType.engineStateChanged) {
      // Defensive cast: native is expected to send a String here, but a
      // malformed payload must not crash the listener (Issue #695 review #7).
      // [SpeechEngineState.fromWire] also performs the defensive default
      // (unknown wires map to [SpeechEngineState.unknown]).
      final dynamic rawState = event.payload['state'];
      final String state = rawState is String ? rawState : '';
      final SpeechEngineState nextState = SpeechEngineState.fromWire(state);
      // Issue #695 cycle-3 review: a READY transition is a strong signal
      // that the engine is alive again — reset the failure counter so a
      // single subsequent transient failure cannot push us right back to
      // ERROR (counter was at threshold, +1 stays over threshold).
      if (nextState == SpeechEngineState.ready) {
        _consecutiveAndroidTtsFailures = 0;
      }
      _setSpeechEngineState(nextState);
      return;
    }
    if (event.type == SpeechEventType.speechFailed) {
      // Only Android TTS runtime failures are tracked here; VOICEVOX uses
      // distinct messages (synthesis_failed / playback_failed) that the
      // existing VOICEVOX flow handles via its own engineStateChanged path.
      //
      // The native payload uses `message` as the key (see
      // `SpeechEvents.kt:speechFailed`). The Android-TTS-specific values
      // emitted by `SpeechControllerImpl.processWithAndroidTts` are
      // `"android_tts_not_ready"` (engine-not-ready guard) and
      // `"android_tts_failed: <inner>"` (any other speak() failure — the
      // prefix is added explicitly on the native side so the inner
      // exception message does not slip past this detector).
      final dynamic rawMessage = event.payload['message'];
      final String message = rawMessage is String ? rawMessage : '';
      // Route through the SSOT (Issue #716): a non-null parse means the
      // payload is one of the known Android-TTS failure reasons. Behaviour
      // is byte-identical to the previous inline `==` / `startsWith` pair.
      final bool isAndroidTtsFailure =
          SpeechFailureReason.fromMessage(message) != null;
      if (isAndroidTtsFailure) {
        _consecutiveAndroidTtsFailures++;
        if (_consecutiveAndroidTtsFailures >= _androidTtsErrorThreshold &&
            _speechEngineState != SpeechEngineState.error) {
          _setSpeechEngineState(SpeechEngineState.error);
        }
      }
      return;
    }
    if (event.type == SpeechEventType.speechCompleted) {
      // Any successful speak proves the engine is alive again — reset the
      // counter so a single transient failure later cannot push us straight
      // back to ERROR.
      if (_consecutiveAndroidTtsFailures != 0) {
        _consecutiveAndroidTtsFailures = 0;
      }
      // Issue #695 cycle-2-new-1 review: native does NOT emit a runtime
      // engineStateChanged → READY for Android TTS recovery (only at
      // initialize). Without this branch the AppBar stays on ERROR forever
      // after a single threshold-tripping failure, even when subsequent
      // speak calls succeed. A successful `speech_completed` is the only
      // recovery signal we have, so use it to flip the AppBar back too.
      //
      // Round-2 review #2/#8 — gate this heuristic recovery on engineType.
      // A `speech_completed` event arriving from a VOICEVOX completion that
      // races with an engine swap must NOT silently clear an ERROR caused
      // by Android TTS. The counter is only ever incremented for
      // Android-TTS-specific reasons (see speechFailed branch above), so
      // the matching recovery must also be Android-TTS-specific.
      final bool isAndroidTtsActive =
          widget.speechConfig.speechSettings.engineType ==
          SpeechEngineType.androidTts;
      if (isAndroidTtsActive && _speechEngineState == SpeechEngineState.error) {
        _setSpeechEngineState(SpeechEngineState.ready);
      }
      return;
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
        // Issue #758: in foreground, didUpdateWidget propagates the latest
        // TimelineStore snapshot to widget.messages. In background the
        // widget tree rebuild is paused (Flutter engine suspends frame
        // scheduling), so widget.messages remains the snapshot captured
        // at the last build before backgrounding. Read directly from the
        // store here so the poll timer always sees the current snapshot.
        // PR #721 made the messages getter return a cached view that is
        // replaced on every mutation, so direct reads are always fresh.
        // Falls back to widget.messages when no store is wired (tests).
        final List<AppMessage> latest =
            widget.speechConfig.timelineStore?.messages ?? widget.messages;
        _submitNewCommentsForSpeech(latest);
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
      if (userId != null && widget.contentFilter.ngUserIds.contains(userId)) {
        _debugLogLazy(
          () => '[CommentScreen] submitComment: SKIP NG user=$userId',
        );
        continue;
      }
      // Skip star-prefix hidden comments.
      if (widget.contentFilter.starPrefixHidingEnabled &&
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
      if (widget.contentFilter.slashPrefixSkipEnabled &&
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
  /// Delegates to the screen-local [NgMatcher]. Behavior matches the
  /// pre-#613 implementation: a hit on any preset or user NG word returns
  /// `true`, regardless of display preferences. The two-axis
  /// display/speech split is exposed separately through
  /// [NgMatcher.shouldBlockDisplay] / [NgMatcher.shouldBlockSpeech].
  bool _containsNgWord(String content) {
    return _ngMatcher.match(content) != null;
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
    String? cursorMessageId,
    List<AppMessage> newMessages,
  ) {
    if (!widget.autoNicknameRegistration ||
        widget.callbacks.onNicknameChanged == null) {
      return;
    }

    final int start = _sliceStartFromCursor(cursorMessageId, newMessages);
    for (int i = start; i < newMessages.length; i++) {
      final AppMessage message = newMessages[i];
      if (message.type != AppMessageType.chat) {
        continue;
      }
      final String? userId = message.userId;
      if (userId == null || userId.isEmpty) {
        continue;
      }
      // Issue #670 round-1 review (感性 / 価値): the
      // `_sliceStartFromCursor` fallback to "process the whole tail" on
      // ring-buffer rotation is acceptable for log / userName-resolve /
      // NG-protection (where re-emission is harmless or already accounted
      // for) but NOT for nickname registration: replaying an older `@A`
      // comment after the user has issued a newer `@B` would silently
      // overwrite the more recent registration. De-duplicate by message
      // id so each `@`-comment registers exactly once for the lifetime
      // of this screen.
      if (_recentlyProcessedNicknameMessageIds.contains(message.id)) {
        continue;
      }
      final String content = message.content;
      if (!content.startsWith('@')) {
        continue;
      }
      _recordNicknameMessageProcessed(message.id);
      final String nickname = content.substring(1).trim();
      if (nickname.isEmpty) {
        // `@` のみ → コテハン解除
        widget.callbacks.onNicknameRemoved?.call(userId);
      } else {
        widget.callbacks.onNicknameChanged!.call(userId, nickname);
      }
    }
  }

  void _recordNicknameMessageProcessed(String messageId) {
    if (_recentlyProcessedNicknameMessageIds.length >=
        _kRecentlyProcessedNicknameIdsCap) {
      _recentlyProcessedNicknameMessageIds.clear();
    }
    _recentlyProcessedNicknameMessageIds.add(messageId);
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
      vposBaseAt: widget.programInfo.vposBaseAt,
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

    final String message = commentPostErrorMessage(result);
    messenger.showSnackBar(
      SnackBar(
        key: const Key('comment-post-error-snackbar'),
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Announces NG-filter protection for comments appended since the last
  /// call. The badge counter always increases on every NG hit, while the
  /// snackbar is throttled to at most one per [_protectionSnackBarWindow].
  ///
  /// No-op when [ContentFilterConfig.ngProtectionNotificationEnabled] is
  /// false (existing silent behavior is preserved).
  void _processNgProtectionNotifications(List<AppMessage> newMessages) {
    if (!widget.contentFilter.ngProtectionNotificationEnabled) {
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
      // Gift / nicoad are excluded from NG filtering by design (they are
      // never silenced; see [_shouldDisplayMessage]).
      if (message.type == AppMessageType.gift ||
          message.type == AppMessageType.nicoad) {
        continue;
      }
      // Honor per-type visibility toggles (operator / system / emotion).
      // A message the user has explicitly hidden must not also trigger a
      // protection notification — announcing protection for something the
      // user asked not to see is a semantic contradiction.  Delegated to
      // [_isTypeVisible] (single source of truth shared with
      // [_shouldDisplayMessage]).
      if (!_isTypeVisible(message.type)) {
        continue;
      }
      if (_isSystemBroadcastEndedMessage(message)) {
        continue;
      }

      final String? userId = message.userId;
      final bool isNgUser =
          userId != null && widget.contentFilter.ngUserIds.contains(userId);
      final String? matchedWord = _matchedNgWord(message.content);
      if (!isNgUser && matchedWord == null) {
        continue;
      }

      // Issue #615: when the user opted the matched subcategory back on,
      // the comment is visible in the list. Announcing protection for
      // something the viewer actually sees is misleading, so such matches
      // are skipped from both the badge and the snackbar. NG-user hits are
      // unaffected (those comments remain hidden), and user-configured NG
      // words keep being counted because they carry no subcategory —
      // shouldBlockDisplay always returns true for them.
      if (matchedWord != null && !isNgUser) {
        if (!_ngMatcher.shouldBlockDisplay(
          message.content,
          widget.contentFilter.ngDisplayPreferences,
        )) {
          continue;
        }
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

    // Resolve the clock seam:
    //   - [widget.clock] when the caller injects an explicit Clock.
    //   - The top-level `clock` getter from `package:clock` otherwise. This
    //     delegates to [DateTime.now()] in production but is observable by
    //     `withClock(...)` in tests, so test scopes can freeze time without
    //     rebuilding the widget.
    final Clock activeClock = widget.clock ?? clock;
    final DateTime now = activeClock.now();
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

    // Suppress the snackbar while the user is in comment-search mode so it
    // does not fight with the IME keyboard (SnackBarBehavior.floating would
    // otherwise overlap / hide behind the keyboard on narrow screens and
    // some iOS layouts). The badge still increments, so no NG hit is lost —
    // the user can read the count once they close the search bar. The
    // existing Semantics on the badge announces the count for TalkBack.
    //
    // Design note: this early return intentionally does NOT update
    // [_lastProtectionNotificationAt], so the throttle window does not
    // advance during search. When the user closes the search bar, the
    // first subsequent NG hit fires the snackbar immediately (the window
    // has already elapsed from the pre-search timestamp).
    if (_isSearching) {
      return;
    }

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

  /// Returns the matched NG word pattern in [content] (normalized, as used
  /// by [_containsNgWord]), or `null` when nothing matches.
  ///
  /// Delegates to the screen-local [NgMatcher]. The pattern string returned
  /// here is the normalized form (same as pre-#613 behavior), which is
  /// what the protection snackbar expects.
  String? _matchedNgWord(String content) {
    return _ngMatcher.match(content)?.matchedPattern;
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
    // All such categories are centralized in [removeControlAndInvisibleChars].
    final String withoutControls = removeControlAndInvisibleChars(value);
    final String collapsed = withoutControls
        .replaceAll(_singleLineWhitespacePattern, ' ')
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
                          isInitialized: _isInitializedForCurrentEngine,
                          isMuted: widget.speechConfig.isSpeechMuted,
                          themeColors: themeColors,
                          onTap: widget.callbacks.onSpeechMuteToggled,
                          // Issue #713 (UX-2): in ERROR state the
                          // mute toggle is disabled by design (see
                          // canToggleMute in _SpeechStatusIcon). Wire a
                          // separate retry callback so the icon becomes
                          // tappable in ERROR and the user can recover
                          // without leaving the screen. Multi-tap
                          // protection is provided by the existing
                          // _speechInitializing guard inside
                          // _initializeAndStartSpeech (early return).
                          onRetry: _retrySpeechAfterError,
                          // Issue #694: Android-TTS-only override. The
                          // icon listens to this notifier and surfaces
                          // ERROR when other screens (e.g. TTS settings)
                          // detect that Japanese voice data is missing,
                          // even before the user reconnects.
                          androidTtsAvailability:
                              widget.speechConfig.speechSettings.engineType ==
                                  SpeechEngineType.androidTts
                              ? widget.speechConfig.androidTtsAvailability
                              : null,
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
                      if (widget
                              .contentFilter
                              .ngProtectionNotificationEnabled &&
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
                  broadcasterUserId: widget.programInfo.broadcasterUserId,
                  beginAt: widget.programInfo.beginAt,
                  endedAt: _endedAt,
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
                if (widget.timeshiftFetchController != null)
                  TimeshiftFetchPanel(
                    key: const Key('timeshift-fetch-panel'),
                    controller: widget.timeshiftFetchController!,
                    onFetch500: () =>
                        widget.timeshiftFetchController!.fetchMore(500),
                    onFetch1000: () =>
                        widget.timeshiftFetchController!.fetchMore(1000),
                    onFetchAll: () =>
                        widget.timeshiftFetchController!.fetchAll(),
                    onCancel: () => widget.timeshiftFetchController!.cancel(),
                    onRetry: () =>
                        widget.timeshiftFetchController!.fetchMore(500),
                  ),
                if (_pinnedMessageIds.isNotEmpty)
                  _PinnedCommentsSection(
                    key: const Key('pinned-comments-section'),
                    pinnedMessages: _pinnedMessages(visibleMessages),
                    themeColors: themeColors,
                    showUserName: widget.showUserName,
                    fontSize: widget.commentFontSize,
                    resolveDisplayName: _resolveDisplayName,
                    userColorMap: widget.contentFilter.userColorMap,
                    onUnpin: _unpinMessage,
                    beginAt: widget.programInfo.beginAt,
                    commentTwoLineEnabled: widget.commentTwoLineEnabled,
                    commentTwoLineMetaFontPercent:
                        widget.commentTwoLineMetaFontPercent,
                    textScaler: textScaler,
                    ngMatcher: _ngMatcher,
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
                                  ? widget.contentFilter.userColorMap[message
                                        .userId!]
                                  : null;
                              return _CommentRow(
                                message: message,
                                themeColors: themeColors,
                                resolvedUserName: _resolveDisplayName(message),
                                showUserName: widget.showUserName,
                                fontSize: widget.commentFontSize,
                                textScaler: textScaler,
                                starPrefixHidingEnabled: widget
                                    .contentFilter
                                    .starPrefixHidingEnabled,
                                commentTwoLineEnabled:
                                    widget.commentTwoLineEnabled,
                                commentTwoLineMetaFontPercent:
                                    widget.commentTwoLineMetaFontPercent,
                                zebraStripingEnabled:
                                    widget.commentZebraStripingEnabled,
                                emphasizeGiftNicoadComment: widget
                                    .contentFilter
                                    .emphasizeGiftNicoadComment,
                                commentIndex: index,
                                userColor: userColor != null
                                    ? colorFromARGB32(userColor)
                                    : null,
                                onLongPress: () => _showCommentActions(message),
                                onOpenUrl: _showUrlConfirmDialog,
                                beginAt: widget.programInfo.beginAt,
                                ngMatcher: _ngMatcher,
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
                if (_pendingStats != null)
                  CommentLogStatsPanel(
                    key: const Key('stats-panel'),
                    stats: _pendingStats!,
                    themeMode: widget.themeMode,
                    expanded: _statsPanelExpanded,
                    programTitle: widget.programInfo.programTitle,
                    lv: widget.programInfo.lv,
                    highlightPickupEnabled:
                        widget.statistics.highlightPickupEnabled,
                    messages: _pendingStatsMessages,
                    ngUserIds: widget.contentFilter.ngUserIds,
                    onBarTapped: (int minuteOffset) {
                      _minimizeStatsPanel();
                      _scrollToMinuteOffset(minuteOffset);
                    },
                    onPeakTapped: (int minuteOffset) {
                      _minimizeStatsPanel();
                      _scrollToMinuteOffset(minuteOffset);
                    },
                    onToggleExpanded: _toggleStatsPanelExpanded,
                  ),
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
        final bool isNg = widget.contentFilter.ngUserIds.contains(userId);
        return UserDetailSheet(
          userId: userId,
          resolvedUserName: _resolveDisplayName(message),
          allMessages: widget.messages,
          isNgUser: isNg,
          themeMode: widget.themeMode,
          beginAt: widget.programInfo.beginAt,
          currentColorValue: widget.contentFilter.userColorMap[userId],
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
          nickname: widget.contentFilter.userNicknameMap[userId],
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
    // Issue #615: when the long-pressed comment is only on screen because
    // the user opted a display subcategory on, the speech engine still
    // skipped it. Surface that reason at the top of the sheet so the
    // broadcaster understands why TTS stayed silent for this row. A null
    // subcategory (unmatched or user-NG) yields no banner.
    final NgDisplaySubcategory? readSkippedSubcategory = _ngMatcher
        .match(message.content)
        ?.matchedSubcategory;

    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            key: const Key('comment-actions-sheet'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (readSkippedSubcategory != null)
                ListTile(
                  key: const Key('action-read-skipped-banner'),
                  leading: const Icon(Icons.volume_off),
                  title: const Text('読み上げ対象外'),
                  subtitle: Text(
                    '${displaySubcategoryLabel(readSkippedSubcategory)}を含むため'
                    '音声では読み上げられません',
                  ),
                  enabled: false,
                ),
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
      final String? nickname = widget.contentFilter.userNicknameMap[userId];
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
      final String? nickname = widget.contentFilter.userNicknameMap[userId];
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
    // Issue #774: 永続化は上位レイヤー (SelectScreen) に委譲する。
    // ここでは UI 状態を確定させた後の新しい値を通知するだけにとどめ、
    // SharedPreferences への書き込みは presentation 層から切り離す。
    widget.callbacks.onSortOrderChanged?.call(_sortOrder);
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
      // Issue #739 AC2: an explicit user-stop must drop any pending grace
      // window so the speech engine matches the user's intent, even if the
      // supervisor was still in `ended` (no manual-stop transition fired).
      _cancelSpeechGrace(reason: 'user_stop_for_exit');
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

    _updateEndedAtForStatus(currentStatus);

    if (!_isStoppingForExit && _isStatsTrigger(currentStatus)) {
      _showStatsPanel();
    }

    if (_lastStatus != ConnectionStatus.ended &&
        currentStatus == ConnectionStatus.ended) {
      _onBroadcastEnded();
    }

    // Issue #739: any reconnect / manual-stop status must cancel an
    // in-progress grace so the queue is dropped immediately and the
    // engine matches the user's intent.
    if (currentStatus != ConnectionStatus.ended && _isInSpeechGrace) {
      _cancelSpeechGrace(reason: 'status=${currentStatus.code}');
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
    // Unknown なエラーコード（null）は一時的事象の可能性を排除できないため
    // retryable 扱いで誘導文を表示する（既存挙動の踏襲）。
    final String guidance = (errorCode?.isRetryable ?? true)
        ? AppStrings.connection.retryGuidance
        : AppStrings.connection.nonRetryableNotice;

    if (widget.debugMode) {
      final String detail = widget.connectionSupervisor.lastErrorDetail ?? '';
      final String compactDetail = detail.isEmpty
          ? '-'
          : _compactSingleLine(detail);
      final String code = errorCode?.code ?? 'UNKNOWN_ERROR';
      return '$base [code: $code] 原因: $compactDetail $guidance';
    }

    return '$base $guidance';
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

  /// Returns whether the per-type visibility toggle allows the message to
  /// be processed.  Covers the three types (operator / system / emotion)
  /// whose toggles are shared between display filtering
  /// ([_shouldDisplayMessage]) and NG-protection notification
  /// ([_processNgProtectionNotifications]).
  ///
  /// Gift / nicoad are intentionally excluded and always return `true`:
  /// they have different policies in [_shouldDisplayMessage] (own toggle)
  /// vs [_processNgProtectionNotifications] (always skip), so each caller
  /// handles them independently.
  bool _isTypeVisible(AppMessageType type) {
    switch (type) {
      case AppMessageType.operator:
        return widget.messageTypeVisibility.showOperatorComment;
      case AppMessageType.system:
        return widget.messageTypeVisibility.showSystemMessage;
      case AppMessageType.emotion:
        return widget.messageTypeVisibility.showEmotion;
      case AppMessageType.chat:
      case AppMessageType.notification:
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return true;
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
  ///     `contentFilter.emphasizeGiftNicoadComment` at render time.
  ///   * NG user / NG word filtering for chat / operator / notification.
  ///
  /// NOTE: `AppMessageType.gift` / `.nicoad` are not produced by the current
  /// normalizer pipeline. This branch exists so that when a future protobuf
  /// or legacy path starts emitting those types, gift / nicoad events cannot
  /// be hidden by NG filters. See also `_shouldIncludeInStatsAndLogs`, which
  /// keeps them out of stats and saved comment logs.
  bool _shouldDisplayMessage(AppMessage message) {
    // Type-based visibility toggles.  Operator / system / emotion share
    // the same toggle semantics with [_processNgProtectionNotifications]
    // and are delegated to [_isTypeVisible] (single source of truth).
    // Gift / nicoad have their own toggles that only apply to display.
    switch (message.type) {
      case AppMessageType.chat:
      case AppMessageType.notification:
        break;
      case AppMessageType.gift:
        if (!widget.messageTypeVisibility.showGiftComment) {
          return false;
        }
        break;
      case AppMessageType.nicoad:
        if (!widget.messageTypeVisibility.showNicoadComment) {
          return false;
        }
        break;
      case AppMessageType.operator:
      case AppMessageType.system:
      case AppMessageType.emotion:
        if (!_isTypeVisible(message.type)) {
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
    if (userId != null && widget.contentFilter.ngUserIds.contains(userId)) {
      return false;
    }

    // Display-axis NG filter. Uses the [NgDisplayPreferences] threaded in
    // from `AppSettings` (#615) so the four preset subcategory toggles
    // (violence / sexual / discrimination / minors) can opt matched
    // comments back into the list without affecting the speech axis.
    if (_ngMatcher.shouldBlockDisplay(
      message.content,
      widget.contentFilter.ngDisplayPreferences,
    )) {
      return false;
    }

    return true;
  }

  // ---- AppBar overflow menu ----

  /// Build the AppBar overflow menu that groups low-frequency actions
  /// (search / save-log / settings). Kept as a dedicated method so it stays
  /// bound to this State — `_isSavingLog` / `setState` interactions remain
  /// local and do not leak into the parent [build].
  ///
  /// Uses `IconButton` + `showMenu()` instead of `PopupMenuButton` so the
  /// trigger's ripple shape and padding match the adjacent `IconButton`
  /// actions in the AppBar (e.g. the sort toggle). The `Builder` exists
  /// solely to obtain the button's `BuildContext` for positioning the menu.
  Widget _buildOverflowMenuButton() {
    return Builder(
      builder: (BuildContext buttonContext) {
        return IconButton(
          key: const Key('appbar-overflow-menu'),
          icon: const Icon(Icons.more_vert),
          tooltip: 'メニュー',
          onPressed: () => _showOverflowMenu(buttonContext),
        );
      },
    );
  }

  Future<void> _showOverflowMenu(BuildContext buttonContext) async {
    // Anchor the menu to the button's on-screen bounds, expressed relative to
    // the Navigator overlay (the coordinate space `showMenu` expects).
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final bool hasLogWriter = widget.logConfig.commentLogWriter != null;
    final bool hasSettings = widget.callbacks.onOpenSettings != null;
    // The "配信を終了" entry is gated on both broadcaster mode AND a
    // wired repository so non-broadcasters never see destructive copy and
    // hosts that intentionally omit the repository (e.g. tests, debug
    // builds) cannot trigger a no-op API call from the menu.
    final bool canEndBroadcast =
        _isBroadcaster && widget.broadcastControlRepository != null;
    final bool showDividerAfterEndBroadcast = canEndBroadcast;
    final bool showDividerBeforeSettings = hasSettings;
    final Color endBroadcastColor = Theme.of(context).colorScheme.error;

    final _AppBarMenuAction? action = await showMenu<_AppBarMenuAction>(
      context: context,
      position: position,
      items: <PopupMenuEntry<_AppBarMenuAction>>[
        if (canEndBroadcast)
          PopupMenuItem<_AppBarMenuAction>(
            key: const Key('end-broadcast-button'),
            value: _AppBarMenuAction.endBroadcast,
            enabled: !_isEndingBroadcast,
            child: _OverflowMenuRow(
              icon: Icons.stop_circle_outlined,
              label: '配信を終了',
              enabled: !_isEndingBroadcast,
              labelColor: endBroadcastColor,
            ),
          ),
        if (showDividerAfterEndBroadcast) const PopupMenuDivider(),
        const PopupMenuItem<_AppBarMenuAction>(
          key: Key('comment-search-button'),
          value: _AppBarMenuAction.search,
          child: _OverflowMenuRow(icon: Icons.search, label: 'コメントを検索'),
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
          const PopupMenuItem<_AppBarMenuAction>(
            key: Key('settings-button'),
            value: _AppBarMenuAction.settings,
            child: _OverflowMenuRow(icon: Icons.settings, label: '設定'),
          ),
      ],
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _AppBarMenuAction.endBroadcast:
        // `_isEndingBroadcast` may have flipped to true between menu open
        // and selection (e.g. user re-opened during an in-flight call),
        // so re-check here on top of the `enabled:` guard on the menu item.
        if (!_isEndingBroadcast) {
          unawaited(_endBroadcastFromMenu());
        }
      case _AppBarMenuAction.search:
        _openSearch();
      case _AppBarMenuAction.saveLog:
        // `_isSavingLog` may have flipped to true between menu open and
        // selection (e.g. a prior save completed then another started),
        // so re-check here on top of the `enabled:` guard on the menu item.
        if (!_isSavingLog) {
          unawaited(_saveLogManual());
        }
      case _AppBarMenuAction.settings:
        final Future<void> Function()? onOpen = widget.callbacks.onOpenSettings;
        if (onOpen != null) {
          unawaited(onOpen());
        }
    }
  }

  /// Confirms with the user, then calls
  /// [BroadcastControlRepository.endBroadcast] for the currently viewed
  /// program. Returns early on cancellation, missing repository, or empty
  /// session — surfacing a session-required SnackBar in the last case so
  /// the user understands why nothing happened.
  ///
  /// Feedback contract on completion:
  /// - **success / `CONFLICT (already-ended)`**: this method shows no
  ///   SnackBar. The server-side end closes the streaming connection and
  ///   the existing `_showStatsPanel` flow surfaces the standard
  ///   "放送が終了しました" SnackBar + auto-expanded stats panel. Showing
  ///   our own SnackBar here would race with that one.
  /// - **other failure**: SnackBar with the localized
  ///   `broadcastControlErrorMessage('終了', result)` string. We do not
  ///   `hideCurrentSnackBar()` because higher-priority notifications
  ///   (NG protection, send errors) should not be silently dismissed.
  Future<void> _endBroadcastFromMenu() async {
    // Re-entrancy guard: the menu auto-closes on tap, but the user can
    // re-open it and tap again before either the confirmation dialog or
    // the API call resolves. Without this the second invocation would
    // stack a duplicate dialog. The flag is set BEFORE the dialog (not
    // only around the API call) so the menu item also renders disabled
    // when re-opened during the confirm step.
    if (_isEndingBroadcast) {
      return;
    }
    final BroadcastControlRepository? repo = widget.broadcastControlRepository;
    if (repo == null) {
      return;
    }
    if (_commentPostUserSession.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('end-broadcast-session-required-snackbar'),
          content: Text('ログインが必要です'),
        ),
      );
      return;
    }

    setState(() {
      _isEndingBroadcast = true;
    });
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            key: const Key('end-broadcast-confirm-dialog'),
            title: const Text('配信を終了しますか？'),
            content: const Text('この操作は取り消せません。視聴者の接続も切断されます。'),
            actions: <Widget>[
              TextButton(
                key: const Key('end-broadcast-cancel-button'),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('キャンセル'),
              ),
              TextButton(
                key: const Key('end-broadcast-confirm-button'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                child: const Text('配信を終了'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) {
        return;
      }
      final BroadcastControlResult result = await repo.endBroadcast(
        programId: widget.programInfo.lv,
        userSession: _commentPostUserSession,
      );
      if (result.success || result.isAlreadyEnded) {
        // Flip the broadcaster-cache so any subsequent broadcaster check
        // does not return the stale "broadcaster" outcome cached during
        // the now-ended program (#752).
        widget.commentPostController?.clearBroadcasterCache();
      }
      if (!mounted) {
        return;
      }
      if (result.success || result.isAlreadyEnded) {
        // Defer to the existing connection-close → _showStatsPanel flow;
        // do not surface a competing SnackBar here.
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('end-broadcast-error-snackbar'),
          content: Text(broadcastControlErrorMessage('終了', result)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEndingBroadcast = false;
        });
      }
    }
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
    // Release normalized-content cache memory when search is dismissed.
    // The cache is only useful while search is active; keeping it alive
    // between search sessions wastes memory for no benefit.
    _normalizedContentCache.clear();
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
    //
    // Note: we intentionally do NOT clear [_normalizedContentCache] here.
    // The user is still in the search UI (only the query string was
    // reset), so keeping the per-message normalized content around means
    // typing a new query reuses the already-paid normalization cost.
    // The cache is cleared on [_closeSearch] (full search dismissal)
    // and on [dispose] (state teardown).
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
        // Issue #472: normalize query with NFKC-style fold so that
        // "ｱｲｳ" / "アイウ" / "あいう" and "ＡＢＣ" / "abc" all match
        // consistently. [normalizeForSearch] already lowercases ASCII.
        _normalizedSearchQuery = normalizeForSearch(_searchQuery.trim());
      });
    });
  }

  /// Returns true when [message] matches the active search query.
  ///
  /// Matching is case-insensitive and applied to the comment body
  /// (`content`) only. Query and body are both folded via
  /// [normalizeForSearch] (NFKC-style full/half-width + hira↔kata) so
  /// that small script / width differences do not break matches.
  /// When the query is empty, all messages match.
  ///
  /// Uses the pre-normalized [_normalizedSearchQuery] on the query side
  /// and a bounded memoization cache (`_normalizedContentCache`) on the
  /// message side to avoid recomputing the fold on every list rebuild.
  bool _matchesSearchQuery(AppMessage message) {
    if (_normalizedSearchQuery.isEmpty) {
      return true;
    }
    final String cached =
        _normalizedContentCache[message.id] ??
        _rememberNormalizedContent(message);
    return cached.contains(_normalizedSearchQuery);
  }

  /// Normalizes [message.content] for search and stores it in
  /// [_normalizedContentCache]. The cache is cleared wholesale when it
  /// grows past [_kNormalizedContentCacheCeiling]; this is simpler than
  /// a true LRU and acceptable because a full repopulation is at worst
  /// the same cost as the non-cached baseline.
  String _rememberNormalizedContent(AppMessage message) {
    if (_normalizedContentCache.length >= _kNormalizedContentCacheCeiling) {
      _normalizedContentCache.clear();
    }
    final String normalized = normalizeForSearch(message.content);
    _normalizedContentCache[message.id] = normalized;
    return normalized;
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
      final Object? decoded = jsonDecode(jsonText);
      final List<NgPresetCategory> categories = NgPresetCategory.parseDocument(
        decoded,
      );
      final List<String> words = NgPresetCategory.flattenWords(categories);
      if (!mounted || widget.contentFilter.presetNgWords.isNotEmpty) {
        return;
      }
      _effectivePresetNgWords = words;
      _effectivePresetCategories = categories;
      _rebuildNgMatcher();
      setState(() {});
    } catch (_) {
      // Keep empty preset list when asset is unavailable (e.g. tests without bundle).
    }
  }

  /// Rebuilds [_ngMatcher] from the current preset / user NG-word
  /// configuration. Called whenever any of those inputs change.
  void _rebuildNgMatcher() {
    // Prefer the structured category list (loaded from the asset) when it
    // is available, so the matcher can expose per-subcategory policies.
    // Fall back to the flat preset list — for pre-#613 callers that
    // injected `presetNgWords` directly — which is matched as
    // `blockSpeechOnly` with no subcategory. With the default
    // `NgDisplayPreferences` (all `false`) both paths hide and silence the
    // same comments, so behavior is unchanged.
    final Iterable<NgPresetCategory> categories =
        _effectivePresetCategories.isNotEmpty
        ? _effectivePresetCategories
        : _effectivePresetNgWords.map(
            (String word) => NgPresetCategory(
              id: '_flat',
              description: '',
              policy: NgPolicy.blockSpeechOnly,
              displaySubcategory: null,
              words: <String>[word],
            ),
          );
    _ngMatcher = NgMatcher(
      presetCategories: categories,
      userNgWords: widget.contentFilter.ngWords,
      normalizer: normalizeNgWordText,
    );
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

  /// Records the time at which the broadcast entered an ended / stopped
  /// state, and clears it when the user reconnects (so the status-bar
  /// timer resumes ticking for the new session).
  ///
  /// Clearing is wrapped in [setState] so the panel widget is removed in
  /// the same frame rather than relying on a sibling listener to rebuild.
  void _updateEndedAtForStatus(ConnectionStatus status) {
    final bool isEnded =
        status == ConnectionStatus.ended || status == ConnectionStatus.stopped;
    if (isEnded) {
      _endedAt ??= DateTime.now();
      return;
    }
    if (_endedAt == null && _pendingStats == null) {
      return;
    }
    setState(() {
      _endedAt = null;
      _pendingStats = null;
      _pendingStatsMessages = const <AppMessage>[];
      _statsPanelExpanded = false;
    });
  }

  void _showStatsPanel() {
    final List<AppMessage> messagesForStatsAndLogs = _messagesForStatsAndLogs();
    final bool hasMessages = messagesForStatsAndLogs.isNotEmpty;
    if (!hasMessages) {
      return;
    }

    final CommentLogStats stats = CommentLogStats.fromMessages(
      messagesForStatsAndLogs,
      ngUserIds: widget.contentFilter.ngUserIds,
    );

    setState(() {
      _pendingStats = stats;
      _pendingStatsMessages = messagesForStatsAndLogs;
      _statsPanelExpanded = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // NOTE: we intentionally do not call `clearSnackBars()` here so
      // that higher-priority notifications (NG protection, send errors)
      // stay visible even when the broadcast ends at the same moment.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('broadcast-ended-stats-snackbar'),
          content: const Text('放送が終了しました'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: '統計を見る', onPressed: _reopenStatsPanel),
        ),
      );
    });
  }

  /// Re-opens or expands the stats panel. Safe to call when stats are
  /// no longer available (for example after a reconnect cleared them) —
  /// it becomes a no-op.
  void _reopenStatsPanel() {
    if (!mounted || _pendingStats == null) {
      return;
    }
    setState(() {
      _statsPanelExpanded = true;
    });
  }

  void _minimizeStatsPanel() {
    if (!mounted) {
      return;
    }
    setState(() {
      _statsPanelExpanded = false;
    });
  }

  void _toggleStatsPanelExpanded() {
    if (!mounted) {
      return;
    }
    setState(() {
      _statsPanelExpanded = !_statsPanelExpanded;
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
    final List<AppMessage> messagesForLog = _messagesForLog();
    final bool hasMessages = messagesForLog.isNotEmpty;
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
        messages: messagesForLog,
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

    final List<AppMessage> messagesForLog = _messagesForLog();

    final Directory? customDir =
        widget.logConfig.autoSaveCommentLogPath.isNotEmpty
        ? Directory(widget.logConfig.autoSaveCommentLogPath)
        : null;

    String? savedPath;
    try {
      savedPath = await writer.save(
        lv: widget.programInfo.lv,
        messages: messagesForLog,
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
    } else if (messagesForLog.isNotEmpty) {
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

  /// Returns the messages to write to the auto-saved comment log file.
  ///
  /// Diverges from [_messagesForStatsAndLogs] (Issue #614):
  ///   * preset-NG-matched comments are **kept** with their content
  ///     prefixed by a `[filtered:<displaySubcategory>]` tag, instead of
  ///     being silently dropped from the log.
  ///   * user-defined NG word matches and NG users are still excluded
  ///     because those are user-driven blocks (not preset display
  ///     categories) and the tagging spec only covers the four preset
  ///     display subcategories.
  ///   * gift / nicoad and the system "broadcast ended" affordance row
  ///     are still excluded — the writer contract for the former and the
  ///     UI-only nature of the latter both predate this change.
  ///
  /// The stats path keeps using [_messagesForStatsAndLogs] so that this
  /// log-only behavior change does not bleed into the in-app statistics
  /// counts.
  @override
  List<AppMessage> messagesForLogForTesting() => _messagesForLog();

  @override
  void setBroadcasterForTesting({
    required bool isBroadcaster,
    String userSession = 'test-user-session',
  }) {
    if (_isBroadcaster == isBroadcaster &&
        _commentPostUserSession == userSession) {
      return;
    }
    setState(() {
      _isBroadcaster = isBroadcaster;
      _commentPostUserSession = userSession;
    });
  }

  List<AppMessage> _messagesForLog() {
    final List<AppMessage> out = <AppMessage>[];
    for (final AppMessage message in widget.messages) {
      // Step 1: system broadcast-ended rows are UI-only.
      if (_isSystemBroadcastEndedMessage(message)) {
        continue;
      }
      // Step 2: gift / nicoad — same writer contract as before.
      if (message.type == AppMessageType.gift ||
          message.type == AppMessageType.nicoad) {
        continue;
      }
      // Step 3: NG user — user-driven block, kept out of the log.
      final String? userId = message.userId;
      if (userId != null && widget.contentFilter.ngUserIds.contains(userId)) {
        continue;
      }
      // Step 4: NG word. Preset categories with a displaySubcategory get
      // tagged so the log preserves "what would have shown if the user
      // toggled the category on". User-defined NG words have no category
      // and remain excluded for parity with NG-user behavior.
      //
      // Uses the unified NgMatcher (#613) which exposes matchedSubcategory
      // directly. User-defined NG words match with matchedSubcategory == null,
      // so the tag-or-drop branch below correctly excludes them from the log.
      //
      // Note: v1 preset asset (#612) guarantees every preset category has a
      // non-null displaySubcategory. If a future preset is added with
      // subcategory=null, NgMatcher.match() may return that entry first and
      // matchedSubcategory becomes null, falling through to the user-NG
      // exclude branch (drop, no tag). To preserve the "save with tag" intent
      // for such future presets, the v3 schema constraint must be retained
      // (or this method extended to skip null-subcategory matches).
      final NgDisplaySubcategory? presetSub = _ngMatcher
          .match(message.content)
          ?.matchedSubcategory;
      if (presetSub != null) {
        out.add(
          AppMessage(
            id: message.id,
            timestamp: message.timestamp,
            userId: message.userId,
            userName: message.userName,
            content: CommentLogTag.applyTag(
              content: message.content,
              tag: CommentLogTag.filtered(presetSub),
            ),
            type: message.type,
            raw: message.raw,
          ),
        );
        continue;
      }
      if (_containsNgWord(message.content)) {
        // Matched a user-defined NG word (no preset category match).
        continue;
      }
      out.add(message);
    }
    return List<AppMessage>.unmodifiable(out);
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
    if (userId != null && widget.contentFilter.ngUserIds.contains(userId)) {
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
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final bool enabled;

  /// Optional override for both the icon and the label text color. Used by
  /// the destructive "配信を終了" entry to render in
  /// `theme.colorScheme.error` so the row reads as destructive at a glance.
  /// When `null` the row inherits the default `PopupMenuItem` foreground.
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final Color? effectiveColor = enabled ? labelColor : null;
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
                Icon(icon, color: effectiveColor),
                const SizedBox(width: 12),
                Text(label, style: TextStyle(color: effectiveColor)),
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
    this.broadcasterUserId,
    this.beginAt,
    this.endedAt,
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
  final String? broadcasterUserId;
  final DateTime? beginAt;

  /// Freezes the elapsed display at this moment. Non-null once the broadcast
  /// has ended or been stopped; null while the broadcast is still active.
  final DateTime? endedAt;
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

  bool get _shouldTickElapsed =>
      widget.beginAt != null && widget.endedAt == null;

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

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
    if (_shouldTickElapsed) {
      _startElapsedTimer();
    }
  }

  @override
  void didUpdateWidget(covariant _StatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool beginChanged = oldWidget.beginAt != widget.beginAt;
    final bool endedChanged = oldWidget.endedAt != widget.endedAt;
    if (beginChanged || endedChanged) {
      _elapsedTimer?.cancel();
      _elapsedTimer = null;
      if (_shouldTickElapsed) {
        _startElapsedTimer();
      }
    }
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  String? _elapsedLabel() =>
      formatElapsed(widget.beginAt, endAt: widget.endedAt);

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
                  if (widget.statisticsEnabled) ...<Widget>[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: <Widget>[
                        if (widget.statisticsViewerCommentEnabled) ...<Widget>[
                          // リスナー (viewer count) is sourced from
                          // NDGR `NicoliveMessage.statistics.viewers`,
                          // which the proto decoder does not yet
                          // extract (tracked in Issue #724). Hide the
                          // row entirely until that field lands so that
                          // we never surface a "-" placeholder that the
                          // user mistakes for a real "0 listeners".
                          if (widget.viewerCount != null)
                            Text(
                              'リスナー: ${widget.viewerCount}',
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
                    // 放送者ID / 最終受信 / 再接続 are debug-only
                    // metadata; collapse them onto a single Wrap row so
                    // the comment list keeps as much vertical space as
                    // possible (UX request, screenshot dated
                    // 2026-04-25).
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: <Widget>[
                        if (widget.broadcasterUserId != null)
                          Text(
                            '放送者ID: ${widget.broadcasterUserId}',
                            key: const Key('status-broadcaster-user-id'),
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.themeColors.subtleTextColor,
                            ),
                          ),
                        Text(
                          '最終受信: ${_formatHmsOrDash(widget.supervisor.lastReceivedAt)}',
                          key: const Key('status-last-received'),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.themeColors.subtleTextColor,
                          ),
                        ),
                        Text(
                          '再接続: ${widget.supervisor.reconnectCount}回',
                          key: const Key('status-reconnect-count'),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.themeColors.subtleTextColor,
                          ),
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
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.textScaler = TextScaler.noScaling,
    this.ngMatcher,
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
  final int commentTwoLineMetaFontPercent;
  final TextScaler textScaler;
  final NgMatcher? ngMatcher;

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
              commentTwoLineMetaFontPercent: commentTwoLineMetaFontPercent,
              userColor:
                  message.userId != null &&
                      userColorMap.containsKey(message.userId!)
                  ? colorFromARGB32(userColorMap[message.userId!]!)
                  : null,
              onUnpin: () => onUnpin(message.id),
              beginAt: beginAt,
              textScaler: textScaler,
              ngMatcher: ngMatcher,
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
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.userColor,
    required this.onUnpin,
    this.beginAt,
    this.textScaler = TextScaler.noScaling,
    this.ngMatcher,
  });

  final AppMessage message;
  final AppThemeColors themeColors;
  final String? resolvedUserName;
  final bool showUserName;
  final double fontSize;
  final bool commentTwoLineEnabled;
  final int commentTwoLineMetaFontPercent;
  final Color? userColor;
  final VoidCallback onUnpin;
  final DateTime? beginAt;

  /// Forwarded text scaler so the badge icon scales with the user's
  /// accessibility font settings, matching the row rendered by
  /// [_CommentRow.textScaler].
  final TextScaler textScaler;

  /// Optional matcher. See [_CommentRow.ngMatcher]. Pinned rows use the
  /// pinned-specific semantics label so screen-reader users can tell a
  /// read-skipped pinned comment apart from a read-skipped inline comment.
  final NgMatcher? ngMatcher;

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

    final NgDisplaySubcategory? matchedSubcategory = ngMatcher
        ?.match(message.content)
        ?.matchedSubcategory;

    Widget body;
    if (useTwoLine) {
      body = _buildTwoLinePinned(context, matchedSubcategory);
    } else {
      body = _buildSingleLinePinned(
        context,
        effectiveUserColor,
        matchedSubcategory,
      );
    }

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: body),
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

    if (matchedSubcategory != null) {
      row = MergeSemantics(
        child: Semantics(
          label:
              '読み上げ対象外のコメント（ピン留め）。'
              '${displaySubcategoryLabel(matchedSubcategory)}を含みます',
          child: row,
        ),
      );
    }
    return row;
  }

  Widget _buildSingleLinePinned(
    BuildContext context,
    Color? effectiveUserColor,
    NgDisplaySubcategory? matchedSubcategory,
  ) {
    final TextStyle bodyStyle = TextStyle(
      fontSize: fontSize,
      color: effectiveUserColor,
    );
    if (matchedSubcategory == null) {
      final String lineText = _commentLineText(
        message: message,
        showUserName: showUserName,
        resolvedUserName: resolvedUserName,
        beginAt: beginAt,
      );
      return Text(lineText, style: bodyStyle);
    }
    // Only the body content is dimmed; timestamp + display name stay at
    // full contrast so the row still reads as a legitimate pinned message.
    // Reuse [_commentLineText] with an empty body so the meta formatting
    // stays in lock-step with the unmatched path — any future change to
    // [_commentLineText] (operator handling, anonymous, etc.) propagates
    // here automatically instead of drifting.
    final String metaPrefix = _commentLineText(
      message: message,
      showUserName: showUserName,
      resolvedUserName: resolvedUserName,
      contentOverride: '',
      beginAt: beginAt,
    );
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          _buildReadSkippedBadgeSpan(
            fontSize: fontSize,
            textScaler: textScaler,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const TextSpan(text: ' '),
          TextSpan(text: metaPrefix, style: bodyStyle),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Opacity(
              opacity: _readSkippedBodyOpacity,
              child: Text(message.content, style: bodyStyle),
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
  Widget _buildTwoLinePinned(
    BuildContext context,
    NgDisplaySubcategory? matchedSubcategory,
  ) {
    final String timestamp = _formatHms(message.timestamp, beginAt: beginAt);
    final double metaFontSize = _resolveTwoLineMetaFontSize(
      fontSize,
      commentTwoLineMetaFontPercent,
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

    final List<InlineSpan> metaSpans = <InlineSpan>[];
    // Badge uses the body [fontSize] (not the smaller [metaFontSize]) so
    // the read-skipped affordance stays equally readable in 2-line pinned
    // layout; see the matching rationale in
    // [_CommentRowState._buildTwoLineComment].
    if (matchedSubcategory != null) {
      metaSpans.add(
        _buildReadSkippedBadgeSpan(
          fontSize: fontSize,
          textScaler: textScaler,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      metaSpans.add(const TextSpan(text: ' '));
    }
    metaSpans.addAll(
      _buildMetaSpans(
        timestamp: timestamp,
        showUserName: true,
        displayName: displayName,
        timestampFontSize: metaFontSize,
        idFontSize: metaFontSize,
        timestampColor: metaColor,
        idColor: metaColor,
        effectiveUserColor: effectiveUserColor,
        hidden: false,
      ),
    );

    Widget bodyText = Text(
      message.content,
      style: TextStyle(fontSize: fontSize, color: effectiveUserColor),
    );
    if (matchedSubcategory != null) {
      bodyText = Opacity(opacity: _readSkippedBodyOpacity, child: bodyText);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(TextSpan(children: metaSpans)),
        const SizedBox(height: 2),
        bodyText,
      ],
    );
  }
}

/// Sentinel wrapper for the cached "matched subcategory" verdict.
///
/// A plain `NgDisplaySubcategory?` field cannot distinguish "not yet
/// computed" from "computed and known to be null (no match)": both are
/// represented as null. Wrapping the verdict in a small holder lets the
/// state class store `null` for "uncomputed" and a `_SubcategoryCache`
/// instance (with `value == null`) for "computed and no match".
class _SubcategoryCache {
  const _SubcategoryCache(this.value);

  final NgDisplaySubcategory? value;
}

/// Opacity alpha applied to the body portion of a read-skipped comment row.
///
/// 0.7 matches the Issue #611 visual baseline. Kept as a named constant so
/// tests and the pinned-row variant can reference the same value without
/// risk of drifting copies.
const double _readSkippedBodyOpacity = 0.7;

/// Semantics label used by [Icon] badges inside the read-skipped row. Left
/// intentionally short because the parent [Semantics] node already
/// describes the full "読み上げ対象外" state; TalkBack/VoiceOver users should
/// not hear the state twice per row.
const String _readSkippedBadgeSemanticLabel = '読み上げ対象外';

/// Builds the "read-skipped" badge icon as an inline span. Sized to mirror
/// [_buildLeadingTypeIconSpan] (matches the gift/nicoad type icon) so the
/// two icons line up visually when they coexist.
///
/// The badge's own [Semantics] is excluded because the parent row already
/// carries a single [Semantics] node that names the state in full.
WidgetSpan _buildReadSkippedBadgeSpan({
  required double fontSize,
  required TextScaler textScaler,
  required Color color,
}) {
  final double baseIconSize = (fontSize * 0.95).clamp(10.0, 20.0);
  final double iconSize = textScaler.scale(baseIconSize);
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: ExcludeSemantics(
      child: Icon(
        Icons.volume_off,
        size: iconSize,
        color: color,
        // Harmless fallback for assistive tooling that bypasses the
        // ExcludeSemantics boundary; the parent Semantics label still
        // carries the authoritative state.
        semanticLabel: _readSkippedBadgeSemanticLabel,
      ),
    ),
  );
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
    this.commentTwoLineMetaFontPercent = commentTwoLineMetaFontPercentDefault,
    this.zebraStripingEnabled = false,
    this.emphasizeGiftNicoadComment = true,
    this.commentIndex = 0,
    this.userColor,
    this.onLongPress,
    this.onOpenUrl,
    this.beginAt,
    this.ngMatcher,
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
  final int commentTwoLineMetaFontPercent;
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

  /// Optional matcher used to detect that this comment is rendered only
  /// because the user opted into a display subcategory (preset match with
  /// `matchedSubcategory != null`). When provided, a "read-skipped" badge
  /// is shown and the body is dimmed so the broadcaster can tell at a
  /// glance that TTS is skipping the row. `null` matches (user-defined NG
  /// or no match) render the row unchanged.
  final NgMatcher? ngMatcher;

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

  /// Cached preset-subcategory match for [widget.message.content].
  ///
  /// `null` (the default) means "not yet computed"; once resolved the cache
  /// holds a [_SubcategoryCache] describing either a real match or the
  /// "no match" verdict. Keyed implicitly by `(message.id, ngMatcher)` —
  /// invalidated in [didUpdateWidget] whenever either changes so a row
  /// recycled for a new message or after a settings-driven matcher rebuild
  /// re-evaluates cleanly.
  _SubcategoryCache? _cachedSubcategory;

  bool get _isStarHidden =>
      widget.starPrefixHidingEnabled &&
      widget.message.content.startsWith('☆') &&
      !_revealed;

  List<UrlMatch> _resolveUrlMatches() {
    return _cachedUrlMatches ??= findUrls(widget.message.content);
  }

  /// Resolves the preset subcategory associated with this row, or `null`
  /// when the row should render unchanged. Returns `null` for:
  ///   * rows with no matcher attached,
  ///   * rows whose content does not match any entry,
  ///   * rows that matched a user-defined NG word (matchedSubcategory is
  ///     null — per the v1 contract, user words always block both display
  ///     and speech so the badge would be redundant),
  ///   * star-prefix-hidden rows (they already render a placeholder body;
  ///     adding a badge would leak that the original matched something).
  NgDisplaySubcategory? _resolveMatchedSubcategory() {
    if (_isStarHidden) {
      return null;
    }
    final NgMatcher? matcher = widget.ngMatcher;
    if (matcher == null) {
      return null;
    }
    final _SubcategoryCache cache = _cachedSubcategory ??= _SubcategoryCache(
      matcher.match(widget.message.content)?.matchedSubcategory,
    );
    return cache.value;
  }

  @override
  void didUpdateWidget(covariant _CommentRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _revealed = false;
      _cachedUrlMatches = null;
      _cachedSubcategory = null;
    } else if (oldWidget.message.content != widget.message.content) {
      _cachedUrlMatches = null;
      _cachedSubcategory = null;
    } else if (!identical(oldWidget.ngMatcher, widget.ngMatcher)) {
      _cachedSubcategory = null;
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
    final NgDisplaySubcategory? matchedSubcategory =
        _resolveMatchedSubcategory();
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

    Widget row = Container(
      color: effectiveBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: _buildRichCommentLine(
        context,
        hidden,
        urlMatches,
        matchedSubcategory,
      ),
    );

    // Wrap in a single Semantics node so TalkBack/VoiceOver users hear the
    // "read-skipped" state once per row. The child icon badge is excluded
    // from semantics (see [_buildReadSkippedBadgeSpan]).
    if (matchedSubcategory != null) {
      row = MergeSemantics(
        child: Semantics(
          label:
              '読み上げ対象外のコメント。'
              '${displaySubcategoryLabel(matchedSubcategory)}を含みます',
          child: row,
        ),
      );
    }

    return GestureDetector(
      key: Key('comment-row-${widget.message.id}'),
      onLongPress: widget.onLongPress,
      onTap: onTap,
      child: row,
    );
  }

  Widget _buildRichCommentLine(
    BuildContext context,
    bool hidden,
    List<UrlMatch> urlMatches,
    NgDisplaySubcategory? matchedSubcategory,
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
          : _resolveTwoLineMetaFontSize(
              fontSize,
              widget.commentTwoLineMetaFontPercent,
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
        matchedSubcategory: matchedSubcategory,
      );
    }

    final List<InlineSpan> spans = <InlineSpan>[];
    // Read-skipped badge is inserted before any type icon so the "skipped"
    // state reads as a global row modifier rather than a per-type marker.
    // Icon color uses `onSurfaceVariant` (the theme's canonical subdued
    // foreground) so it remains legible on both the plain background and
    // the zebra stripe tint — unlike `outline`, which is intended for
    // decorative borders and can drop to ~40% luminance on dark themes.
    if (matchedSubcategory != null) {
      spans.add(
        _buildReadSkippedBadgeSpan(
          fontSize: fontSize,
          textScaler: widget.textScaler,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      spans.add(const TextSpan(text: ' '));
    }
    final InlineSpan? leadingIconSpan = _buildLeadingTypeIconSpan(
      context,
      fontSize,
    );
    if (leadingIconSpan != null) {
      spans.add(leadingIconSpan);
      spans.add(const TextSpan(text: ' '));
    }
    spans.addAll(
      _buildMetaSpans(
        timestamp: timestamp,
        showUserName: widget.showUserName,
        displayName: widget.showUserName ? _displayNameFor(message) : null,
        timestampFontSize: timestampFontSize,
        idFontSize: idFontSize,
        timestampColor: timestampColor,
        idColor: idColor,
        effectiveUserColor: effectiveUserColor,
        hidden: hidden,
        idFontWeight: FontWeight.w500,
      ),
    );

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : effectiveUserColor,
      fontStyle: hidden ? FontStyle.italic : null,
    );

    spans.add(const TextSpan(text: '  '));
    final List<InlineSpan> contentSpans = _buildContentSpans(
      context: context,
      content: content,
      urlMatches: urlMatches,
      baseStyle: contentStyle,
    );
    if (matchedSubcategory != null) {
      // Wrap the body in an inline Opacity so timestamp/username stay at
      // full contrast while the content dims. A WidgetSpan is used (rather
      // than splitting the row into a Row) so the row's vertical rhythm
      // and tap target remain identical to non-matched rows.
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Opacity(
            opacity: _readSkippedBodyOpacity,
            child: Text.rich(TextSpan(children: contentSpans)),
          ),
        ),
      );
    } else {
      spans.addAll(contentSpans);
    }

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
    NgDisplaySubcategory? matchedSubcategory,
  }) {
    final List<InlineSpan> metaSpans = <InlineSpan>[];
    // Mirror the 1-line ordering: badge first, then type icon, then meta.
    // Badge is sized by the body [fontSize] (not the smaller meta font) so
    // it stays as readable as in 1-line mode — the whole point of the
    // badge is at-a-glance scanning of silenced rows, which should not
    // degrade just because the streamer chose 2-line display.
    if (matchedSubcategory != null) {
      metaSpans.add(
        _buildReadSkippedBadgeSpan(
          fontSize: fontSize,
          textScaler: widget.textScaler,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
      metaSpans.add(const TextSpan(text: ' '));
    }
    final InlineSpan? leadingIconSpan = _buildLeadingTypeIconSpan(
      context,
      timestampFontSize,
    );
    if (leadingIconSpan != null) {
      metaSpans.add(leadingIconSpan);
      metaSpans.add(const TextSpan(text: ' '));
    }
    metaSpans.addAll(
      _buildMetaSpans(
        timestamp: timestamp,
        showUserName: widget.showUserName,
        displayName: widget.showUserName
            ? _displayNameFor(widget.message)
            : null,
        timestampFontSize: timestampFontSize,
        idFontSize: idFontSize,
        timestampColor: timestampColor,
        idColor: idColor,
        effectiveUserColor: effectiveUserColor,
        hidden: hidden,
        idFontWeight: FontWeight.w500,
      ),
    );

    final TextStyle contentStyle = TextStyle(
      fontSize: fontSize,
      color: hidden ? Colors.grey : effectiveUserColor,
      fontStyle: hidden ? FontStyle.italic : null,
    );

    Widget body = Text.rich(
      TextSpan(
        children: _buildContentSpans(
          context: context,
          content: content,
          urlMatches: urlMatches,
          baseStyle: contentStyle,
        ),
      ),
    );
    if (matchedSubcategory != null) {
      body = Opacity(opacity: _readSkippedBodyOpacity, child: body);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text.rich(TextSpan(children: metaSpans)),
        const SizedBox(height: 2),
        body,
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

/// View-model produced by [speechIconViewFor]. Concrete pixel-level
/// inputs to the AppBar speech-status icon, derived purely from the
/// engine state machine inputs — no `BuildContext`, no `setState`, no
/// theme lookups beyond the [AppThemeColors] passed in. Unit-testable
/// in isolation (Issue #717 / ARCH-2).
@immutable
class SpeechIconView {
  const SpeechIconView({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.isError,
  });

  final IconData icon;
  final Color color;
  final String tooltip;

  /// True when the icon represents an error state (either local
  /// `engineState == error` or `treatAsError` from the cross-screen
  /// notifier). Used by [_SpeechStatusIcon] to gate `canToggleMute`.
  final bool isError;
}

/// Pure state-decision function for the AppBar speech-status icon.
/// Extracted from `_SpeechStatusIcon._buildIcon` (Issue #717 / ARCH-2)
/// so the priority ladder
/// (ERROR → !initialized → !started → isMuted → ready) can be unit
/// tested without pumping a widget tree.
///
/// Behaviour parity with the previous inline if/else chain is preserved:
/// * ERROR is checked first so a failure dominates the visual signal,
///   even if the engine never reached `_speechStarted == true` (Issue
///   #682's "the user must be able to notice the failure").
/// * [treatAsError] is the cross-screen availability override (Issue
///   #694). When `true`, the icon renders ERROR even if the local
///   `engineState` is still `unknown`/`ready`.
/// * The tooltip distinguishes Android TTS errors (which point at
///   read-aloud settings) from generic errors (which do not). The
///   distinction is signalled by [isAndroidTtsEngine] — the caller
///   passes `androidTtsAvailability != null` since that notifier is
///   only injected for the Android TTS engine.
/// * [hasRetryAffordance] (Issue #713 / UX-2): when true, the error
///   tooltip is rewritten to advertise the inline retry path
///   ("タップで再試行"). Defaults to false to preserve the legacy
///   tooltip wording for callers that have not wired a retry callback.
SpeechIconView speechIconViewFor({
  required SpeechEngineState engineState,
  required bool isStarted,
  required bool isInitialized,
  required bool isMuted,
  required bool treatAsError,
  required AppThemeColors themeColors,
  required bool isAndroidTtsEngine,
  bool hasRetryAffordance = false,
}) {
  final bool isError = engineState == SpeechEngineState.error || treatAsError;
  if (isError) {
    // Issue #713 (UX-2): when the host wires a retry handler the
    // tooltip advertises the new tappable affordance. The Android-TTS
    // hint is preserved so users still know where to read the detailed
    // warning if the inline retry doesn't recover the engine.
    final String tooltip;
    if (hasRetryAffordance) {
      tooltip = isAndroidTtsEngine
          ? '読み上げ: エラー（タップで再試行 / 読み上げ設定で詳細）'
          : '読み上げ: エラー（タップで再試行）';
    } else {
      tooltip = isAndroidTtsEngine
          ? '読み上げ: エラー（読み上げ設定で詳細を確認してください）'
          : '読み上げ: エラー';
    }
    return SpeechIconView(
      icon: Icons.error_outline,
      color: themeColors.statusDisconnected,
      tooltip: tooltip,
      isError: true,
    );
  }
  if (!isInitialized) {
    return SpeechIconView(
      icon: Icons.hourglass_top,
      color: themeColors.subtleTextColor,
      tooltip: '読み上げ: 初期化中',
      isError: false,
    );
  }
  if (!isStarted) {
    return SpeechIconView(
      icon: Icons.pause_circle_outline,
      color: themeColors.subtleTextColor,
      tooltip: '読み上げ: 停止中',
      isError: false,
    );
  }
  if (isMuted) {
    return SpeechIconView(
      icon: Icons.volume_off,
      color: themeColors.statusConnected,
      tooltip: 'ミュート解除',
      isError: false,
    );
  }
  return SpeechIconView(
    icon: Icons.volume_up,
    color: themeColors.statusConnected,
    tooltip: 'ミュート',
    isError: false,
  );
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
    this.onRetry,
    this.androidTtsAvailability,
  });

  final SpeechEngineState engineState;
  final bool isStarted;
  final bool isInitialized;
  final bool isMuted;
  final AppThemeColors themeColors;
  final VoidCallback? onTap;

  /// Issue #713 (UX-2): callback fired when the user taps the icon
  /// while the engine is in ERROR. The host wires this to a re-init
  /// flow (`_initializedEngineType = null; _initializeAndStartSpeech()`)
  /// so the user can recover without leaving the screen. Multi-tap
  /// protection is provided by the host's existing `_speechInitializing`
  /// guard inside the init method.
  final VoidCallback? onRetry;

  /// Issue #694: Android-TTS-only cross-screen availability source. When
  /// non-null and the latest publish was [SpeechAvailability.unavailable],
  /// the icon renders ERROR even though `engineState` itself may still be
  /// READY (because nothing on this screen has tried to speak yet).
  /// VOICEVOX and the no-notifier case are unaffected.
  final SpeechAvailabilityNotifier? androidTtsAvailability;

  @override
  Widget build(BuildContext context) {
    final SpeechAvailabilityNotifier? notifier = androidTtsAvailability;
    if (notifier == null) {
      return _buildIcon(context, treatAsError: false);
    }
    return AnimatedBuilder(
      animation: notifier,
      builder: (BuildContext context, Widget? _) {
        return _buildIcon(context, treatAsError: notifier.isUnavailable);
      },
    );
  }

  Widget _buildIcon(BuildContext context, {required bool treatAsError}) {
    // Issue #713 (UX-2): the pure view function takes
    // `hasRetryAffordance` so the error tooltip advertises the new
    // retry path when the host wires [onRetry]. When false (no
    // host-side retry handler), the tooltip falls back to the
    // settings-side recovery instruction.
    final SpeechIconView view = speechIconViewFor(
      engineState: engineState,
      isStarted: isStarted,
      isInitialized: isInitialized,
      isMuted: isMuted,
      treatAsError: treatAsError,
      themeColors: themeColors,
      isAndroidTtsEngine: androidTtsAvailability != null,
      hasRetryAffordance: onRetry != null,
    );
    final IconData icon = view.icon;
    final Color color = view.color;
    final String tooltip = view.tooltip;
    final bool canToggleMute = isInitialized && isStarted && !view.isError;
    // Issue #713 (UX-2): in ERROR state the mute toggle is disabled by
    // design (canToggleMute is false), but the icon should still be
    // interactive when [onRetry] is wired so the user has a one-tap
    // recovery path from the AppBar.
    final bool canRetry = view.isError && onRetry != null;

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

    if (canRetry) {
      return Semantics(
        // Mirror the `tooltip` text exactly so screen-reader users and
        // sighted hover users hear / see the same wording (sage UX/UI
        // OPTIONAL #1).
        label: tooltip,
        button: true,
        enabled: true,
        child: IconButton(
          key: const Key('speech-status-icon-retry'),
          icon: Icon(icon, size: 24, color: color),
          tooltip: tooltip,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: () {
            HapticFeedback.lightImpact();
            onRetry!();
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
