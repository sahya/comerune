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

/// Fallback ID prefix for gift (ギフト) messages that do not carry a
/// source ID.
const String kNdgrGiftIdPrefix = 'ndgr-gift-';

/// Fallback ID prefix for nicoad (ニコニ広告) messages that do not carry
/// a source ID.
const String kNdgrNicoadIdPrefix = 'ndgr-nicoad-';

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

/// Upper bound on the length of a chat (viewer) user name after
/// sanitisation. Same ceiling as the operator label: viewer nicknames are
/// typically short, and the operator cap has proven conservative enough
/// in practice. A separate constant keeps the two policies independently
/// tunable if a future issue needs to tighten chat names without affecting
/// the operator label.
const int _kChatUserNameMaxLength = 64;

/// Cached pattern for collapsing consecutive ASCII spaces and full-width
/// spaces into a single space during user-name sanitisation.
final RegExp _kWhitespaceRunPattern = RegExp(r'[ \u3000]+');

/// Shared sanitisation pipeline for user-name labels (operator and chat).
///
/// Steps:
///   1. strip invisible / control code points via [removeControlAndInvisibleChars]
///   2. collapse whitespace runs (ASCII + full-width space) into a single space
///   3. trim surrounding whitespace
///   4. cap at [maxLength] grapheme clusters (safe split via [Characters])
///   5. return `null` when the result is empty (= "no label")
///
/// Preserves ZWJ (U+200D) and Variation Selectors so ZWJ-composed emoji
/// and presentation selectors continue to render correctly.
///
/// Callers ([_sanitizeOperatorUserName], [_sanitizeChatUserName]) forward
/// a trust-model-specific [maxLength] so the two name fields can diverge
/// independently in the future without duplicating the pipeline.
String? _sanitizeUserName(String? raw, int maxLength) {
  if (raw == null) {
    return null;
  }
  final String controlFree = removeControlAndInvisibleChars(raw);
  final String cleaned = controlFree
      .replaceAll(_kWhitespaceRunPattern, ' ')
      .trim();
  if (cleaned.isEmpty) {
    return null;
  }
  final Characters chars = Characters(cleaned);
  if (chars.length > maxLength) {
    return chars.take(maxLength).toString();
  }
  return cleaned;
}

/// Sanitises an operator-comment name (broadcaster-supplied) for safe
/// rendering. The operator channel is broadcaster-authenticated upstream,
/// so the trust level is higher than chat names, but defence-in-depth
/// still strips CR/LF, bidi overrides, Tag Characters, and other
/// invisible controls. See [_sanitizeUserName] for the shared pipeline
/// and `domain/utils/unicode_sanitizer.dart` for the stripped categories.
String? _sanitizeOperatorUserName(String? raw) =>
    _sanitizeUserName(raw, _kOperatorUserNameMaxLength);

/// Sanitises a chat (viewer-supplied) user name for safe rendering.
/// Chat names originate from arbitrary viewer input with no upstream
/// authentication — the lowest-trust name field in the pipeline.
/// Uses the same shared pipeline as [_sanitizeOperatorUserName] via
/// [_sanitizeUserName] but with a separate length constant so the two
/// policies can diverge independently.
String? _sanitizeChatUserName(String? raw) =>
    _sanitizeUserName(raw, _kChatUserNameMaxLength);

/// Applies [removeControlAndInvisibleChars] to a message body and returns
/// the sanitised string, or `null` when sanitisation empties it.
///
/// Shared by the three [NdgrChunkedMessage] branches that forward a
/// broadcaster- or viewer-authored body into [AppMessage.content]
/// (operator comment, simpleNotificationV2, chat). Centralising the
/// sanitise → drop-on-empty policy keeps the three branches in
/// lock-step: if the stripped categories or the drop-on-empty policy
/// ever needs to change, it now happens in exactly one place.
///
/// Callers are expected to have already verified the raw body was
/// non-empty (each branch's early `isNotEmpty` guard). The `null`
/// return here specifically marks the "non-empty but invisible-only
/// payload" case. A non-null return is guaranteed to be non-empty.
String? _sanitizeMessageContent(String rawContent) {
  final String sanitized = removeControlAndInvisibleChars(rawContent);
  if (sanitized.isEmpty) {
    return null;
  }
  return sanitized;
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
      // Dropping when sanitisation empties the body is handled inside
      // [_sanitizeMessageContent] (shared with the simpleNotificationV2
      // and chat branches below).
      final String? sanitizedContent = _sanitizeMessageContent(
        operatorComment.content,
      );
      if (sanitizedContent == null) {
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
      // Sanitise the notification body symmetrically with the operator
      // comment content above: strip bidi overrides / Tag Characters /
      // other invisible controls so a Trojan Source style payload cannot
      // be smuggled into the rendered system / emotion / notification
      // bubble. Drop-on-empty policy lives in [_sanitizeMessageContent].
      final String? sanitizedContent = _sanitizeMessageContent(
        notification.message,
      );
      if (sanitizedContent == null) {
        return null;
      }
      return AppMessage(
        id: _buildNdgrId(kNdgrNotifyIdPrefix, source.id, null, timestamp),
        timestamp: timestamp,
        userId: null,
        userName: null,
        content: sanitizedContent,
        type: _notificationTypeToAppMessageType(notification.type),
        raw: source,
      );
    }

    // SimpleNotification (v1 legacy) — fallback for streams that still emit
    // ニコ生クルーズ / 市場 / エモーション through the older
    // `NicoliveMessage.simple_notification` field (7) instead of
    // SimpleNotificationV2 (23). Placed after the v2 branch so that when
    // both are present in the same chunk, v2 wins.
    final NdgrSimpleNotificationV1? notificationV1 = source.simpleNotification;
    if (notificationV1 != null && notificationV1.message.isNotEmpty) {
      final String? sanitizedContent = _sanitizeMessageContent(
        notificationV1.message,
      );
      if (sanitizedContent == null) {
        return null;
      }
      return AppMessage(
        id: _buildNdgrId(kNdgrNotifyIdPrefix, source.id, null, timestamp),
        timestamp: timestamp,
        userId: null,
        userName: null,
        content: sanitizedContent,
        type: _notificationV1TypeToAppMessageType(notificationV1.type),
        raw: source,
      );
    }

    // Nicoad (ニコニ広告). The decoder already collapses V0 / V1 into a
    // single [NdgrNicoad.message] so this branch does not need to know the
    // version.  The body is broadcaster/advertiser-authored text so the
    // same sanitiser pipeline (bidi / Tag / zero-width) is applied as to
    // chat / operator / notification content.  Downstream speech code in
    // `comment_screen.dart` additionally runs the NG-word filter on
    // [AppMessage.content] for nicoad (but bypasses it for gift), which is
    // the reason nicoad carries the user-facing message verbatim while
    // gift is synthesised from system fields only.
    final NdgrNicoad? nicoad = source.nicoad;
    if (nicoad != null && nicoad.message.isNotEmpty) {
      final String? sanitizedContent = _sanitizeMessageContent(nicoad.message);
      if (sanitizedContent == null) {
        return null;
      }
      return AppMessage(
        id: _buildNdgrId(kNdgrNicoadIdPrefix, source.id, null, timestamp),
        timestamp: timestamp,
        userId: null,
        userName: null,
        content: sanitizedContent,
        type: AppMessageType.nicoad,
        raw: source,
      );
    }

    // Gift (ギフト). Body is intentionally synthesised from the
    // advertiser / item / point fields only — never from any
    // advertiser-supplied free-text — so the comment-screen assumption
    // that gift bodies are system-generated (and therefore safe to
    // bypass the NG word filter) holds. The advertiser name goes through
    // the same chat-name sanitiser (strip bidi / Tag / zero-width, cap
    // to 64 grapheme clusters) because the upstream label is advertiser-
    // supplied and the gift row renders it in-line with the item name.
    final NdgrGift? gift = source.gift;
    if (gift != null) {
      final String? content = _formatGiftContent(gift);
      if (content == null) {
        return null;
      }
      return AppMessage(
        id: _buildNdgrId(kNdgrGiftIdPrefix, source.id, null, timestamp),
        timestamp: timestamp,
        userId: null,
        userName: _sanitizeChatUserName(gift.advertiserName),
        content: content,
        type: AppMessageType.gift,
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

    // Defense-in-depth for user-authored chat content.
    //
    // Unlike the operator branch (broadcaster-authenticated upstream by the
    // service) or the simpleNotificationV2 branch (system / broadcaster
    // originated), `chat.content` is arbitrary user input from any viewer
    // and therefore carries the widest attack surface in this pipeline:
    //   - Trojan Source / bidi overrides (U+202A-U+202E, U+2066-U+2069):
    //     flip the reading direction of a visible message to spoof what
    //     other users see.
    //   - Tag Characters (U+E0000-U+E007F): smuggle invisible payloads
    //     inside otherwise ordinary-looking text.
    //   - Zero-width / invisible spaces (NBSP, ZWSP, BOM, WORD JOINER,
    //     HANGUL FILLER, interlinear annotation anchors, etc.):
    //     break homoglyph comparisons and inject invisible gaps used for
    //     display spoofing ("user<ZWSP>name" vs "username").
    //   - C0 / C1 controls + LINE / PARAGRAPH SEPARATOR: inject extra
    //     rendered rows into the comment stream.
    //
    // The [removeControlAndInvisibleChars] helper intentionally preserves
    // ZWJ (U+200D) and Variation Selectors (U+FE00-U+FE0F, U+E0100-U+E01EF)
    // so ZWJ-composed emoji (family / profession / flag) and VS-16
    // presentation selectors keep rendering as single glyphs.
    //
    // Drop-on-empty policy (invisible-only payloads) lives in the shared
    // [_sanitizeMessageContent] helper, symmetric with the operator and
    // simpleNotificationV2 branches above.
    final String? sanitizedContent = _sanitizeMessageContent(chat.content);
    if (sanitizedContent == null) {
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
      userName: _sanitizeChatUserName(chat.name),
      content: sanitizedContent,
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

  /// Maps legacy SimpleNotification (v1) oneof field numbers to
  /// [AppMessageType].  Kept in lock-step with the v2 mapping so a
  /// category that arrives via either field produces the same downstream
  /// visibility / NG-filter behaviour.
  AppMessageType _notificationV1TypeToAppMessageType(
    NdgrSimpleNotificationV1Type type,
  ) {
    switch (type) {
      case NdgrSimpleNotificationV1Type.ichiba:
        return AppMessageType.system;
      case NdgrSimpleNotificationV1Type.emotion:
        return AppMessageType.emotion;
      case NdgrSimpleNotificationV1Type.unknown:
      case NdgrSimpleNotificationV1Type.quote:
      case NdgrSimpleNotificationV1Type.cruise:
      case NdgrSimpleNotificationV1Type.programExtended:
      case NdgrSimpleNotificationV1Type.rankingIn:
      case NdgrSimpleNotificationV1Type.visited:
      case NdgrSimpleNotificationV1Type.rankingUpdated:
      case NdgrSimpleNotificationV1Type.supporterRegistered:
      case NdgrSimpleNotificationV1Type.userLevelUp:
        return AppMessageType.notification;
    }
  }

  /// Synthesises the gift row body from system-supplied fields only.
  ///
  /// Preserves the invariant that gift bodies never carry arbitrary
  /// advertiser-authored text (the `Gift.message` field in the upstream
  /// proto is deliberately not decoded — see [NdgrGift]). Returns `null`
  /// when there is no usable fixed text to produce (both advertiser and
  /// item are absent); in that case the caller drops the gift rather than
  /// emit an empty bubble.
  ///
  /// The advertiser label runs through [_sanitizeChatUserName] at the
  /// callsite for the `userName` field; this helper additionally strips
  /// invisible characters from whichever advertiser/item substring it
  /// interpolates into the body so a crafted label cannot inject extra
  /// rendered rows into the comment list.
  String? _formatGiftContent(NdgrGift gift) {
    final String? safeAdvertiser = _sanitizeGiftLabel(gift.advertiserName);
    final String? safeItem = _sanitizeGiftLabel(gift.itemName);
    final int? point = gift.point;

    if (safeItem != null && safeAdvertiser != null) {
      if (point != null && point > 0) {
        return '${safeAdvertiser}さんが${safeItem}（${point}pt）をプレゼントしました';
      }
      return '${safeAdvertiser}さんが${safeItem}をプレゼントしました';
    }
    if (safeItem != null) {
      if (point != null && point > 0) {
        return 'ギフト：${safeItem}（${point}pt）';
      }
      return 'ギフト：${safeItem}';
    }
    if (safeAdvertiser != null) {
      if (point != null && point > 0) {
        return '${safeAdvertiser}さんからギフト（${point}pt）';
      }
      return '${safeAdvertiser}さんからギフト';
    }
    return null;
  }

  /// Strips invisible / control characters from a gift label substring and
  /// caps it at the chat-user-name length ceiling so a malformed or
  /// abusive label cannot inflate the rendered comment row. Returns
  /// `null` when the label empties after sanitisation.
  ///
  /// Shares [_sanitizeUserName] with the chat / operator name fields so
  /// the strip-set stays in lock-step across every user-authored label
  /// the comment list renders.
  String? _sanitizeGiftLabel(String? raw) =>
      _sanitizeUserName(raw, _kChatUserNameMaxLength);

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
