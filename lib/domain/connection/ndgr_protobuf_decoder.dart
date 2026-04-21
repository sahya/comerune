import 'dart:convert';
import 'dart:developer' as developer;

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';

class NdgrChunkedEntry {
  const NdgrChunkedEntry({
    this.segmentUri,
    this.previousUri,
    this.backwardSegmentUri,
    this.nextAt,
  });

  final String? segmentUri;
  final String? previousUri;
  final String? backwardSegmentUri;
  final int? nextAt;
}

class NdgrChat {
  const NdgrChat({
    required this.content,
    this.name,
    this.rawUserId,
    this.hashedUserId,
    this.no,
  });

  final String content;
  final String? name;
  final int? rawUserId;
  final String? hashedUserId;
  final int? no;
}

class NdgrStatistics {
  const NdgrStatistics({this.viewers});

  final int? viewers;
}

/// Operator (broadcaster) comment delivered via `NicoliveState.marquee.display.operator_comment`.
///
/// Mapped to [AppMessageType.operator] by [NdgrMessageNormalizer]. See
/// `proto/dwango/nicolive/chat/data/state.proto` (Marquee field 4) and
/// `proto/dwango/nicolive/chat/data/atoms/*` for the canonical schema.
class NdgrOperatorComment {
  const NdgrOperatorComment({required this.content, this.name, this.link});

  final String content;
  final String? name;

  /// Optional click-through target URL carried on the upstream operator
  /// comment.
  ///
  /// UNSANITIZED: do not render as a URL without validation. The upstream
  /// service does not guarantee this value is a well-formed, safe URL — it
  /// may contain whitespace, control characters, or unexpected schemes
  /// (`javascript:`, `data:`, custom schemes, etc.). Any future UI that
  /// surfaces this field as a tappable link MUST:
  ///   - parse the string with [Uri.tryParse] / reject malformed input
  ///   - allow-list schemes (typically only `http` / `https`)
  ///   - consider length / control-character sanitisation similar to the
  ///     operator `name` handling in [NdgrMessageNormalizer]
  final String? link;
}

/// `SimpleNotificationV2` payload from `atoms/notifications.proto`.
///
/// Field numbers (verified 2026-04 against upstream proto):
///   1: NotificationType type (enum)
///   2: string message
///
/// NotificationType enum values:
///   0 UNKNOWN, 1 ICHIBA, 2 EMOTION, 3 CRUISE, 4 PROGRAM_EXTENDED,
///   5 RANKING_IN, 6 VISITED, 7 SUPPORTER_REGISTERED, 8 USER_LEVEL_UP,
///   9 USER_FOLLOW.
enum NdgrSimpleNotificationV2Type {
  unknown,
  ichiba,
  emotion,
  cruise,
  programExtended,
  rankingIn,
  visited,
  supporterRegistered,
  userLevelUp,
  userFollow,
}

class NdgrSimpleNotificationV2 {
  const NdgrSimpleNotificationV2({required this.type, required this.message});

  final NdgrSimpleNotificationV2Type type;
  final String message;
}

/// Legacy (v1) `SimpleNotification` payload from `atoms.proto`.
///
/// Schema (verified 2026-04 against upstream proto): a single `oneof message`
/// whose field number identifies the notification category and whose value
/// is the pre-formatted display string.
///
/// Field numbers (oneof):
///   1 ichiba, 2 quote, 3 emotion, 4 cruise, 5 program_extended,
///   6 ranking_in, 7 visited, 8 ranking_updated, 9 supporter_registered,
///   10 user_level_up.
///
/// Retained alongside [NdgrSimpleNotificationV2] because the upstream service
/// is observed to still emit certain categories (notably CRUISE and legacy
/// ICHIBA) through this older field (NicoliveMessage.simple_notification at
/// field 7) rather than the newer SimpleNotificationV2 (field 23). Dropping
/// v1 would leave ニコ生クルーズ events invisible on streams that haven't
/// migrated yet.
enum NdgrSimpleNotificationV1Type {
  unknown,
  ichiba,
  quote,
  emotion,
  cruise,
  programExtended,
  rankingIn,
  visited,
  rankingUpdated,
  supporterRegistered,
  userLevelUp,
}

class NdgrSimpleNotificationV1 {
  const NdgrSimpleNotificationV1({required this.type, required this.message});

  final NdgrSimpleNotificationV1Type type;
  final String message;
}

/// Gift (ギフト) message extracted from
/// `NicoliveMessage.gift` (field 8). Schema (atoms.proto `message Gift`):
///   1: string item_id
///   2: optional int64 advertiser_user_id
///   3: string advertiser_name
///   4: int64 point
///   5: string message                (NOT surfaced — see normaliser)
///   6: string item_name
///   7: optional int32 contribution_rank
///
/// `message` is intentionally not carried on this class: downstream
/// rendering (`comment_screen.dart`) bypasses the NG word filter for gift
/// entries on the assumption that the body is a system-generated string of
/// the form "xxxさんがyyyをプレゼントしました". Preserving that invariant
/// here — by only exposing the system-derivable fields — means the NG-
/// bypass assumption cannot accidentally regress if a future advertiser-
/// supplied `message` ever carries arbitrary user text.
class NdgrGift {
  const NdgrGift({required this.itemName, this.advertiserName, this.point});

  final String itemName;
  final String? advertiserName;
  final int? point;
}

/// Nicoad (ニコニ広告) message extracted from
/// `NicoliveMessage.nicoad` (field 9). Schema (atoms.proto `message Nicoad`):
///   versions: oneof { V0 v0 = 1; V1 v1 = 2; }
///   V0: Latest latest = 1, repeated Ranking ranking = 2, int32 total_point = 3
///     Latest:  advertiser = 1, point = 2, optional message = 3
///     Ranking: advertiser = 1, rank = 2, optional message = 3, user_rank = 4
///   V1: total_ad_point = 1, string message = 2
///
/// Normalised into a single display [message] so downstream code does not
/// need to branch on V0 / V1. V1 wins when both are present (newer format).
/// V0 falls back to the `latest` sub-message; the `ranking` list is not
/// surfaced to keep the comment row single-line.
class NdgrNicoad {
  const NdgrNicoad({required this.message, this.advertiser, this.totalPoint});

  final String message;
  final String? advertiser;
  final int? totalPoint;
}

enum NdgrProgramStatus { unknown, ended }

class NdgrChunkedMessage {
  const NdgrChunkedMessage({
    this.id,
    this.serverTimestamp,
    this.chat,
    this.statistics,
    this.operatorComment,
    this.simpleNotification,
    this.simpleNotificationV2,
    this.gift,
    this.nicoad,
    this.programStatus,
  });

  final String? id;
  final DateTime? serverTimestamp;
  final NdgrChat? chat;
  final NdgrStatistics? statistics;

  /// Operator (運営) comment extracted from `ChunkedMessage.state.marquee`.
  final NdgrOperatorComment? operatorComment;

  /// Legacy SimpleNotification extracted from
  /// `NicoliveMessage.simple_notification` (field 7). Used as a fallback for
  /// streams that still emit e.g. ニコ生クルーズ through the v1 path
  /// instead of SimpleNotificationV2 (field 23).
  final NdgrSimpleNotificationV1? simpleNotification;

  /// SimpleNotificationV2 extracted from `NicoliveMessage.simple_notification_v2`.
  /// Used to surface system/emotion/notification messages.
  final NdgrSimpleNotificationV2? simpleNotificationV2;

  /// Gift (ギフト) extracted from `NicoliveMessage.gift` (field 8).
  final NdgrGift? gift;

  /// Nicoad (ニコニ広告) extracted from `NicoliveMessage.nicoad` (field 9).
  final NdgrNicoad? nicoad;

  /// Program status extracted from `ChunkedMessage.state.program_status`.
  /// Non-null with [NdgrProgramStatus.ended] when the broadcast has ended.
  final NdgrProgramStatus? programStatus;
}

class NdgrPackedSegment {
  const NdgrPackedSegment({required this.messages, this.nextUri});

  final List<NdgrChunkedMessage> messages;
  final String? nextUri;
}

class NdgrLengthDelimitedDecoder {
  static const int _maxFrameLengthBytes = 100 * 1024;
  static const int _maxBufferedBytes = 256 * 1024;

  final List<int> _buffer = <int>[];
  bool _waitingForMore = false;
  int _fragmentRestoreCount = 0;

  int get fragmentRestoreCount => _fragmentRestoreCount;

  List<Uint8List> add(List<int> chunk) {
    if (chunk.isEmpty) {
      return const <Uint8List>[];
    }

    if (_waitingForMore) {
      _fragmentRestoreCount += 1;
      _waitingForMore = false;
    }

    _buffer.addAll(chunk);
    if (_buffer.length > _maxBufferedBytes) {
      clear();
      return const <Uint8List>[];
    }

    final List<Uint8List> frames = <Uint8List>[];
    int offset = 0;
    bool didResetBuffer = false;

    while (offset < _buffer.length) {
      final _VarintReadResult? length;
      try {
        length = _tryReadVarintFromList(_buffer, offset);
      } on FormatException {
        clear();
        didResetBuffer = true;
        break;
      }
      if (length == null) {
        _waitingForMore = true;
        break;
      }
      if (length.value > _maxFrameLengthBytes) {
        clear();
        didResetBuffer = true;
        break;
      }

      final int frameStart = offset + length.bytesRead;
      final int frameEnd = frameStart + length.value;
      if (frameEnd > _buffer.length) {
        _waitingForMore = true;
        break;
      }

      frames.add(Uint8List.fromList(_buffer.sublist(frameStart, frameEnd)));
      offset = frameEnd;
    }

    if (!didResetBuffer && offset > 0) {
      _buffer.removeRange(0, offset);
    }

    return frames;
  }

  void clear() {
    _buffer.clear();
    _waitingForMore = false;
    _fragmentRestoreCount = 0;
  }
}

class NdgrProtobufDecoder {
  NdgrChunkedEntry decodeChunkedEntry(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String? segmentUri;
    String? previousUri;
    String? backwardSegmentUri;
    int? nextAt;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // Entry.segment (MessageSegment)
          if (wireType == _WireType.lengthDelimited) {
            segmentUri = _decodeMessageSegmentUri(reader.readLengthDelimited());
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // Entry.backward (BackwardSegment)
          if (wireType == _WireType.lengthDelimited) {
            backwardSegmentUri = _decodeBackwardSegmentUri(
              reader.readLengthDelimited(),
            );
          } else {
            reader.skipField(wireType);
          }
          break;
        case 3: // Entry.previous (MessageSegment)
          if (wireType == _WireType.lengthDelimited) {
            previousUri = _decodeMessageSegmentUri(
              reader.readLengthDelimited(),
            );
          } else {
            reader.skipField(wireType);
          }
          break;
        case 4: // Entry.next (ReadyForNext)
          if (wireType == _WireType.lengthDelimited) {
            nextAt = _decodeReadyForNextAt(reader.readLengthDelimited());
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrChunkedEntry(
      segmentUri: segmentUri,
      previousUri: previousUri,
      backwardSegmentUri: backwardSegmentUri,
      nextAt: nextAt,
    );
  }

  NdgrChunkedMessage decodeChunkedMessage(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String? id;
    DateTime? serverTimestamp;
    NdgrChat? chat;
    // `statistics` on [NdgrChunkedMessage] is retained as part of the
    // public shape for ndgr_client.dart, but the current proto does not
    // carry Statistics on NicoliveMessage — see the note on
    // [_NicoliveMessageResult] and Issue #461. Until the NicoliveState
    // fallback is added, this always passes through as `null`.
    const NdgrStatistics? statistics = null;
    NdgrOperatorComment? operatorComment;
    NdgrSimpleNotificationV1? simpleNotification;
    NdgrSimpleNotificationV2? simpleNotificationV2;
    NdgrGift? gift;
    NdgrNicoad? nicoad;
    NdgrProgramStatus? programStatus;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // ChunkedMessage.meta
          if (wireType == _WireType.lengthDelimited) {
            // Isolate meta decode failures so that a single malformed
            // timestamp / id does not drop the other fields (chat /
            // statistics / operator / simpleNotificationV2) in the same
            // chunk. Symmetry with case 2 / case 4.
            final Uint8List metaBytes = reader.readLengthDelimited();
            try {
              final _ChunkedMessageMeta meta = _decodeChunkedMessageMeta(
                metaBytes,
              );
              id = meta.id;
              serverTimestamp = meta.serverTimestamp;
            } on FormatException {
              // Leave id / serverTimestamp null; downstream normalisation
              // will synthesise a fallback id based on timestamp + sequence.
            }
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // ChunkedMessage.message (oneof NicoliveMessage)
          if (wireType == _WireType.lengthDelimited) {
            // Isolate NicoliveMessage decode failures so that a malformed
            // chat / statistics / simpleNotificationV2 payload does not
            // drop the meta or operator fields in the same chunk. Symmetry
            // with case 1 / case 4.
            final Uint8List messageBytes = reader.readLengthDelimited();
            try {
              final _NicoliveMessageResult result = _decodeNicoliveMessage(
                messageBytes,
              );
              chat = result.chat;
              simpleNotification = result.simpleNotification;
              simpleNotificationV2 = result.simpleNotificationV2;
              gift = result.gift;
              nicoad = result.nicoad;
            } on FormatException {
              chat = null;
              simpleNotification = null;
              simpleNotificationV2 = null;
              gift = null;
              nicoad = null;
            }
          } else {
            reader.skipField(wireType);
          }
          break;
        case 4: // ChunkedMessage.state (oneof NicoliveState)
          if (wireType == _WireType.lengthDelimited) {
            // Isolate decode failures in the nested state payload so that a
            // single malformed operator/marquee field does not drop other
            // already-decoded fields in the same chunk (e.g. a valid
            // simpleNotificationV2 from NicoliveMessage). On failure we leave
            // [operatorComment] null and continue.
            final Uint8List stateBytes = reader.readLengthDelimited();
            try {
              final _NicoliveStateResult stateResult = _decodeNicoliveState(
                stateBytes,
              );
              operatorComment = stateResult.operatorComment;
              programStatus = stateResult.programStatus;
            } on FormatException {
              operatorComment = null;
            }
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrChunkedMessage(
      id: id,
      serverTimestamp: serverTimestamp,
      chat: chat,
      statistics: statistics,
      operatorComment: operatorComment,
      simpleNotification: simpleNotification,
      simpleNotificationV2: simpleNotificationV2,
      gift: gift,
      nicoad: nicoad,
      programStatus: programStatus,
    );
  }

  NdgrPackedSegment decodePackedSegment(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    final List<NdgrChunkedMessage> messages = <NdgrChunkedMessage>[];
    String? nextUri;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // PackedSegment.messages (repeated ChunkedMessage)
          if (wireType == _WireType.lengthDelimited) {
            // Isolate decode failures per ChunkedMessage so a single
            // malformed message in the segment does not drop every
            // subsequent (valid) message in the same batch.
            final Uint8List chunkBytes = reader.readLengthDelimited();
            try {
              messages.add(decodeChunkedMessage(chunkBytes));
            } on FormatException {
              // Skip the malformed chunk and continue reading the rest of
              // the segment.
            }
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // PackedSegment.next (next packed segment uri)
          if (wireType == _WireType.lengthDelimited) {
            nextUri = _decodePackedSegmentNextUri(reader.readLengthDelimited());
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrPackedSegment(messages: messages, nextUri: nextUri);
  }

  _ChunkedMessageMeta _decodeChunkedMessageMeta(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String? id;
    DateTime? serverTimestamp;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // ChunkedMessageMeta.id
          if (wireType == _WireType.lengthDelimited) {
            id = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // ChunkedMessageMeta.at (google.protobuf.Timestamp)
          if (wireType == _WireType.lengthDelimited) {
            serverTimestamp = _decodeTimestamp(reader.readLengthDelimited());
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return _ChunkedMessageMeta(id: id, serverTimestamp: serverTimestamp);
  }

  /// Scans `bytes` for length-delimited fields matching [fieldNumber] and
  /// returns [decoder] applied to the payload of the last match (or `null`
  /// when absent). Sibling fields are skipped. Consolidates the
  /// "read one nested message, ignore the rest" NDGR wrapper layers
  /// (see `_decodeMarquee` and friends).
  T? _readSingleFieldLD<T>(
    Uint8List bytes,
    int fieldNumber,
    T Function(Uint8List) decoder,
  ) {
    final _ProtoReader reader = _ProtoReader(bytes);
    T? result;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int number = tag >> 3;
      final int wireType = tag & 0x07;

      if (number == fieldNumber && wireType == _WireType.lengthDelimited) {
        result = decoder(reader.readLengthDelimited());
      } else {
        reader.skipField(wireType);
      }
    }

    return result;
  }

  _NicoliveMessageResult _decodeNicoliveMessage(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    NdgrChat? chat;
    NdgrSimpleNotificationV1? simpleNotification;
    NdgrSimpleNotificationV2? simpleNotificationV2;
    NdgrGift? gift;
    NdgrNicoad? nicoad;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if ((fieldNumber == 1 || fieldNumber == 20) &&
          wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.chat (1) / NicoliveMessage.overflowed_chat (20)
        //
        // Design decision: chat is NOT wrapped in try/catch (unlike the
        // notification / gift / nicoad branches below).  Chat is the
        // primary payload of the NicoliveMessage — if it is malformed, the
        // entire message is semantically broken and should propagate as a
        // decode failure rather than silently producing a null chat while
        // other data is preserved.  Silently swallowing a chat decode
        // error would hide protocol drift from the maintainer and leave
        // the user with no visible comment.
        chat = _decodeChat(reader.readLengthDelimited());
      } else if (fieldNumber == 7 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.simple_notification (v1 legacy)
        //
        // Retained as a fallback path: servers that have not yet migrated
        // to SimpleNotificationV2 still emit categories like ニコ生クルーズ
        // through this field. Dropping v1 would leave those events
        // invisible. When both v1 and v2 are present in the same chunk,
        // v2 wins at the normaliser level.
        final Uint8List notificationBytes = reader.readLengthDelimited();
        try {
          simpleNotification = _decodeSimpleNotificationV1(notificationBytes);
        } on FormatException {
          simpleNotification = null;
        }
      } else if (fieldNumber == 8 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.gift (ギフト).
        //
        // Prior revisions routed this field to `_decodeStatistics`, which
        // was a protocol-drift bug: field 8 in the current proto is
        // `Gift gift`, not `Statistics statistics`. The misroute silently
        // dropped every gift event and, because the Gift wire format was
        // being re-interpreted as Statistics, also produced spurious
        // null-viewer Statistics payloads on every gift. Corrected to
        // decode Gift directly; viewer counts are now sourced via
        // NicoliveState (Issue #461) rather than this field.
        final Uint8List giftBytes = reader.readLengthDelimited();
        try {
          gift = _decodeGift(giftBytes);
        } on FormatException {
          gift = null;
        }
      } else if (fieldNumber == 9 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.nicoad (ニコニ広告).
        //
        // Not handled prior to this change — every nicoad event was being
        // skipped by the default branch. Isolate decode failures so a
        // single malformed V0 / V1 payload does not drop the rest of the
        // NicoliveMessage.
        final Uint8List nicoadBytes = reader.readLengthDelimited();
        try {
          nicoad = _decodeNicoad(nicoadBytes);
        } on FormatException {
          nicoad = null;
        }
      } else if (fieldNumber == 23 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.simple_notification_v2 (atoms.SimpleNotificationV2)
        //
        // Isolate decode failures so that a single malformed
        // SimpleNotificationV2 payload does not drop other already-decoded
        // fields in the same NicoliveMessage (chat / gift / nicoad).
        // Mirrors the try/catch around NicoliveState.operator_comment in
        // [decodeChunkedMessage] so both nested fields are equally robust
        // to protocol drift.
        //
        // Reading the length-delimited bytes first, then decoding inside
        // the try, keeps the outer reader advanced even when decode fails
        // — otherwise the malformed bytes would be re-parsed as the next
        // tag on the following loop iteration.
        final Uint8List notificationBytes = reader.readLengthDelimited();
        try {
          simpleNotificationV2 = _decodeSimpleNotificationV2(notificationBytes);
        } on FormatException {
          simpleNotificationV2 = null;
        }
      } else {
        reader.skipField(wireType);
      }
    }

    return _NicoliveMessageResult(
      chat: chat,
      simpleNotification: simpleNotification,
      simpleNotificationV2: simpleNotificationV2,
      gift: gift,
      nicoad: nicoad,
    );
  }

  /// Extracts the parts of `NicoliveState` the app currently consumes.
  ///
  /// Today this is only `operatorComment` (from
  /// `state.marquee.display.operator_comment`). The return type is kept
  /// as [_NicoliveStateResult] so that adding
  /// [_NicoliveStateResult.statistics] later — when upstream proto field
  /// numbers are confirmed (see Issue #461) — is a strictly additive
  /// change with no further refactor at the caller.
  ///
  /// Schema (verified against upstream proto, 2026-04):
  ///   NicoliveState.marquee    = field 4 (Marquee)
  ///   Marquee.display          = field 1 (Marquee.Display)
  ///   Display.operator_comment = field 1 (OperatorComment)
  ///   OperatorComment.content  = field 1 (string)
  ///   OperatorComment.name     = field 2 (optional string)
  ///   OperatorComment.link     = field 4 (optional string)
  ///
  /// Statistics fallback (Issue #461) is intentionally NOT implemented
  /// here yet: the upstream field number for `NicoliveState.statistics`
  /// is not yet independently verified against the current proto, and
  /// blindly decoding an unrelated sub-message as Statistics would
  /// produce silently-wrong viewer counts (worse than today's "null
  /// viewers"). The legacy `NicoliveMessage.statistics` (field 8) path
  /// is preserved unchanged so existing deployments keep working. Once
  /// upstream is confirmed, the fallback can be added by populating
  /// [_NicoliveStateResult.statistics] inside this loop.
  _NicoliveStateResult _decodeNicoliveState(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    NdgrOperatorComment? operatorComment;
    NdgrProgramStatus? programStatus;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 4 && wireType == _WireType.lengthDelimited) {
        operatorComment = _decodeMarquee(reader.readLengthDelimited());
      } else if (fieldNumber == 9 && wireType == _WireType.lengthDelimited) {
        try {
          programStatus = _decodeProgramStatus(reader.readLengthDelimited());
        } on FormatException {
          // Malformed ProgramStatus — leave null, do not drop other fields.
        }
      } else {
        reader.skipField(wireType);
      }
    }

    return _NicoliveStateResult(
      operatorComment: operatorComment,
      programStatus: programStatus,
    );
  }

  NdgrProgramStatus _decodeProgramStatus(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);
    int stateValue = 0;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 1 && wireType == _WireType.varint) {
        stateValue = reader.readVarint();
      } else {
        reader.skipField(wireType);
      }
    }

    return stateValue == 1
        ? NdgrProgramStatus.ended
        : NdgrProgramStatus.unknown;
  }

  NdgrOperatorComment? _decodeMarquee(Uint8List bytes) {
    // Marquee.display = field 1 (Marquee.Display)
    return _readSingleFieldLD<NdgrOperatorComment?>(
      bytes,
      1,
      _decodeMarqueeDisplay,
    );
  }

  NdgrOperatorComment? _decodeMarqueeDisplay(Uint8List bytes) {
    // Display.operator_comment = field 1 (OperatorComment)
    return _readSingleFieldLD<NdgrOperatorComment>(
      bytes,
      1,
      _decodeOperatorComment,
    );
  }

  NdgrOperatorComment _decodeOperatorComment(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String content = '';
    String? name;
    // `link` is decoded and carried on [NdgrOperatorComment] for schema
    // parity with the upstream proto, but it is not currently surfaced in
    // the UI. Kept here so future work (clickable operator link support)
    // can consume it without re-introducing a protobuf change.
    String? link;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // content
          if (wireType == _WireType.lengthDelimited) {
            content = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // name
          if (wireType == _WireType.lengthDelimited) {
            name = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 4: // link
          if (wireType == _WireType.lengthDelimited) {
            link = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrOperatorComment(
      content: content,
      name: name != null && name.isNotEmpty ? name : null,
      link: link != null && link.isNotEmpty ? link : null,
    );
  }

  /// Decodes `atoms.SimpleNotificationV2`.
  ///
  /// Schema (verified against upstream proto, 2026-04):
  ///   field 1: NotificationType type (enum / varint)
  ///   field 2: string message
  NdgrSimpleNotificationV2 _decodeSimpleNotificationV2(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    int rawType = 0;
    String message = '';

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1:
          if (wireType == _WireType.varint) {
            rawType = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2:
          if (wireType == _WireType.lengthDelimited) {
            message = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrSimpleNotificationV2(
      type: _simpleNotificationV2TypeFromInt(rawType),
      message: message,
    );
  }

  /// Decodes `SimpleNotification` (v1) from atoms.proto.
  ///
  /// Wire shape: a single `oneof message { string … }` where the selected
  /// field number identifies the category and the string value is the
  /// pre-formatted body. Returns `null` when no recognised field carries a
  /// non-empty payload (avoids emitting empty bubbles).
  NdgrSimpleNotificationV1? _decodeSimpleNotificationV1(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    NdgrSimpleNotificationV1Type type = NdgrSimpleNotificationV1Type.unknown;
    String message = '';
    bool resolved = false;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (wireType != _WireType.lengthDelimited) {
        reader.skipField(wireType);
        continue;
      }

      final String value = reader.readString();
      final NdgrSimpleNotificationV1Type? mapped =
          _simpleNotificationV1TypeFromField(fieldNumber);
      if (mapped != null && value.isNotEmpty) {
        type = mapped;
        message = value;
        resolved = true;
      }
    }

    if (!resolved) {
      return null;
    }
    return NdgrSimpleNotificationV1(type: type, message: message);
  }

  NdgrSimpleNotificationV1Type? _simpleNotificationV1TypeFromField(int field) {
    switch (field) {
      case 1:
        return NdgrSimpleNotificationV1Type.ichiba;
      case 2:
        return NdgrSimpleNotificationV1Type.quote;
      case 3:
        return NdgrSimpleNotificationV1Type.emotion;
      case 4:
        return NdgrSimpleNotificationV1Type.cruise;
      case 5:
        return NdgrSimpleNotificationV1Type.programExtended;
      case 6:
        return NdgrSimpleNotificationV1Type.rankingIn;
      case 7:
        return NdgrSimpleNotificationV1Type.visited;
      case 8:
        return NdgrSimpleNotificationV1Type.rankingUpdated;
      case 9:
        return NdgrSimpleNotificationV1Type.supporterRegistered;
      case 10:
        return NdgrSimpleNotificationV1Type.userLevelUp;
      default:
        return null;
    }
  }

  /// Decodes `Gift` from atoms.proto. Returns `null` when the gift is
  /// unusable for display (no item_name and no advertiser) so the
  /// normaliser can drop it rather than emit an empty bubble.
  NdgrGift? _decodeGift(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String itemName = '';
    String? advertiserName;
    int? point;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 3: // advertiser_name
          if (wireType == _WireType.lengthDelimited) {
            advertiserName = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 4: // point
          if (wireType == _WireType.varint) {
            point = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 6: // item_name
          if (wireType == _WireType.lengthDelimited) {
            itemName = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    final String? normalizedAdvertiser =
        advertiserName != null && advertiserName.isNotEmpty
        ? advertiserName
        : null;
    if (itemName.isEmpty && normalizedAdvertiser == null) {
      return null;
    }
    return NdgrGift(
      itemName: itemName,
      advertiserName: normalizedAdvertiser,
      point: point,
    );
  }

  /// Decodes `Nicoad` from atoms.proto. Collapses V0 / V1 into a single
  /// display [NdgrNicoad]. When both versions are present in the same
  /// payload, V1 wins (newer format).
  NdgrNicoad? _decodeNicoad(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    Uint8List? v0Bytes;
    Uint8List? v1Bytes;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (wireType != _WireType.lengthDelimited) {
        reader.skipField(wireType);
        continue;
      }
      switch (fieldNumber) {
        case 1: // v0
          v0Bytes = reader.readLengthDelimited();
          break;
        case 2: // v1
          v1Bytes = reader.readLengthDelimited();
          break;
        default:
          // Skip the payload of any unknown length-delimited field.
          reader.readLengthDelimited();
      }
    }

    if (v1Bytes != null) {
      final NdgrNicoad? v1 = _decodeNicoadV1(v1Bytes);
      if (v1 != null) {
        return v1;
      }
    }
    if (v0Bytes != null) {
      return _decodeNicoadV0(v0Bytes);
    }
    return null;
  }

  NdgrNicoad? _decodeNicoadV1(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    int? totalAdPoint;
    String message = '';

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1:
          if (wireType == _WireType.varint) {
            totalAdPoint = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2:
          if (wireType == _WireType.lengthDelimited) {
            message = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    if (message.isEmpty) {
      return null;
    }
    return NdgrNicoad(message: message, totalPoint: totalAdPoint);
  }

  NdgrNicoad? _decodeNicoadV0(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    Uint8List? latestBytes;
    int? totalPoint;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // latest
          if (wireType == _WireType.lengthDelimited) {
            latestBytes = reader.readLengthDelimited();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 3: // total_point
          if (wireType == _WireType.varint) {
            totalPoint = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    if (latestBytes == null) {
      return null;
    }
    return _decodeNicoadV0Latest(latestBytes, totalPoint);
  }

  NdgrNicoad? _decodeNicoadV0Latest(Uint8List bytes, int? totalPoint) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String? advertiser;
    int? point;
    String? message;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1:
          if (wireType == _WireType.lengthDelimited) {
            advertiser = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2:
          if (wireType == _WireType.varint) {
            point = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 3:
          if (wireType == _WireType.lengthDelimited) {
            message = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    final String? resolvedAdvertiser =
        advertiser != null && advertiser.isNotEmpty ? advertiser : null;
    if (message != null && message.isNotEmpty) {
      return NdgrNicoad(
        message: message,
        advertiser: resolvedAdvertiser,
        totalPoint: totalPoint,
      );
    }
    if (resolvedAdvertiser != null && point != null) {
      // Defence-in-depth for the synthesised body: the advertiser label
      // is pulled verbatim from the server and interpolated into a new
      // string that ends up in [AppMessage.content]. The downstream
      // [_sanitizeMessageContent] pipeline strips control characters but
      // does NOT enforce a length cap, so an adversarial server could
      // balloon the rendered comment row by shipping a multi-megabyte
      // advertiser string. Cap to [_kNicoadAdvertiserMaxLength] grapheme
      // clusters (same ceiling as chat user names) before synthesis.
      final String cappedAdvertiser = _capGraphemes(
        resolvedAdvertiser,
        _kNicoadAdvertiserMaxLength,
      );
      return NdgrNicoad(
        message: '${cappedAdvertiser}さんが${point}ptニコニ広告しました',
        advertiser: cappedAdvertiser,
        totalPoint: totalPoint,
      );
    }
    return null;
  }

  /// Upper bound on the length of the advertiser label that may be
  /// interpolated into a Nicoad V0 synthesised body.
  ///
  /// Intentionally matches the `_kOperatorUserNameMaxLength` /
  /// `_kChatUserNameMaxLength` constants in [NdgrMessageNormalizer]
  /// (same numeric value, independent definition). The three ceilings
  /// are deliberately kept separate so a future issue can tighten any
  /// one label policy without affecting the others — see the sibling
  /// docstring on `_kChatUserNameMaxLength` in the normaliser.
  static const int _kNicoadAdvertiserMaxLength = 64;

  /// Truncates [value] at [maxGraphemes] grapheme clusters, using the
  /// same `Characters`-based split as `_sanitizeUserName` in
  /// [NdgrMessageNormalizer] so a multi-byte emoji at the boundary is
  /// not split into a lone surrogate. Returns [value] unchanged when it
  /// already fits within [maxGraphemes] clusters.
  @visibleForTesting
  static String capGraphemesForTest(String value, int maxGraphemes) =>
      _capGraphemesImpl(value, maxGraphemes);

  String _capGraphemes(String value, int maxGraphemes) =>
      _capGraphemesImpl(value, maxGraphemes);

  static String _capGraphemesImpl(String value, int maxGraphemes) {
    final Characters chars = Characters(value);
    if (chars.length <= maxGraphemes) {
      return value;
    }
    return chars.take(maxGraphemes).toString();
  }

  /// Highest `NotificationType` enum value the decoder currently knows about
  /// (verified 2026-04 against upstream proto: 0 UNKNOWN … 9 USER_FOLLOW).
  ///
  /// When the upstream proto adds a new enum value, the
  /// [_simpleNotificationV2TypeFromInt] `assert` below will fire in debug
  /// builds so developers notice the drift instead of silently falling back
  /// to [NdgrSimpleNotificationV2Type.unknown]. Bump this constant (and add
  /// the new `case` branch) whenever upstream ships a new value.
  static const int _kMaxKnownNotificationTypeRaw = 9;

  NdgrSimpleNotificationV2Type _simpleNotificationV2TypeFromInt(int raw) {
    // Debug-build only: upstream proto may have added a new enum value that
    // this decoder does not map yet. We DO NOT throw on drift — doing so
    // would take the streaming decode pipeline down for any contributor
    // running a debug build against a live server the moment upstream
    // ships a new NotificationType. Instead we surface a debug log so the
    // developer notices, and we keep the existing `unknown` fallback so
    // the rest of the chunk (chat body, statistics, operator comment)
    // still decodes safely. Release builds strip the `assert` entirely.
    // See Issue #478.
    assert(() {
      if (raw < 0 || raw > _kMaxKnownNotificationTypeRaw) {
        debugPrint(
          'NdgrProtobufDecoder: unexpected SimpleNotificationV2 type '
          'raw=$raw (known max=$_kMaxKnownNotificationTypeRaw). '
          'Upstream proto may have added a new enum value — extend the '
          'switch in _simpleNotificationV2TypeFromInt and bump '
          '_kMaxKnownNotificationTypeRaw.',
        );
      }
      return true;
    }());
    switch (raw) {
      case 1:
        return NdgrSimpleNotificationV2Type.ichiba;
      case 2:
        return NdgrSimpleNotificationV2Type.emotion;
      case 3:
        return NdgrSimpleNotificationV2Type.cruise;
      case 4:
        return NdgrSimpleNotificationV2Type.programExtended;
      case 5:
        return NdgrSimpleNotificationV2Type.rankingIn;
      case 6:
        return NdgrSimpleNotificationV2Type.visited;
      case 7:
        return NdgrSimpleNotificationV2Type.supporterRegistered;
      case 8:
        return NdgrSimpleNotificationV2Type.userLevelUp;
      case 9:
        return NdgrSimpleNotificationV2Type.userFollow;
      case 0:
        return NdgrSimpleNotificationV2Type.unknown;
      default:
        // Log once per unexpected value in debug builds so that upstream
        // enum drift (new NotificationType) is observable during
        // development. Gated on [kDebugMode] so release builds stay silent.
        if (kDebugMode) {
          developer.log(
            'Unknown SimpleNotificationV2 type rawType=$raw',
            name: 'NdgrProtobufDecoder',
          );
        }
        return NdgrSimpleNotificationV2Type.unknown;
    }
  }

  // [_decodeStatistics] was removed alongside the field-8 misroute fix: the
  // only caller was the buggy `NicoliveMessage.statistics` path, which in
  // the current proto is actually `Gift gift = 8`. When the
  // NicoliveState.statistics fallback (Issue #461) is implemented, the
  // field-1 decoder can be re-introduced inside [_decodeNicoliveState].

  NdgrChat _decodeChat(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    String content = '';
    String? name;
    int? rawUserId;
    String? hashedUserId;
    int? no;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // Chat.content
          if (wireType == _WireType.lengthDelimited) {
            content = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // Chat.name (user nickname from protobuf)
          if (wireType == _WireType.lengthDelimited) {
            name = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 5: // Chat.raw_user_id
          if (wireType == _WireType.varint) {
            rawUserId = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 6: // Chat.hashed_user_id
          if (wireType == _WireType.lengthDelimited) {
            hashedUserId = reader.readString();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 8: // Chat.no
          if (wireType == _WireType.varint) {
            no = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrChat(
      content: content,
      name: name != null && name.isNotEmpty ? name : null,
      rawUserId: rawUserId,
      hashedUserId: hashedUserId != null && hashedUserId.isNotEmpty
          ? hashedUserId
          : null,
      no: no,
    );
  }

  String? _decodeMessageSegmentUri(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 3 && wireType == _WireType.lengthDelimited) {
        return reader.readString();
      }

      reader.skipField(wireType);
    }

    return null;
  }

  String? _decodeBackwardSegmentUri(Uint8List bytes) {
    // BackwardSegment.segment = field 2. Semantics note:
    // `_readSingleFieldLD` is last-match-wins; the pre-refactor loop was
    // first-match-wins. Equivalent for singular proto fields (current
    // case) per the protobuf spec ("last value wins for singular fields").
    //
    // If the upstream schema ever promotes `BackwardSegment.segment` to
    // `repeated`, this path will silently shift from "first segment URI"
    // to "last segment URI". At that point, replace this helper with a
    // first-match-wins or a repeated-aware reader and update the
    // corresponding test. Searching for the string literal
    // `_decodeBackwardSegmentUri` will locate every affected site.
    return _readSingleFieldLD<String?>(bytes, 2, _decodePackedSegmentNextUri);
  }

  String? _decodePackedSegmentNextUri(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 1 && wireType == _WireType.lengthDelimited) {
        return reader.readString();
      }

      reader.skipField(wireType);
    }

    return null;
  }

  int? _decodeReadyForNextAt(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 1 && wireType == _WireType.varint) {
        return reader.readVarint();
      }

      reader.skipField(wireType);
    }

    return null;
  }

  DateTime? _decodeTimestamp(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    int seconds = 0;
    int nanos = 0;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // Timestamp.seconds
          if (wireType == _WireType.varint) {
            seconds = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // Timestamp.nanos
          if (wireType == _WireType.varint) {
            nanos = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return DateTime.fromMicrosecondsSinceEpoch(
      (seconds * 1000000) + (nanos ~/ 1000),
      isUtc: true,
    );
  }
}

class _WireType {
  static const int varint = 0;
  static const int fixed64 = 1;
  static const int lengthDelimited = 2;
  static const int fixed32 = 5;
}

class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  int readVarint() {
    int value = 0;
    int shift = 0;

    while (true) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Unexpected EOF while reading varint');
      }

      final int byte = _bytes[_offset++];
      value |= (byte & 0x7f) << shift;

      if ((byte & 0x80) == 0) {
        return value;
      }

      shift += 7;
      if (shift > 63) {
        throw const FormatException('Varint is too long');
      }
    }
  }

  Uint8List readLengthDelimited() {
    final int length = readVarint();
    if (length < 0) {
      throw const FormatException('Negative length');
    }

    final int end = _offset + length;
    if (end > _bytes.length) {
      throw const FormatException('Unexpected EOF while reading bytes');
    }

    final Uint8List value = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return value;
  }

  String readString() {
    return utf8.decode(readLengthDelimited(), allowMalformed: true);
  }

  void skipField(int wireType) {
    switch (wireType) {
      case _WireType.varint:
        readVarint();
        return;
      case _WireType.fixed64:
        _skipBytes(8);
        return;
      case _WireType.lengthDelimited:
        final int length = readVarint();
        _skipBytes(length);
        return;
      case _WireType.fixed32:
        _skipBytes(4);
        return;
      default:
        throw FormatException('Unsupported wire type: $wireType');
    }
  }

  void _skipBytes(int count) {
    if (count < 0) {
      throw const FormatException('Negative skip count');
    }

    final int next = _offset + count;
    if (next > _bytes.length) {
      throw const FormatException('Unexpected EOF while skipping bytes');
    }

    _offset = next;
  }
}

class _ChunkedMessageMeta {
  const _ChunkedMessageMeta({this.id, this.serverTimestamp});

  final String? id;
  final DateTime? serverTimestamp;
}

class _NicoliveMessageResult {
  const _NicoliveMessageResult({
    this.chat,
    this.simpleNotification,
    this.simpleNotificationV2,
    this.gift,
    this.nicoad,
  });

  final NdgrChat? chat;
  final NdgrSimpleNotificationV1? simpleNotification;
  final NdgrSimpleNotificationV2? simpleNotificationV2;
  final NdgrGift? gift;
  final NdgrNicoad? nicoad;

  // `statistics` is intentionally not on this result: the current upstream
  // proto does not carry Statistics on NicoliveMessage (field 8 is Gift).
  // The NicoliveState.statistics fallback path lives on
  // [_NicoliveStateResult] and is tracked by Issue #461.
}

class _NicoliveStateResult {
  const _NicoliveStateResult({this.operatorComment, this.programStatus});

  final NdgrOperatorComment? operatorComment;
  final NdgrProgramStatus? programStatus;

  // NOTE(Issue #461): a future `NicoliveStatistics? statistics` field
  // will live here once upstream proto field numbers are confirmed.
  // Adding it is strictly additive and requires no caller refactor —
  // see the doc comment on [_decodeNicoliveState] for details.
}

class _VarintReadResult {
  const _VarintReadResult({required this.value, required this.bytesRead});

  final int value;
  final int bytesRead;
}

_VarintReadResult? _tryReadVarintFromList(List<int> buffer, int start) {
  int value = 0;
  int shift = 0;
  int index = start;

  while (index < buffer.length) {
    final int byte = buffer[index];
    value |= (byte & 0x7f) << shift;

    index += 1;
    if ((byte & 0x80) == 0) {
      return _VarintReadResult(value: value, bytesRead: index - start);
    }

    shift += 7;
    if (shift > 63) {
      throw const FormatException('Varint is too long');
    }
  }

  return null;
}
