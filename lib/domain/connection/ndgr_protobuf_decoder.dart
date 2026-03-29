import 'dart:convert';
import 'dart:typed_data';

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

class NdgrChunkedMessage {
  const NdgrChunkedMessage({
    this.id,
    this.serverTimestamp,
    this.chat,
    this.statistics,
  });

  final String? id;
  final DateTime? serverTimestamp;
  final NdgrChat? chat;
  final NdgrStatistics? statistics;
}

class NdgrPackedSegment {
  const NdgrPackedSegment({
    required this.messages,
    this.nextUri,
  });

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
            previousUri =
                _decodeMessageSegmentUri(reader.readLengthDelimited());
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

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      switch (fieldNumber) {
        case 1: // ChunkedMessage.meta
          if (wireType == _WireType.lengthDelimited) {
            final _ChunkedMessageMeta meta = _decodeChunkedMessageMeta(
              reader.readLengthDelimited(),
            );
            id = meta.id;
            serverTimestamp = meta.serverTimestamp;
          } else {
            reader.skipField(wireType);
          }
          break;
        case 2: // ChunkedMessage.message (oneof NicoliveMessage)
          if (wireType == _WireType.lengthDelimited) {
            final _NicoliveMessageResult result =
                _decodeNicoliveMessage(reader.readLengthDelimited());
            chat = result.chat;
            statistics = result.statistics;
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
            messages.add(decodeChunkedMessage(reader.readLengthDelimited()));
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

  _NicoliveMessageResult _decodeNicoliveMessage(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);

    NdgrChat? chat;
    NdgrStatistics? statistics;

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if ((fieldNumber == 1 || fieldNumber == 20) &&
          wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.chat / NicoliveMessage.overflowed_chat
        chat = _decodeChat(reader.readLengthDelimited());
      } else if (fieldNumber == 8 && wireType == _WireType.lengthDelimited) {
        // NicoliveMessage.statistics
        statistics = _decodeStatistics(reader.readLengthDelimited());
      } else {
        reader.skipField(wireType);
      }
    }

    return _NicoliveMessageResult(chat: chat, statistics: statistics);
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
      name: name,
      rawUserId: rawUserId,
      hashedUserId: hashedUserId,
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
    final _ProtoReader reader = _ProtoReader(bytes);

    while (!reader.isAtEnd) {
      final int tag = reader.readVarint();
      final int fieldNumber = tag >> 3;
      final int wireType = tag & 0x07;

      if (fieldNumber == 2 && wireType == _WireType.lengthDelimited) {
        return _decodePackedSegmentNextUri(reader.readLengthDelimited());
      }

      reader.skipField(wireType);
    }

    return null;
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
  const _ChunkedMessageMeta({
    this.id,
    this.serverTimestamp,
  });

  final String? id;
  final DateTime? serverTimestamp;
}

class _NicoliveMessageResult {
  const _NicoliveMessageResult({
    this.chat,
    this.statistics,
  });

  final NdgrChat? chat;
  final NdgrStatistics? statistics;
}

class _VarintReadResult {
  const _VarintReadResult({
    required this.value,
    required this.bytesRead,
  });

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
      return _VarintReadResult(
        value: value,
        bytesRead: index - start,
      );
    }

    shift += 7;
    if (shift > 63) {
      throw const FormatException('Varint is too long');
    }
  }

  return null;
}
