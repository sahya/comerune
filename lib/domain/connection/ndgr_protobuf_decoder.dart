import 'dart:convert';
import 'dart:developer' as developer;

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

class NdgrChunkedMessage {
  const NdgrChunkedMessage({
    this.id,
    this.serverTimestamp,
    this.chat,
    this.statistics,
    this.operatorComment,
    this.simpleNotificationV2,
  });

  final String? id;
  final DateTime? serverTimestamp;
  final NdgrChat? chat;
  final NdgrStatistics? statistics;

  /// Operator (運営) comment extracted from `ChunkedMessage.state.marquee`.
  final NdgrOperatorComment? operatorComment;

  /// SimpleNotificationV2 extracted from `NicoliveMessage.simple_notification_v2`.
  /// Used to surface system/emotion/notification messages.
  final NdgrSimpleNotificationV2? simpleNotificationV2;
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
    NdgrStatistics? statistics;
    NdgrOperatorComment? operatorComment;
    NdgrSimpleNotificationV2? simpleNotificationV2;

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
              statistics = result.statistics;
              simpleNotificationV2 = result.simpleNotificationV2;
            } on FormatException {
              chat = null;
              statistics = null;
              simpleNotificationV2 = null;
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
              // Statistics fallback from `NicoliveState.statistics` is
              // not wired in yet — see Issue #461 and the doc comment
              // on [_decodeNicoliveState]. Once upstream proto is
              // verified, populate `_NicoliveStateResult.statistics`
              // there and assign it to [statistics] here.
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
      simpleNotificationV2: simpleNotificationV2,
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
    NdgrStatistics? statistics;
    NdgrSimpleNotificationV2? simpleNotificationV2;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if ((fieldNumber == 1 || fieldNumber == 20) &&
          wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.chat / NicoliveMessage.overflowed_chat
        chat = _decodeChat(reader.readLengthDelimited());
      } else if (fieldNumber == 8 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.statistics (legacy path). Upstream proto is
        // migrating Statistics into NicoliveState (see
        // [_decodeNicoliveState] / Issue #461 for the fallback path that
        // reads NicoliveState.statistics). We keep this branch so that any
        // server still emitting the legacy layout continues to populate
        // viewers safely; the NicoliveState path will overwrite this value
        // when both are present (upstream is considered authoritative once
        // it ships the migration).
        statistics = _decodeStatistics(reader.readLengthDelimited());
      } else if (fieldNumber == 23 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.simple_notification_v2 (atoms.SimpleNotificationV2)
        //
        // Isolate decode failures so that a single malformed
        // SimpleNotificationV2 payload does not drop other already-decoded
        // fields in the same NicoliveMessage (chat / statistics). Mirrors
        // the try/catch around NicoliveState.operator_comment in
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
      statistics: statistics,
      simpleNotificationV2: simpleNotificationV2,
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

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 4 && wireType == _WireType.lengthDelimited) {
        operatorComment = _decodeMarquee(reader.readLengthDelimited());
      } else {
        reader.skipField(wireType);
      }
    }

    return _NicoliveStateResult(operatorComment: operatorComment);
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

  NdgrStatistics _decodeStatistics(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    int? viewers;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // Statistics.viewers
          if (wireType == _WireType.varint) {
            viewers = reader.readVarint();
          } else {
            reader.skipField(wireType);
          }
          break;
        default:
          reader.skipField(wireType);
      }
    }

    return NdgrStatistics(viewers: viewers);
  }

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
    this.statistics,
    this.simpleNotificationV2,
  });

  final NdgrChat? chat;
  final NdgrStatistics? statistics;
  final NdgrSimpleNotificationV2? simpleNotificationV2;
}

class _NicoliveStateResult {
  const _NicoliveStateResult({this.operatorComment});

  final NdgrOperatorComment? operatorComment;

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
