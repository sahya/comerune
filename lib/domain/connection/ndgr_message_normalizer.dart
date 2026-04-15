import '../models/app_message.dart';
import 'ndgr_protobuf_decoder.dart';

/// Fallback ID prefix for operator (運営) comments that do not carry a
/// source ID. Paired with the server timestamp and a local sequence.
///
/// Named to match the existing `kSystemBroadcastEndedMessageIdPrefix`
/// pattern so fallback prefixes share a consistent `kNdgr…Prefix` shape.
const String kNdgrOperatorIdPrefix = 'ndgr-operator-';

/// Fallback ID prefix for simpleNotificationV2-based messages (system /
/// emotion / notification) that do not carry a source ID.
const String kNdgrNotifyIdPrefix = 'ndgr-notify-';

/// Upper bound on the length of an operator-comment `name` label after
/// sanitisation. Operator labels are typically short ("運営", "公式", etc.);
/// cap the rendered label to a conservative ceiling so a malformed or
/// abusive broadcaster-supplied name cannot expand the comment row
/// vertically or horizontally and push other UI off-screen.
const int _kOperatorUserNameMaxLength = 64;

/// Sanitises an operator-comment name (broadcaster-supplied) for safe
/// rendering as a label:
///   - strips CR / LF so the label cannot inject additional rows
///   - collapses any remaining control characters (U+0000..U+001F, U+007F)
///   - trims surrounding whitespace
///   - caps length at [_kOperatorUserNameMaxLength]
///
/// Returns `null` when the input is null or becomes empty after sanitation,
/// matching the existing "null = no label" convention used by
/// `_displayNameForMessage`.
String? _sanitizeOperatorUserName(String? raw) {
  if (raw == null) {
    return null;
  }
  // Strip CR/LF and other C0/C1 control characters. We intentionally keep
  // normal Unicode printable characters so CJK / emoji labels survive.
  //
  // `raw.runes` yields Unicode code points (not UTF-16 code units), and
  // `StringBuffer.writeCharCode` accepts code points up to U+10FFFF and emits
  // the appropriate UTF-16 surrogate pair when needed. So multi-code-unit
  // characters (emoji, supplementary CJK) round-trip correctly without manual
  // surrogate handling.
  final StringBuffer buffer = StringBuffer();
  for (final int codePoint in raw.runes) {
    if (codePoint == 0x0A || codePoint == 0x0D) {
      // Drop newline / carriage return explicitly.
      continue;
    }
    if (codePoint < 0x20 || codePoint == 0x7F) {
      // Drop other C0 control characters + DEL.
      continue;
    }
    buffer.writeCharCode(codePoint);
  }
  String cleaned = buffer.toString().trim();
  if (cleaned.isEmpty) {
    return null;
  }
  if (cleaned.length > _kOperatorUserNameMaxLength) {
    cleaned = cleaned.substring(0, _kOperatorUserNameMaxLength);
  }
  return cleaned;
}

class NdgrMessageNormalizer {
  int _fallbackSequence = 0;

  AppMessage? normalizeChunkedMessage(
    NdgrChunkedMessage source, {
    DateTime? receivedAt,
  }) {
    final DateTime timestamp =
        source.serverTimestamp ?? receivedAt ?? DateTime.now().toUtc();

    // Operator (運営) comment — emitted via NicoliveState.marquee.display.operator_comment.
    //
    // Trust boundary policy (Policy A):
    //   The `name` field on an operator comment is authored by the broadcaster
    //   (or the operating staff controlling the program) and is forwarded here
    //   verbatim as [AppMessage.userName]. The upstream protocol does not
    //   guarantee that this name is a stable identity label ("運営") — a
    //   broadcaster can set it to any string (e.g. `"視聴者一同"`).
    //
    //   We intentionally preserve the broadcaster-supplied value because:
    //     1. The operator-comment channel itself is broadcaster-authenticated
    //        by the upstream service, so any visual spoofing of the `name`
    //        label is the broadcaster's responsibility, not the client's.
    //     2. Operator comments are already rendered with a distinct
    //        background + `operatorTextColor` semantic, which is controlled
    //        by the client and cannot be spoofed via this field.
    //     3. Overriding or sanitising `name` on the client would hide
    //        legitimate, intentional labels chosen by the broadcaster.
    //
    //   If a future issue needs stronger visual attribution (fixed "運営"
    //   label or a badge), switch to Policy B/C and update the renderer; do
    //   not patch the field here.
    final NdgrOperatorComment? operatorComment = source.operatorComment;
    if (operatorComment != null && operatorComment.content.isNotEmpty) {
      return AppMessage(
        id: _resolveOperatorId(source.id, timestamp),
        timestamp: timestamp,
        userId: null,
        // Sanitise the broadcaster-supplied name before rendering: strip
        // CR/LF + C0/C1 control characters and cap to a conservative length
        // so a malformed/abusive label cannot inject additional lines or
        // push other UI off-screen. Policy A is still honored — we keep any
        // legitimate printable label verbatim (including CJK / emoji).
        userName: _sanitizeOperatorUserName(operatorComment.name),
        content: operatorComment.content,
        type: AppMessageType.operator,
        raw: source,
      );
    }

    // SimpleNotificationV2 — system/emotion/generic notification.
    final NdgrSimpleNotificationV2? notification = source.simpleNotificationV2;
    if (notification != null && notification.message.isNotEmpty) {
      return AppMessage(
        id: _resolveNotificationId(source.id, timestamp),
        timestamp: timestamp,
        userId: null,
        userName: null,
        content: notification.message,
        type: _notificationTypeToAppMessageType(notification.type),
        raw: source,
      );
    }

    final NdgrChat? chat = source.chat;
    if (chat == null) {
      return null;
    }
    if (chat.content.isEmpty) {
      return null;
    }

    final String id = _resolveId(source.id, chat, timestamp);

    return AppMessage(
      id: id,
      timestamp: timestamp,
      userId: _resolveUserId(chat),
      userName: chat.name != null && chat.name!.isNotEmpty ? chat.name : null,
      content: chat.content,
      type: AppMessageType.chat,
      raw: source,
    );
  }

  /// Maps SimpleNotificationV2 enum values to [AppMessageType].
  ///
  /// - ICHIBA (市場) → system
  /// - EMOTION       → emotion
  /// - others        → notification
  AppMessageType _notificationTypeToAppMessageType(
    NdgrSimpleNotificationV2Type type,
  ) {
    switch (type) {
      case NdgrSimpleNotificationV2Type.ichiba:
        return AppMessageType.system;
      case NdgrSimpleNotificationV2Type.emotion:
        return AppMessageType.emotion;
      case NdgrSimpleNotificationV2Type.unknown:
      case NdgrSimpleNotificationV2Type.cruise:
      case NdgrSimpleNotificationV2Type.programExtended:
      case NdgrSimpleNotificationV2Type.rankingIn:
      case NdgrSimpleNotificationV2Type.visited:
      case NdgrSimpleNotificationV2Type.supporterRegistered:
      case NdgrSimpleNotificationV2Type.userLevelUp:
      case NdgrSimpleNotificationV2Type.userFollow:
        return AppMessageType.notification;
    }
  }

  String _resolveId(String? sourceId, NdgrChat chat, DateTime timestamp) {
    if (sourceId != null && sourceId.isNotEmpty) {
      return sourceId;
    }

    if (chat.no != null) {
      return 'ndgr-chat-${chat.no}';
    }

    _fallbackSequence += 1;
    return 'ndgr-${timestamp.microsecondsSinceEpoch}-$_fallbackSequence';
  }

  String _resolveOperatorId(String? sourceId, DateTime timestamp) {
    if (sourceId != null && sourceId.isNotEmpty) {
      return sourceId;
    }
    _fallbackSequence += 1;
    return '$kNdgrOperatorIdPrefix${timestamp.microsecondsSinceEpoch}-$_fallbackSequence';
  }

  String _resolveNotificationId(String? sourceId, DateTime timestamp) {
    if (sourceId != null && sourceId.isNotEmpty) {
      return sourceId;
    }
    _fallbackSequence += 1;
    return '$kNdgrNotifyIdPrefix${timestamp.microsecondsSinceEpoch}-$_fallbackSequence';
  }

  String? _resolveUserId(NdgrChat chat) {
    if (chat.rawUserId != null) {
      return chat.rawUserId.toString();
    }

    if (chat.hashedUserId != null && chat.hashedUserId!.isNotEmpty) {
      return chat.hashedUserId;
    }

    return null;
  }
}
