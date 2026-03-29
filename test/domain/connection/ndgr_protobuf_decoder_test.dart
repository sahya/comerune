import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/ndgr_protobuf_decoder.dart';

void main() {
  group('NdgrProtobufDecoder', () {
    test('decodes chunked message chat payload and server timestamp', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> timestamp = <int>[
        ..._varintField(1, 1700000000),
        ..._varintField(2, 500000000),
      ];

      final List<int> meta = <int>[
        ..._stringField(1, 'msg-1'),
        ..._bytesField(2, timestamp),
      ];

      final List<int> chat = <int>[
        ..._stringField(1, 'hello'),
        ..._varintField(5, 123456),
        ..._stringField(6, 'hashed-1'),
        ..._varintField(8, 99),
      ];

      final List<int> nicoliveMessage = <int>[
        ..._bytesField(1, chat),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(1, meta),
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.id, 'msg-1');
      expect(
        message.serverTimestamp,
        DateTime.fromMicrosecondsSinceEpoch(
          1700000000 * 1000000 + 500000,
          isUtc: true,
        ),
      );
      expect(message.chat, isNotNull);
      expect(message.chat!.content, 'hello');
      expect(message.chat!.rawUserId, 123456);
      expect(message.chat!.hashedUserId, 'hashed-1');
      expect(message.chat!.no, 99);
    });

    test('decodes overflowed chat payload as chat', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[
        ..._stringField(1, 'overflowed-body'),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(20, chat),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.content, 'overflowed-body');
    });

    test('decodes chunked entry backward segment and next at', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> packedSegmentNext = _bytesField(
        1,
        Uint8List.fromList(_utf8('https://example.com/backward-segment')),
      );

      final List<int> backward = <int>[
        ..._bytesField(2, packedSegmentNext),
      ];

      final List<int> next = <int>[
        ..._varintField(1, 12345),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, backward),
        ..._bytesField(4, next),
      ]);

      final NdgrChunkedEntry entry = decoder.decodeChunkedEntry(bytes);

      expect(entry.backwardSegmentUri, 'https://example.com/backward-segment');
      expect(entry.nextAt, 12345);
      expect(entry.segmentUri, isNull);
      expect(entry.previousUri, isNull);
    });

    test('decodes statistics message with viewers', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> statistics = <int>[
        ..._varintField(1, 42),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(8, statistics),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNull);
      expect(message.statistics, isNotNull);
      expect(message.statistics!.viewers, 42);
    });

    test('decodes message with both chat and statistics', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[
        ..._stringField(1, 'hello'),
      ];
      final List<int> statistics = <int>[
        ..._varintField(1, 100),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(1, chat),
        ..._bytesField(8, statistics),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.content, 'hello');
      expect(message.statistics, isNotNull);
      expect(message.statistics!.viewers, 100);
    });

    test('decodes packed segment messages and next uri', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> timestamp = <int>[
        ..._varintField(1, 1700000000),
      ];
      final List<int> meta = <int>[
        ..._stringField(1, 'm-1'),
        ..._bytesField(2, timestamp),
      ];
      final List<int> chat = <int>[
        ..._stringField(1, 'chat-body'),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(1, chat),
      ];

      final List<int> chunkedMessage = <int>[
        ..._bytesField(1, meta),
        ..._bytesField(2, nicoliveMessage),
      ];

      final List<int> packedNext = <int>[
        ..._stringField(1, 'https://example.com/next-segment'),
      ];

      final Uint8List packed = Uint8List.fromList(<int>[
        ..._bytesField(1, chunkedMessage),
        ..._bytesField(2, packedNext),
      ]);

      final NdgrPackedSegment decoded = decoder.decodePackedSegment(packed);

      expect(decoded.messages.length, 1);
      expect(decoded.messages.first.id, 'm-1');
      expect(decoded.messages.first.chat, isNotNull);
      expect(decoded.messages.first.chat!.content, 'chat-body');
      expect(decoded.nextUri, 'https://example.com/next-segment');
    });
  });

  group('NdgrLengthDelimitedDecoder', () {
    test('restores fragmented payload and counts restoration', () {
      final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

      final List<int> payload = <int>[1, 2, 3, 4, 5];
      final List<int> delimited = <int>[
        ..._encodeVarint(payload.length),
        ...payload,
      ];

      final List<Uint8List> first = decoder.add(delimited.sublist(0, 2));
      final List<Uint8List> second = decoder.add(delimited.sublist(2));

      expect(first, isEmpty);
      expect(second.length, 1);
      expect(second.first, Uint8List.fromList(payload));
      expect(decoder.fragmentRestoreCount, 1);
    });

    test('clear resets fragment restoration count', () {
      final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

      final List<int> payload = <int>[1, 2, 3];
      final List<int> delimited = <int>[
        ..._encodeVarint(payload.length),
        ...payload,
      ];

      decoder.add(delimited.sublist(0, 1));
      decoder.add(delimited.sublist(1));
      expect(decoder.fragmentRestoreCount, 1);

      decoder.clear();
      expect(decoder.fragmentRestoreCount, 0);
    });

    test('drops oversized frame length and recovers on next chunk', () {
      final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

      final List<int> oversizedPrefix = _encodeVarint(102401);
      expect(decoder.add(oversizedPrefix), isEmpty);

      final List<int> payload = <int>[7, 8, 9];
      final List<int> delimited = <int>[
        ..._encodeVarint(payload.length),
        ...payload,
      ];

      final List<Uint8List> recovered = decoder.add(delimited);
      expect(recovered.length, 1);
      expect(recovered.first, Uint8List.fromList(payload));
    });

    test('drops malformed varint prefix and recovers on next chunk', () {
      final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

      final List<int> malformedPrefix = List<int>.filled(11, 0x80);
      expect(decoder.add(malformedPrefix), isEmpty);

      final List<int> payload = <int>[1, 2];
      final List<int> delimited = <int>[
        ..._encodeVarint(payload.length),
        ...payload,
      ];

      final List<Uint8List> recovered = decoder.add(delimited);
      expect(recovered.length, 1);
      expect(recovered.first, Uint8List.fromList(payload));
    });
  });
}

List<int> _varintField(int fieldNumber, int value) {
  return <int>[
    ..._encodeVarint((fieldNumber << 3) | 0),
    ..._encodeVarint(value),
  ];
}

List<int> _bytesField(int fieldNumber, List<int> bytes) {
  return <int>[
    ..._encodeVarint((fieldNumber << 3) | 2),
    ..._encodeVarint(bytes.length),
    ...bytes,
  ];
}

List<int> _stringField(int fieldNumber, String value) {
  return _bytesField(fieldNumber, _utf8(value));
}

List<int> _encodeVarint(int value) {
  int next = value;
  final List<int> bytes = <int>[];

  while (next >= 0x80) {
    bytes.add((next & 0x7f) | 0x80);
    next >>= 7;
  }
  bytes.add(next);

  return bytes;
}

List<int> _utf8(String value) {
  return utf8.encode(value);
}
