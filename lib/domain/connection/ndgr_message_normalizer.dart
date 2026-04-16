import 'package:characters/characters.dart';

import '../models/app_message.dart';
import '../utils/unicode_sanitizer.dart';
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

/// Prefix for chat ids that fall back to `${prefix}${chat.no}` when the
/// upstream ChunkedMessageMeta.id is missing but the chat carries a
/// comment number. Library-private so the refactor does not widen the
/// public surface of this file — the prior behaviour inlined this literal.
const String _kNdgrChatNoIdPrefix = 'ndgr-chat-';

/// Prefix for chat ids that cannot resolve to either a source id or a
/// comment number and must use a local-sequence fallback. Intentionally
/// shorter than [_kNdgrChatNoIdPrefix] to match the historical
/// `ndgr-${microsecondsSinceEpoch}-${seq}` shape emitted before the
/// refactor so persisted ids round-trip across restarts.
const String _kNdgrChatFallbackTimestampPrefix = 'ndgr-';

/// Upper bound on the length of an operator-comment `name` label after
/// sanitisation. Operator labels are typically short ("運営", "公式", etc.);
/// cap the rendered label to a conservative ceiling so a malformed or
/// abusive broadcaster-supplied name cannot expand the comment row
/// vertically or horizontally and push other UI off-screen.
const int _kOperatorUserNameMaxLength = 64;

/// Cached pattern for collapsing consecutive ASCII spaces and full-width
/// spaces into a single space during operator-name sanitisation.
final RegExp _kWhitespaceRunPattern = RegExp(r'[ \u3000]+');

/// Sanitises an operator-comment name (broadcaster-supplied) for safe
/// rendering as a label:
///   - strips CR / LF, line/paragraph separators (U+2028/2029) so the label
///     cannot inject additional rows
///   - strips C0/C1 control characters (U+0000..U+001F, U+007F..U+009F)
///   - strips bidi overrides / isolate controls / Arabic Letter Mark /
///     Mongolian Vowel Separator / Tag Characters so the label cannot spoof
///     its own direction (RTL / Trojan Source)
///   - trims surrounding whitespace
///   - caps length at [_kOperatorUserNameMaxLength]
///
/// Preserves ZWJ (U+200D) and Variation Selectors (U+FE00-U+FE0F,
/// U+E0100-U+E01EF) so ZWJ-composed emoji and presentation selectors
/// continue to render correctly.
///
/// Returns `null` when the input is null or becomes empty after sanitation,
/// matching the existing "null = no label" convention used by
/// `_displayNameForMessage`.
///
/// Kept symmetric with the snackbar sanitiser in `comment_screen.dart`
/// (`_sanitizeSingleLine`) — both delegate to
/// [removeControlAndInvisibleChars]. See `domain/utils/unicode_sanitizer.dart`
/// for the rationale behind the preserved / stripped categories.
String? _sanitizeOperatorUserName(String? raw) {
  if (raw == null) {
    return null;
  }
  // Delegate to the shared helper so the operator label and the snackbar
  // label strip the same category of spoofing / layout-breaking characters.
  // TAB (U+0009) is stripped by the C0 block inside the helper; collapse
  // any remaining intra-label whitespace run into a single space so the
  // label does not end up with "前<TAB>後" → "前後" artifacts when
  // `_removeControlAndInvisible` previously dropped the TAB silently.
  final String controlFree = removeControlAndInvisibleChars(raw);
  final String cleaned = controlFree
      .replaceAll(_kWhitespaceRunPattern, ' ')
      .trim();
  if (cleaned.isEmpty) {
    return null;
  }
  // Count grapheme clusters (user-perceived characters) so the cap never
  // slices a surrogate pair or a ZWJ-composed emoji cluster in half.
  // `String.length` counts UTF-16 code units, so a naive
  // `substring(0, _kOperatorUserNameMaxLength)` could leave a dangling
  // surrogate at the boundary and produce U+FFFD on the next render.
  final Characters chars = Characters(cleaned);
  if (chars.length > _kOperatorUserNameMaxLength) {
    return chars.take(_kOperatorUserNameMaxLength).toString();
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
    //
    //   Defense-in-depth for both `name` and `content`:
    //   While Policy A preserves broadcaster-authored *printable* text
    //   verbatim, we still strip CR / LF / C0 controls / bidi overrides /
    //   Tag Characters from both fields.  These code points are never
    //   part of a legitimate label or message body, but they CAN inject
    //   additional UI rows (CR / LF), reverse the reading direction
    //   (bidi overrides → Trojan Source), or smuggle invisible payloads
    //   (Tag Characters).  Stripping them is a client-side rendering
    //   concern, not an override of the broadcaster's intent.
    final NdgrOperatorComment? operatorComment = source.operatorComment;
    if (operatorComment != null && operatorComment.content.isNotEmpty) {
      // Sanitise the content body symmetrically with the name: strip
      // bidi overrides, Tag Characters, and other invisible controls
      // that could produce Trojan Source style visual spoofing inside
      // the operator-comment bubble.  Operator comments are single-line
      // marquee messages in practice (CR/LF falls in the C0 block and
      // is stripped by the shared helper).
      //
      // Drop the whole message when the sanitised content is empty — an
      // operator-comment body that was *non-empty but consists only of
      // invisible characters* is either malformed or deliberately crafted
      // to inject an invisible payload; rendering an empty bubble would
      // leak a row of UI without any user value.  Mirrors the chat path
      // below which also returns null on empty content.
      final String sanitizedContent = removeControlAndInvisibleChars(
        operatorComment.content,
      );
      if (sanitizedContent.isEmpty) {
        return null;
      }
      return AppMessage(
        id: _buildNdgrId(kNdgrOperatorIdPrefix, source.id, null, timestamp),
        timestamp: timestamp,
        userId: null,
        // Sanitise the broadcaster-supplied name before rendering: strip
        // CR/LF + C0/C1 control characters and cap to a conservative length
        // so a malformed/abusive label cannot inject additional lines or
        // push other UI off-screen. Policy A is still honored — we keep any
        // legitimate printable label verbatim (including CJK / emoji).
        userName: _sanitizeOperatorUserName(operatorComment.name),
        content: sanitizedContent,
        type: AppMessageType.operator,
        raw: source,
      );
    }

    // SimpleNotificationV2 — system/emotion/generic notification.
    final NdgrSimpleNotificationV2? notification = source.simpleNotificationV2;
    if (notification != null && notification.message.isNotEmpty) {
      return AppMessage(
        id: _buildNdgrId(kNdgrNotifyIdPrefix, source.id, null, timestamp),
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

    final String id = _buildNdgrId(
      _kNdgrChatNoIdPrefix,
      source.id,
      chat.no,
      timestamp,
      timestampPrefix: _kNdgrChatFallbackTimestampPrefix,
    );

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

  /// Builds a stable id for a normalized NDGR message, consolidating the
  /// pre-refactor per-type `_resolveId` / `_resolveOperatorId` /
  /// `_resolveNotificationId` helpers. Resolution order:
  ///   1. non-empty [sourceId] verbatim (upstream ChunkedMessageMeta.id),
  ///   2. `${prefix}${no}` when [no] is non-null (chat path only),
  ///   3. `${timestampPrefix ?? prefix}${microsecondsSinceEpoch}-${seq}`.
  ///
  /// [timestampPrefix] is separate from [prefix] so the chat path can
  /// keep its historical `ndgr-${ts}-${seq}` fallback shape alongside the
  /// `ndgr-chat-${no}` no-path. Fallback sequence is per-normalizer.
  String _buildNdgrId(
    String prefix,
    String? sourceId,
    int? no,
    DateTime timestamp, {
    String? timestampPrefix,
  }) {
    if (sourceId != null && sourceId.isNotEmpty) {
      return sourceId;
    }
    if (no != null) {
      return '$prefix$no';
    }
    _fallbackSequence += 1;
    final String tsPrefix = timestampPrefix ?? prefix;
    return '$tsPrefix${timestamp.microsecondsSinceEpoch}-$_fallbackSequence';
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
