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
  /// the list is controlled by
  /// `MessageTypeVisibilityConfig.showOperatorComment`.
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
  /// `MessageTypeVisibilityConfig.showSystemMessage`.
  system,

  /// Viewer-sent emotion originating from NDGR SimpleNotificationV2 with
  /// `type == EMOTION`.
  ///
  /// Visibility in the list is controlled by
  /// `MessageTypeVisibilityConfig.showEmotion`.
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
    this.commentNo,
    this.raw,
  });

  final String id;
  final DateTime timestamp;
  final String? userId;

  /// User nickname from the NDGR protobuf (chat.name field).
  final String? userName;
  final String content;
  final AppMessageType type;

  /// Comment number (コメ番) extracted from NDGR `Chat.no` (proto field 8,
  /// int32) for Issue #784. Always `null` for [AppMessageType.operator] /
  /// `system` / `notification` / `emotion` / `gift` / `nicoad` because
  /// those payloads do not carry a `Chat` body. Always `null` for
  /// forwarded chats (e.g. ニコ生クルーズ) because the source-stream
  /// number would mislead viewers about the current stream's count.
  /// Only populated for native chat messages and only after passing
  /// `_sanitizeCommentNo`'s range check (`1 ≤ no ≤ 0x7FFFFFFF`);
  /// out-of-range values are coerced to `null`.
  ///
  /// **Do not use as a unique key, sort key, or de-duplication key.**
  /// The upstream service does not guarantee continuity or uniqueness of
  /// `Chat.no` (best-effort numbering, per NDGRClient docstring). Use
  /// [id] for any such role.
  ///
  /// **Privacy / tracking caveat (review #784, 守護仙人指摘):** when this
  /// number is paired with a stream id and a user id it can act as a
  /// stable per-user activity marker. New code that emits [commentNo]
  /// to log files, analytics endpoints, or shared exports MUST consider
  /// the resulting traceability and prefer aggregation over raw
  /// per-message values.
  ///
  /// **Future-extension caveat (review #784, 未来仙人指摘):** this is a
  /// chat-only field and the current shape (flat `int?` on every
  /// `AppMessage`) leaves the value `null` for the majority of message
  /// types. New per-message numeric metadata for emotion / gift / nicoad
  /// should NOT reuse this field — introduce a typed payload object on
  /// `raw`, or split `AppMessage` into per-type sealed variants, rather
  /// than overload `commentNo` with a meaning beyond chat numbering.
  final int? commentNo;

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
