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

      final List<int> nicoliveMessage = <int>[..._bytesField(1, chat)];

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

      final List<int> chat = <int>[..._stringField(1, 'overflowed-body')];
      final List<int> nicoliveMessage = <int>[..._bytesField(20, chat)];

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

      final List<int> backward = <int>[..._bytesField(2, packedSegmentNext)];

      final List<int> next = <int>[..._varintField(1, 12345)];

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

      final List<int> statistics = <int>[..._varintField(1, 42)];
      final List<int> nicoliveMessage = <int>[..._bytesField(8, statistics)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNull);
      expect(message.statistics, isNotNull);
      expect(message.statistics!.viewers, 42);
    });

    test('normalizes empty chat.name to null at decode level', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[
        ..._stringField(1, 'hello'),
        ..._stringField(2, ''),
        ..._varintField(5, 100),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(1, chat)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.name, isNull);
    });

    test('normalizes empty hashedUserId to null at decode level', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[
        ..._stringField(1, 'hello'),
        ..._stringField(6, ''),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(1, chat)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.hashedUserId, isNull);
    });

    test('preserves non-empty chat.name at decode level', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[
        ..._stringField(1, 'hello'),
        ..._stringField(2, 'ユーザー名'),
        ..._varintField(5, 200),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(1, chat)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.name, 'ユーザー名');
    });

    test('decodes message with both chat and statistics', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[..._stringField(1, 'hello')];
      final List<int> statistics = <int>[..._varintField(1, 100)];
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

    test('decodes operator comment from ChunkedMessage.state.marquee', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // OperatorComment: content(1), name(2)
      final List<int> operatorComment = <int>[
        ..._stringField(1, '運営コメント本文'),
        ..._stringField(2, '配信者'),
      ];
      // Marquee.Display: operator_comment(1)
      final List<int> display = <int>[..._bytesField(1, operatorComment)];
      // Marquee: display(1)
      final List<int> marquee = <int>[..._bytesField(1, display)];
      // NicoliveState: marquee(4)
      final List<int> state = <int>[..._bytesField(4, marquee)];
      // ChunkedMessage: state(4)
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.operatorComment, isNotNull);
      expect(message.operatorComment!.content, '運営コメント本文');
      expect(message.operatorComment!.name, '配信者');
      expect(message.chat, isNull);
    });

    test('ignores operator marquee without display payload', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Empty marquee message (no display).
      final List<int> marquee = <int>[];
      final List<int> state = <int>[..._bytesField(4, marquee)];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.operatorComment, isNull);
    });

    test(
      'decodes SimpleNotificationV2 ICHIBA from NicoliveMessage field 23',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        final List<int> notification = <int>[
          ..._varintField(1, 1), // ICHIBA
          ..._stringField(2, '商品登録'),
        ];
        final List<int> nicoliveMessage = <int>[
          ..._bytesField(23, notification),
        ];
        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.simpleNotificationV2, isNotNull);
        expect(
          message.simpleNotificationV2!.type,
          NdgrSimpleNotificationV2Type.ichiba,
        );
        expect(message.simpleNotificationV2!.message, '商品登録');
      },
    );

    test(
      'decodes SimpleNotificationV2 EMOTION from NicoliveMessage field 23',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        final List<int> notification = <int>[
          ..._varintField(1, 2), // EMOTION
          ..._stringField(2, 'エモーション'),
        ];
        final List<int> nicoliveMessage = <int>[
          ..._bytesField(23, notification),
        ];
        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(
          message.simpleNotificationV2!.type,
          NdgrSimpleNotificationV2Type.emotion,
        );
      },
    );

    test(
      'falls back to unknown type for unrecognised NotificationType enum',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Use enum value 99 (not defined in schema).
        final List<int> notification = <int>[
          ..._varintField(1, 99),
          ..._stringField(2, '未知種別'),
        ];
        final List<int> nicoliveMessage = <int>[
          ..._bytesField(23, notification),
        ];
        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(
          message.simpleNotificationV2!.type,
          NdgrSimpleNotificationV2Type.unknown,
        );
        expect(message.simpleNotificationV2!.message, '未知種別');
      },
    );

    test('falls back to unknown type for NotificationType raw=0 (UNKNOWN)', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Explicit raw=0 exercises the `case 0:` path of the enum mapper.
      final List<int> notification = <int>[
        ..._varintField(1, 0),
        ..._stringField(2, '未知'),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(23, notification)];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(
        message.simpleNotificationV2!.type,
        NdgrSimpleNotificationV2Type.unknown,
      );
      expect(message.simpleNotificationV2!.message, '未知');
    });

    test(
      'decodes operator comment and simpleNotificationV2 from the same chunk',
      () {
        // Both signals coexist on the wire. The decoder must not drop either.
        // Priority between them is the normalizer's concern (see
        // ndgr_message_normalizer_test.dart).
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // OperatorComment → NicoliveState.marquee.display.
        final List<int> operatorComment = <int>[
          ..._stringField(1, '運営'),
          ..._stringField(2, '配信者'),
        ];
        final List<int> display = <int>[..._bytesField(1, operatorComment)];
        final List<int> marquee = <int>[..._bytesField(1, display)];
        final List<int> state = <int>[..._bytesField(4, marquee)];

        // SimpleNotificationV2 → NicoliveMessage field 23.
        final List<int> notification = <int>[
          ..._varintField(1, 2), // EMOTION
          ..._stringField(2, 'エモ'),
        ];
        final List<int> nicoliveMessage = <int>[
          ..._bytesField(23, notification),
        ];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.operatorComment, isNotNull);
        expect(message.operatorComment!.content, '運営');
        expect(message.simpleNotificationV2, isNotNull);
        expect(
          message.simpleNotificationV2!.type,
          NdgrSimpleNotificationV2Type.emotion,
        );
        expect(message.simpleNotificationV2!.message, 'エモ');
      },
    );

    test(
      'malformed operator state bytes do not drop valid simpleNotificationV2',
      () {
        // Inverse failure test: when the NicoliveState (field 4) payload is
        // malformed, the decoder must still surface the valid
        // simpleNotificationV2 carried in NicoliveMessage (field 2) of the
        // SAME chunk. Regression guard: before the isolation, an exception
        // in state parsing aborted the whole chunk decode and dropped the
        // notification.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // A deliberately malformed NicoliveState payload: the outer bytes
        // encode a lengthDelimited tag whose declared length overruns the
        // buffer, forcing readLengthDelimited() to throw.
        final List<int> malformedState = <int>[
          // Tag for field 4 (marquee), wire type 2 (length-delimited).
          (4 << 3) | 2,
          // Declared length 0x7F (127) but payload contains only 1 byte ->
          // EOF when the reader tries to consume it.
          0x7F,
          0x00,
        ];

        // Valid SimpleNotificationV2 → NicoliveMessage field 23.
        final List<int> notification = <int>[
          ..._varintField(1, 1), // ICHIBA
          ..._stringField(2, '商品登録'),
        ];
        final List<int> nicoliveMessage = <int>[
          ..._bytesField(23, notification),
        ];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
          ..._bytesField(4, malformedState),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        // Operator comment is dropped (null) because the state was malformed.
        expect(message.operatorComment, isNull);
        // But the valid notification from the same chunk must survive.
        expect(message.simpleNotificationV2, isNotNull);
        expect(
          message.simpleNotificationV2!.type,
          NdgrSimpleNotificationV2Type.ichiba,
        );
        expect(message.simpleNotificationV2!.message, '商品登録');
      },
    );

    // --- _readSingleFieldLD consolidation guard ---
    //
    // The refactor replaced three hand-rolled "scan for one nested
    // length-delimited field" loops with a shared helper. These tests
    // exercise each wrapper layer of the Marquee chain with interleaved
    // sibling fields and with the target field absent, so that a
    // regression in the helper would surface here instead of in one of
    // the wrapper sites.

    test(
      'operator comment decoder skips unknown sibling fields in every wrapper layer',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // OperatorComment: content(1), name(2), link(4)
        final List<int> operatorComment = <int>[
          ..._stringField(1, 'body'),
          ..._stringField(2, 'name'),
        ];
        // Marquee.Display: sibling varint field 99 before operator_comment(1)
        final List<int> display = <int>[
          ..._varintField(99, 12345),
          ..._bytesField(1, operatorComment),
        ];
        // Marquee: sibling string field 7 before display(1)
        final List<int> marquee = <int>[
          ..._stringField(7, 'sibling'),
          ..._bytesField(1, display),
        ];
        // NicoliveState: sibling varint field 2 before marquee(4)
        final List<int> state = <int>[
          ..._varintField(2, 1),
          ..._bytesField(4, marquee),
        ];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.operatorComment, isNotNull);
        expect(message.operatorComment!.content, 'body');
        expect(message.operatorComment!.name, 'name');
      },
    );

    test(
      'operator comment decoder returns null when Marquee.display is absent',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Marquee with only sibling fields, no display(1).
        final List<int> marquee = <int>[..._varintField(5, 1)];
        final List<int> state = <int>[..._bytesField(4, marquee)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.operatorComment, isNull);
      },
    );

    test(
      'operator comment decoder returns null when NicoliveState.marquee is absent',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // NicoliveState with only sibling fields, no marquee(4).
        final List<int> state = <int>[..._varintField(1, 9)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.operatorComment, isNull);
      },
    );

    test('decodes backward segment uri with interleaved sibling fields', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // PackedSegmentNext-like wrapper: field 1 (string).
      final List<int> packedSegmentNext = _stringField(
        1,
        'https://example.com/backward-sibling',
      );
      // BackwardSegment: sibling varint field 5 before segment(2).
      final List<int> backward = <int>[
        ..._varintField(5, 7),
        ..._bytesField(2, packedSegmentNext),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, backward),
      ]);

      final NdgrChunkedEntry entry = decoder.decodeChunkedEntry(bytes);

      expect(entry.backwardSegmentUri, 'https://example.com/backward-sibling');
    });

    test('decodes packed segment messages and next uri', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> timestamp = <int>[..._varintField(1, 1700000000)];
      final List<int> meta = <int>[
        ..._stringField(1, 'm-1'),
        ..._bytesField(2, timestamp),
      ];
      final List<int> chat = <int>[..._stringField(1, 'chat-body')];
      final List<int> nicoliveMessage = <int>[..._bytesField(1, chat)];

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
