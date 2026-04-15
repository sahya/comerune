import 'package:flutter/foundation.dart';

import '../../application/settings/settings_store.dart';
import '../../comment_speech/comment_speech.dart';
import '../../data/comment_log/comment_log_writer.dart';
import '../../domain/connection/connection_method.dart';
import '../../domain/models/app_settings.dart';

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
}

/// Groups filter-related parameters for [CommentScreen].
///
/// This config intentionally carries two related but distinct responsibilities:
///
/// - **Content/user filters** — [ngUserIds], [ngWords], [presetNgWords],
///   [starPrefixHidingEnabled]. These hide messages based on who/what sent
///   them (blocked users, banned words, star-prefixed bodies).
/// - **Message-type display toggles** — [showOperatorComment],
///   [showSystemMessage], [showEmotion]. These hide entire message categories
///   the viewer does not want to see (e.g. 運営コメント OFF).
///
/// Both are funneled through `_shouldDisplayMessage` in `CommentScreen` and
/// therefore share this parameter bag. They are grouped together because the
/// UI treats them uniformly as "things that suppress a message from the list";
/// keep that in mind if adding new fields — if a new flag changes *rendering*
/// rather than *visibility*, it does not belong here.
///
/// TODO(follow-up): consider splitting this class into two dedicated configs
/// (content-filter vs. message-type-display-toggles) so each responsibility
/// can evolve independently. follow-up issue: pending
@immutable
class CommentFilterConfig {
  const CommentFilterConfig({
    this.ngUserIds = const <String>{},
    this.ngWords = const <String>[],
    this.presetNgWords = const <String>[],
    this.starPrefixHidingEnabled = false,
    this.slashPrefixSkipEnabled = true,
    this.emphasizeGiftNicoadComment = true,
    this.userColorMap = const <String, int>{},
    this.userNicknameMap = const <String, String>{},
    this.showOperatorComment = true,
    this.showSystemMessage = true,
    this.showEmotion = true,
    this.showGiftComment = true,
    this.showNicoadComment = true,
    this.ngProtectionNotificationEnabled = false,
  });

  /// Set of user IDs marked as NG (blocked).
  final Set<String> ngUserIds;

  /// List of NG words for content-based filtering (case-insensitive).
  final List<String> ngWords;

  /// System preset NG words (non-user editable in UI).
  ///
  /// When empty, the widget attempts to load `preset_ng_words.json` from assets.
  final List<String> presetNgWords;

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
  /// This only affects rendering; gift/nicoad messages are always shown in
  /// the comment list regardless of this flag.
  final bool emphasizeGiftNicoadComment;

  /// Per-user comment color map. Keys are user IDs, values are ARGB32 ints.
  final Map<String, int> userColorMap;

  /// Per-user nickname (コテハン) map. Keys are user IDs, values are nicknames.
  final Map<String, String> userNicknameMap;

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

  /// When true, the comment screen announces via snackbar + AppBar badge
  /// every time a comment is hidden by NG word or NG user filtering.
  ///
  /// When false (default), filtering stays silent.
  final bool ngProtectionNotificationEnabled;
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
  /// [CommentFilterConfig.showGiftComment], which controls list visibility.
  final bool readGiftComment;

  /// When true, ニコニ広告 (nicoad) messages are read aloud by TTS.
  /// Defaults to false.
  ///
  /// Only the message body (`message.content`) is spoken — no additional
  /// formatting or user-name prefixing is applied. This is independent of
  /// [CommentFilterConfig.showNicoadComment], which controls list visibility.
  final bool readNicoadComment;

  /// Settings store for persisting teach command dictionary changes.
  final SettingsStore? settingsStore;

  /// Whether the speech output is currently muted.
  final bool isSpeechMuted;
}
