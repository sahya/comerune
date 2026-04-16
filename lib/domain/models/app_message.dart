const String kSystemBroadcastEndedMessageIdPrefix = 'system:broadcast_ended:';

/// Builds a unique system notification ID for broadcast-ended events.
///
/// `sequence` is appended to avoid ID collisions when multiple notifications
/// are created in the same millisecond.
String buildBroadcastEndedNotificationId({
  required int epochMilliseconds,
  required int sequence,
}) {
  return '$kSystemBroadcastEndedMessageIdPrefix$epochMilliseconds:$sequence';
}

/// Semantic category of a message flowing into [CommentScreen].
///
/// The enum also carries implicit expectations that downstream UI relies on
/// (visibility toggles, NG-filter bypass, protection-notification scope).
/// When adding a new variant, update:
///   - `_shouldDisplayMessage` (visibility)
///   - `_processNgProtectionNotifications` (NG-filter scope)
///   - any rendering branch that switches on [AppMessageType]
/// to keep those rules consistent.
enum AppMessageType {
  /// Viewer chat comment.
  ///
  /// Emitted by: NDGR normalizer (chat payload) and the legacy comment
  /// normalizer. Subject to NG word / NG user filters.
  chat,

  /// Broadcaster / staff "運営" (operator) comment.
  ///
  /// Emitted by: NDGR normalizer from
  /// `NicoliveState.marquee.display.operator_comment`. Its visibility in
  /// the list is controlled by `CommentFilterConfig.showOperatorComment`.
  operator,

  /// Generic client-side or protocol notification that does not fit the
  /// system / emotion specialised types.
  ///
  /// Emitted by: select_screen (synthetic broadcast-ended notification)
  /// and the legacy normalizer; also covers catch-all SimpleNotificationV2
  /// types that are not ichiba / emotion.
  notification,

  /// System notification originating from NDGR SimpleNotificationV2 with
  /// `type == ICHIBA` (市場).
  ///
  /// Visibility in the list is controlled by
  /// `CommentFilterConfig.showSystemMessage`.
  system,

  /// Viewer-sent emotion originating from NDGR SimpleNotificationV2 with
  /// `type == EMOTION`.
  ///
  /// Visibility in the list is controlled by
  /// `CommentFilterConfig.showEmotion`.
  emotion,

  /// Gift (ギフト) message. Reserved for future NDGR protobuf support;
  /// currently not emitted by the normalizer pipeline. Always visible and
  /// bypasses NG filters so an advertiser/sponsor name cannot accidentally
  /// silence them.
  gift,

  /// Nico-ad (ニコニ広告) message. Reserved for future NDGR protobuf
  /// support; currently not emitted by the normalizer pipeline. Always
  /// visible and bypasses NG filters.
  nicoad,
}

class AppMessage {
  const AppMessage({
    required this.id,
    required this.timestamp,
    this.userId,
    this.userName,
    required this.content,
    required this.type,
    this.raw,
  });

  final String id;
  final DateTime timestamp;
  final String? userId;

  /// User nickname from the NDGR protobuf (chat.name field).
  final String? userName;
  final String content;
  final AppMessageType type;
  final Object? raw;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
