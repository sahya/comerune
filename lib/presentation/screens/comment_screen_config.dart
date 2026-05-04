import 'package:flutter/foundation.dart';

import '../../application/settings/settings_store.dart';
import '../../application/speech/speech_availability_notifier.dart';
import '../../application/timeline/timeline_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/comment_log/recent_broadcast_stats.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/matchers/ng_matcher.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/ng_preset_category.dart';

/// Program-level metadata for the comment screen.
@immutable
class CommentProgramInfo {
  const CommentProgramInfo({
    required this.lv,
    this.programTitle,
    this.broadcasterName,
    this.broadcasterUserId,
    this.broadcasterIconUrl,
    this.beginAt,
    this.vposBaseAt,
    this.connectionMethod,
  });

  /// The live program ID (e.g. "lv348712105").
  final String lv;

  /// The broadcast title.
  final String? programTitle;

  /// The broadcaster's display name.
  final String? broadcasterName;

  /// The broadcaster's user ID.
  final String? broadcasterUserId;

  /// The broadcaster's icon URL.
  final String? broadcasterIconUrl;

  /// When the broadcast started.
  final DateTime? beginAt;

  /// Authoritative vpos base time from
  /// `data.programSchedule.vposBaseTime` (Issue #465). When non-null
  /// this takes precedence over [beginAt] for comment vpos calculation;
  /// when null the existing [beginAt] fallback keeps the previous
  /// behaviour. Extended / rehearsal broadcasts can have
  /// [vposBaseAt] drift from [beginAt] by several seconds, which
  /// otherwise shows up as this client's comments being mis-ordered
  /// against other viewers server-side.
  final DateTime? vposBaseAt;

  /// The connection method used to connect to the program.
  final ConnectionMethod? connectionMethod;
}

/// Statistics display configuration and live data.
@immutable
class CommentStatisticsConfig {
  const CommentStatisticsConfig({
    this.enabled = false,
    this.viewerCommentEnabled = true,
    this.activeUserEnabled = true,
    this.highlightPickupEnabled = false,
    this.viewerCount,
    this.totalCommentCount = 0,
    this.activeUserCount = 0,
  });

  /// Whether statistics display is enabled.
  final bool enabled;

  /// Whether viewer/comment count is shown.
  final bool viewerCommentEnabled;

  /// Whether active user count is shown.
  final bool activeUserEnabled;

  /// Whether highlight pickup is shown at broadcast end.
  final bool highlightPickupEnabled;

  /// Current viewer count (null when unavailable).
  final int? viewerCount;

  /// Total number of comments received.
  final int totalCommentCount;

  /// Number of active users in recent window.
  final int activeUserCount;
}

/// Groups callback parameters for [CommentScreen].
@immutable
class CommentCallbacks {
  const CommentCallbacks({
    required this.onStopAllConnections,
    required this.onReconnectSameLv,
    required this.onDifferentLvConnected,
    this.onOpenSettings,
    this.onToggleNgUser,
    this.onDictionaryRulesChanged,
    this.onSpeechMuteToggled,
    this.onUserColorChanged,
    this.onUserColorRemoved,
    this.onNicknameChanged,
    this.onNicknameRemoved,
    this.onSortOrderChanged,
    this.onRecentBroadcastStatsCaptured,
  });

  final Future<void> Function() onStopAllConnections;
  final Future<void> Function() onReconnectSameLv;
  final Future<void> Function(String previousLv, String nextLv)
  onDifferentLvConnected;
  final Future<void> Function()? onOpenSettings;

  /// Called to toggle NG status for a user.
  final void Function(String userId)? onToggleNgUser;

  /// Called when dictionary rules are updated by a teach/unteach command.
  final void Function(AppSettings updated)? onDictionaryRulesChanged;

  /// Called when the user taps the speech status icon to toggle mute.
  final VoidCallback? onSpeechMuteToggled;

  /// Called when the user sets a custom comment color for a user.
  final void Function(String userId, int colorValue)? onUserColorChanged;

  /// Called when the user removes a custom comment color.
  final void Function(String userId)? onUserColorRemoved;

  /// Called when a nickname is set or updated for a user.
  final void Function(String userId, String nickname)? onNicknameChanged;

  /// Called when a nickname is removed for a user.
  final void Function(String userId)? onNicknameRemoved;

  /// Called when the user toggles the comment scroll order via the
  /// AppBar sort button. The argument is the **new** sort order after the
  /// toggle. The composition root is responsible for persisting this via
  /// [SettingsStore.save]. Issue #774.
  final void Function(CommentSortOrder)? onSortOrderChanged;

  /// Issue #767: optional integration. Invoked once per finalised
  /// broadcast at the moment the comment screen builds its end-of-broadcast
  /// stats panel. The composition root is expected to capture the snapshot
  /// into a memory-only "previous broadcast" holder so the user can
  /// re-open it from the next broadcast's status detail view. The comment
  /// screen does not own the holding concern. When null this is a no-op
  /// so legacy embedders / minimal test harnesses do not need to wire it.
  final RecentBroadcastStatsCallback? onRecentBroadcastStatsCaptured;
}

/// Issue #767: callback signature for
/// [CommentCallbacks.onRecentBroadcastStatsCaptured]. The receiver is
/// expected to inspect [RecentBroadcastStats.isBroadcaster] and only
/// persist (in memory) when the local user owns the broadcast.
typedef RecentBroadcastStatsCallback =
    void Function(RecentBroadcastStats snapshot);

/// Content-based filtering and per-user rendering attributes for
/// [CommentScreen].
///
/// Responsible for hiding messages based on *who/what* sent them (blocked
/// users, banned words, star-prefixed bodies, slash-prefixed speech skip) and
/// for carrying per-user display attributes (color / nickname) plus the
/// "emphasize gift/nicoad" rendering toggle.
///
/// Sibling class: [MessageTypeVisibilityConfig] handles message *category* toggles
/// (運営 / system / emotion / gift / nicoad list visibility). Kept separate so
/// each responsibility can evolve independently. See issue #457.
@immutable
class ContentFilterConfig {
  const ContentFilterConfig({
    this.ngUserIds = const <String>{},
    this.ngWords = const <String>[],
    this.presetNgWords = const <String>[],
    this.presetCategories = const <NgPresetCategory>[],
    this.starPrefixHidingEnabled = false,
    this.slashPrefixSkipEnabled = true,
    this.emphasizeGiftNicoadComment = true,
    this.userColorMap = const <String, int>{},
    this.userNicknameMap = const <String, String>{},
    this.ngProtectionNotificationEnabled = false,
    this.ngDisplayPreferences = NgDisplayPreferences.defaults,
  });

  /// Set of user IDs marked as NG (blocked).
  final Set<String> ngUserIds;

  /// List of NG words for content-based filtering (case-insensitive).
  final List<String> ngWords;

  /// System preset NG words (non-user editable in UI).
  ///
  /// When empty, the widget attempts to load `preset_ng_words.json` from assets.
  final List<String> presetNgWords;

  /// Structured preset NG categories injection seam (Issue #628).
  ///
  /// When non-empty, the widget uses these categories directly and derives
  /// the flat preset NG word list via [NgPresetCategory.flattenWords]. This
  /// takes precedence over [presetNgWords] and skips the asset-load
  /// fallback. Empty (the default) preserves the pre-#628 behavior:
  /// callers that only inject [presetNgWords] continue to work as before,
  /// and callers that inject neither still fall back to the bundled
  /// `preset_ng_words.json` asset.
  final List<NgPresetCategory> presetCategories;

  /// When true, comments starting with `☆` have their body hidden
  /// and can be revealed by tapping.
  final bool starPrefixHidingEnabled;

  /// When true, comments starting with `/` are skipped by the TTS engine
  /// (they remain visible in the comment list).
  final bool slashPrefixSkipEnabled;

  /// When true, gift / ニコニ広告 (nicoad) comments are rendered with a
  /// subtle shaded background and a leading type icon. When false, they are
  /// displayed with the default chat styling.
  ///
  /// This only affects rendering; gift/nicoad list visibility is governed by
  /// [MessageTypeVisibilityConfig.showGiftComment] / [MessageTypeVisibilityConfig.showNicoadComment].
  final bool emphasizeGiftNicoadComment;

  /// Per-user comment color map. Keys are user IDs, values are ARGB32 ints.
  final Map<String, int> userColorMap;

  /// Per-user nickname (コテハン) map. Keys are user IDs, values are nicknames.
  final Map<String, String> userNicknameMap;

  /// When true, the comment screen announces via snackbar + AppBar badge
  /// every time a comment is hidden by NG word or NG user filtering.
  ///
  /// When false (default), filtering stays silent.
  final bool ngProtectionNotificationEnabled;

  /// Per-subcategory display allow-list wired to the preset NG matcher.
  ///
  /// Introduced in #615. Defaults to [NgDisplayPreferences.defaults]
  /// (all `false`), which preserves the pre-#615 behavior where every
  /// preset NG match silently hides the comment.
  final NgDisplayPreferences ngDisplayPreferences;
}

/// Message-type visibility toggles for [CommentScreen].
///
/// Controls whether entire message categories (運営 / system / emotion /
/// gift / nicoad) are shown in the comment list. See sibling class
/// [ContentFilterConfig] for content-based filtering. See issue #457.
@immutable
class MessageTypeVisibilityConfig {
  const MessageTypeVisibilityConfig({
    this.showOperatorComment = true,
    this.showSystemMessage = true,
    this.showEmotion = true,
    this.showGiftComment = true,
    this.showNicoadComment = true,
  });

  /// Whether operator (運営) comments are displayed. Defaults to true.
  final bool showOperatorComment;

  /// Whether system messages (e.g. ichiba) are displayed. Defaults to true.
  final bool showSystemMessage;

  /// Whether emotion notifications are displayed. Defaults to true.
  final bool showEmotion;

  /// Whether gift comments are displayed in the comment list. Defaults to true.
  ///
  /// When false, gift messages are suppressed from the comment list entirely.
  /// This does not affect the TTS read-aloud pipeline, which is governed
  /// separately by `CommentSpeechConfig.readGiftComment`.
  final bool showGiftComment;

  /// Whether ニコニ広告 (nicoad) comments are displayed in the comment list.
  /// Defaults to true.
  ///
  /// When false, nicoad messages are suppressed from the comment list entirely.
  /// This does not affect the TTS read-aloud pipeline, which is governed
  /// separately by `CommentSpeechConfig.readNicoadComment`.
  final bool showNicoadComment;
}

/// Groups comment-log parameters for [CommentScreen].
@immutable
class CommentLogConfig {
  const CommentLogConfig({
    this.commentLogWriter,
    this.autoSaveCommentLog = false,
    this.autoSaveCommentLogPath = '',
  });

  final CommentLogWriter? commentLogWriter;
  final bool autoSaveCommentLog;
  final String autoSaveCommentLogPath;
}

/// Groups speech (VoiceVox) parameters for [CommentScreen].
@immutable
class CommentSpeechConfig {
  const CommentSpeechConfig({
    this.speechPlatform,
    this.speechSettings = const SpeechSettings(enabled: false),
    this.readUserName = false,
    this.readGiftComment = false,
    this.readNicoadComment = false,
    this.settingsStore,
    this.isSpeechMuted = false,
    this.androidTtsAvailability,
    this.playRemainingAfterEnded = true,
    this.onSpeechGraceEnded,
    this.timelineStore,
  });

  /// The platform channel bridge for VoiceVox speech synthesis.
  /// Null when the speech plugin is not available.
  final CommentSpeechPlatform? speechPlatform;

  /// VoiceVox speech configuration. [SpeechSettings.enabled] reflects
  /// whether auto-read is active with the VoiceVox engine.
  final SpeechSettings speechSettings;

  /// When true, the user name is prepended to the comment text for TTS.
  final bool readUserName;

  /// When true, gift messages are read aloud by TTS. Defaults to false.
  ///
  /// Only the message body (`message.content`) is spoken — no additional
  /// formatting or user-name prefixing is applied. This is independent of
  /// [MessageTypeVisibilityConfig.showGiftComment], which controls list visibility.
  final bool readGiftComment;

  /// When true, ニコニ広告 (nicoad) messages are read aloud by TTS.
  /// Defaults to false.
  ///
  /// Only the message body (`message.content`) is spoken — no additional
  /// formatting or user-name prefixing is applied. This is independent of
  /// [MessageTypeVisibilityConfig.showNicoadComment], which controls list visibility.
  final bool readNicoadComment;

  /// Settings store for persisting teach command dictionary changes.
  final SettingsStore? settingsStore;

  /// Whether the speech output is currently muted.
  final bool isSpeechMuted;

  /// Cross-screen single source of truth for Android TTS availability
  /// (Issue #694). Optional — when null, the AppBar speech-status icon
  /// falls back to the previous behaviour where availability detection in
  /// other screens (e.g. TTS settings) does not propagate here.
  ///
  /// When provided AND `speechSettings.engineType == SpeechEngineType.androidTts`,
  /// the comment screen treats `SpeechAvailability.unavailable` as a
  /// `engineState == 'ERROR'` for icon-rendering purposes, so the user sees
  /// the failure state immediately on returning from settings without
  /// having to reconnect to the program.
  final SpeechAvailabilityNotifier? androidTtsAvailability;

  /// Issue #739: when true, [ConnectionStatus.ended] does not stop the
  /// speech queue immediately. Instead the comment screen waits up to 30
  /// seconds for the queue to drain, so the last few comments before a
  /// broadcast end are still read out. Defaults to `true` — the same
  /// default used by [AppSettings.playRemainingAfterEnded].
  ///
  /// Has no effect on `failed` / `stopped`, which always stop immediately.
  final bool playRemainingAfterEnded;

  /// Issue #739: optional callback fired when the comment screen's grace
  /// window ends (timeout, queue drained, or speech disabled mid-grace).
  /// Wired by the app composition root to
  /// [ForegroundServiceController.notifyQueueDrained] so the FGS notification
  /// can drop early when speech actually finishes or is cancelled, instead of
  /// waiting out the controller's own 30 s timer.
  ///
  /// Null in test harnesses that do not need to assert FGS coordination.
  final VoidCallback? onSpeechGraceEnded;

  /// Issue #758 / #762: optional reactive source for the speech submit
  /// pipeline.
  ///
  /// When provided, [CommentScreen] subscribes to this store via
  /// [ChangeNotifier.addListener] and submits new comments for speech the
  /// instant a mutation fires `notifyListeners()` — both in foreground
  /// (immediate, no waiting for the next widget rebuild) and in background
  /// (no longer waiting up to 2 s for the previous periodic poll).
  ///
  /// PR #721 made [TimelineStore.messages] return a cached snapshot that
  /// is re-published just before `notifyListeners()`, so the listener sees
  /// the new entry on the very first read inside the callback.
  ///
  /// Null in test harnesses that do not exercise the reactive submit path;
  /// in that case the screen falls back to the foreground-only submit
  /// triggered from [State.didUpdateWidget] when `widget.messages` changes.
  final TimelineStore? timelineStore;
}
