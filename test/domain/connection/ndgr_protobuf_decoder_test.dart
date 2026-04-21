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

    test('decodes NicoliveMessage.gift (field 8) as Gift, not Statistics', () {
      // Regression guard: prior revisions wrongly routed field 8 to
      // `_decodeStatistics`. The upstream proto defines
      // `NicoliveMessage.gift = 8` (atoms.proto `message Gift`) — every
      // gift event was invisible and every gift payload spuriously
      // emitted a null-viewer Statistics event. This test pins the fix.
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Gift: advertiser_name(3), point(4), item_name(6)
      final List<int> gift = <int>[
        ..._stringField(3, 'たろう'),
        ..._varintField(4, 500),
        ..._stringField(6, 'こんぺいとう'),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(8, gift)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNull);
      expect(
        message.statistics,
        isNull,
        reason: 'field 8 must no longer populate Statistics',
      );
      expect(message.gift, isNotNull);
      expect(message.gift!.itemName, 'こんぺいとう');
      expect(message.gift!.advertiserName, 'たろう');
      expect(message.gift!.point, 500);
    });

    test(
      'Gift falls back to item_id (field 1) when item_name (field 6) is empty',
      () {
        // Defence against server variants that omit the localised
        // `item_name` and only ship the stable `item_id`: we previously
        // returned null and silently dropped the gift.  Now the decoder
        // falls back so the user still sees something.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Gift: item_id(1) + advertiser_name(3) + point(4), no item_name(6)
        final List<int> gift = <int>[
          ..._stringField(1, 'konpeito_small'),
          ..._stringField(3, 'たろう'),
          ..._varintField(4, 500),
        ];
        final List<int> nicoliveMessage = <int>[..._bytesField(8, gift)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.gift, isNotNull);
        expect(message.gift!.itemName, 'konpeito_small');
        expect(message.gift!.advertiserName, 'たろう');
        expect(message.gift!.point, 500);
      },
    );

    test('Gift returns null when both item_name and item_id and advertiser '
        'are empty', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Gift with only point(4) — no identifying label at all.
      final List<int> gift = <int>[..._varintField(4, 1)];
      final List<int> nicoliveMessage = <int>[..._bytesField(8, gift)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.gift, isNull);
    });

    test(
      'decodes NicoliveMessage.forwarded_chat (field 22) with FROM_CRUISE mode',
      () {
        // ForwardedChat is the path ニコ生クルーズ visitor comments actually
        // travel through.  Before this change field 22 was skipped via
        // default `skipField`, so cruise visitor comments were invisible.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Inner Chat: content(1), name(2), raw_user_id(5), no(8)
        final List<int> innerChat = <int>[
          ..._stringField(1, 'クルーズから来ました'),
          ..._stringField(2, 'クルーズ太郎'),
          ..._varintField(5, 777),
          ..._varintField(8, 42),
        ];
        // ForwardedChat: chat(1) + message_id(2) + source_live_id(3) + mode(4)
        final List<int> forwarded = <int>[
          ..._bytesField(1, innerChat),
          ..._stringField(2, 'msg-abc-123'),
          ..._varintField(3, 111222),
          ..._varintField(4, 1), // FROM_CRUISE
        ];
        final List<int> nicoliveMessage = <int>[..._bytesField(22, forwarded)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.forwardedChat, isNotNull);
        expect(message.forwardedChat!.chat.content, 'クルーズから来ました');
        expect(message.forwardedChat!.chat.name, 'クルーズ太郎');
        expect(message.forwardedChat!.chat.rawUserId, 777);
        expect(message.forwardedChat!.chat.no, 42);
        expect(message.forwardedChat!.messageId, 'msg-abc-123');
        expect(message.forwardedChat!.sourceLiveId, 111222);
        expect(message.forwardedChat!.mode, NdgrForwardingMode.fromCruise);
      },
    );

    test(
      'decodes NicoliveMessage.forwarded_chat (field 22) with COLLAB_SHARING '
      'mode',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        final List<int> innerChat = <int>[..._stringField(1, 'コラボからの一言')];
        final List<int> forwarded = <int>[
          ..._bytesField(1, innerChat),
          ..._varintField(4, 2), // COLLAB_SHARING
        ];
        final List<int> nicoliveMessage = <int>[..._bytesField(22, forwarded)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.forwardedChat, isNotNull);
        expect(message.forwardedChat!.mode, NdgrForwardingMode.collabSharing);
      },
    );

    test('forwarded_chat returns null when inner Chat body is empty', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Inner Chat with empty content (no field 1) — not displayable.
      final List<int> innerChat = <int>[..._stringField(2, 'だれか')];
      final List<int> forwarded = <int>[
        ..._bytesField(1, innerChat),
        ..._varintField(4, 1),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(22, forwarded)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.forwardedChat, isNull);
    });

    test('decodes NicoliveMessage.nicoad (field 9) V1 variant', () {
      // Field 9 was not handled at all before this change; every
      // ニコニ広告 event was silently skipped by the default branch.
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Nicoad.V1: total_ad_point(1), message(2)
      final List<int> v1 = <int>[
        ..._varintField(1, 5000),
        ..._stringField(2, '広告主さんが1000ポイントの広告をしました'),
      ];
      // Nicoad.versions oneof: v1 = 2
      final List<int> nicoad = <int>[..._bytesField(2, v1)];
      final List<int> nicoliveMessage = <int>[..._bytesField(9, nicoad)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.nicoad, isNotNull);
      expect(message.nicoad!.message, '広告主さんが1000ポイントの広告をしました');
      expect(message.nicoad!.totalPoint, 5000);
    });

    test('decodes NicoliveMessage.nicoad (field 9) V0 variant via Latest', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Nicoad.V0.Latest: advertiser(1), point(2), message(3)
      final List<int> latest = <int>[
        ..._stringField(1, 'たろう'),
        ..._varintField(2, 1000),
        ..._stringField(3, 'たろうさんが1000ptニコニ広告をしました'),
      ];
      // Nicoad.V0: latest(1), total_point(3)
      final List<int> v0 = <int>[
        ..._bytesField(1, latest),
        ..._varintField(3, 3000),
      ];
      // Nicoad.versions oneof: v0 = 1
      final List<int> nicoad = <int>[..._bytesField(1, v0)];
      final List<int> nicoliveMessage = <int>[..._bytesField(9, nicoad)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.nicoad, isNotNull);
      expect(message.nicoad!.message, 'たろうさんが1000ptニコニ広告をしました');
      expect(message.nicoad!.advertiser, 'たろう');
      expect(message.nicoad!.totalPoint, 3000);
    });

    test(
      'decodes NicoliveMessage.nicoad (field 9) V0 with missing Latest.message '
      'synthesises body from advertiser + point',
      () {
        // The V0 Latest.message field is `optional`; real payloads do omit
        // it. In that case the decoder synthesises a display body from the
        // remaining fields so the ニコニ広告 event is still visible.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Nicoad.V0.Latest: advertiser(1) + point(2) only (no message).
        final List<int> latest = <int>[
          ..._stringField(1, 'たろう'),
          ..._varintField(2, 500),
        ];
        final List<int> v0 = <int>[..._bytesField(1, latest)];
        final List<int> nicoad = <int>[..._bytesField(1, v0)];
        final List<int> nicoliveMessage = <int>[..._bytesField(9, nicoad)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.nicoad, isNotNull);
        expect(message.nicoad!.message, 'たろうさんが500ptニコニ広告しました');
        expect(message.nicoad!.advertiser, 'たろう');
      },
    );

    test('decodes NicoliveMessage.nicoad (field 9) V0 caps adversarial '
        'advertiser length in the synthesised body', () {
      // Defence-in-depth: a multi-megabyte advertiser string must not
      // balloon AppMessage.content. The decoder caps the advertiser at
      // 64 grapheme clusters when synthesising a V0 fallback body.
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final String hugeAdvertiser = 'あ' * 5000;
      final List<int> latest = <int>[
        ..._stringField(1, hugeAdvertiser),
        ..._varintField(2, 1),
      ];
      final List<int> v0 = <int>[..._bytesField(1, latest)];
      final List<int> nicoad = <int>[..._bytesField(1, v0)];
      final List<int> nicoliveMessage = <int>[..._bytesField(9, nicoad)];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.nicoad, isNotNull);
      final int bodyBytes = message.nicoad!.message.length;
      // The capped advertiser is 64 code units ('あ' is BMP, 1 UTF-16
      // code unit each) plus the fixed "さんが${point}ptニコニ広告しました"
      // suffix (20 code units for point=1). Assert a generous upper
      // bound well below the original 5,000-char advertiser.
      expect(
        bodyBytes,
        lessThan(200),
        reason: 'V0 advertiser must be length-capped before synthesis',
      );
      // And specifically: advertiser prefix length (64) is enforced.
      expect(message.nicoad!.advertiser!.length, 64);
    });

    test(
      'decodes NicoliveMessage.nicoad (field 9) with both V0 and V1 payloads '
      'prefers V1',
      () {
        // Upstream proto marks Nicoad.versions as a oneof; in practice the
        // upstream is expected to emit only one at a time. A lenient
        // decoder still handles the paranoid "both present" case and
        // prefers the newer (V1) representation because that's what the
        // docstring on [NdgrNicoad] promises.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // V0 Latest with message (would decode successfully on its own).
        final List<int> latest = <int>[
          ..._stringField(1, 'たろう'),
          ..._varintField(2, 100),
          ..._stringField(3, 'V0 message'),
        ];
        final List<int> v0 = <int>[..._bytesField(1, latest)];

        // V1 with its own message.
        final List<int> v1 = <int>[
          ..._varintField(1, 2000),
          ..._stringField(2, 'V1 message'),
        ];

        // Nicoad: both v0 (field 1) and v1 (field 2) present.
        final List<int> nicoad = <int>[
          ..._bytesField(1, v0),
          ..._bytesField(2, v1),
        ];
        final List<int> nicoliveMessage = <int>[..._bytesField(9, nicoad)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.nicoad, isNotNull);
        expect(
          message.nicoad!.message,
          'V1 message',
          reason: 'V1 wins when both payloads coexist',
        );
        expect(message.nicoad!.totalPoint, 2000);
      },
    );

    test('decodes NicoliveMessage.simple_notification (field 7) v1 cruise', () {
      // Retained fallback for servers still emitting ニコ生クルーズ via the
      // legacy v1 SimpleNotification oneof (cruise = field 4).
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> simpleNotification = <int>[
        ..._stringField(4, 'ニコ生クルーズが到着しました'),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(7, simpleNotification),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.simpleNotification, isNotNull);
      expect(
        message.simpleNotification!.type,
        NdgrSimpleNotificationV1Type.cruise,
      );
      expect(message.simpleNotification!.message, 'ニコ生クルーズが到着しました');
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

    test('decodes message with both chat and gift (field 8 is Gift)', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> chat = <int>[..._stringField(1, 'hello')];
      // Gift: advertiser_name(3), item_name(6)
      final List<int> gift = <int>[
        ..._stringField(3, 'たろう'),
        ..._stringField(6, 'こんぺいとう'),
      ];
      final List<int> nicoliveMessage = <int>[
        ..._bytesField(1, chat),
        ..._bytesField(8, gift),
      ];

      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.chat, isNotNull);
      expect(message.chat!.content, 'hello');
      expect(message.gift, isNotNull);
      expect(message.gift!.itemName, 'こんぺいとう');
      expect(message.gift!.advertiserName, 'たろう');
      expect(
        message.statistics,
        isNull,
        reason:
            'field 8 is Gift, not Statistics; statistics must not be '
            'populated from NicoliveMessage',
      );
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

    test('falls back to unknown type and does NOT throw when '
        'NotificationType raw is outside the known range (Issue #478)', () {
      // The debug-build-only `assert(() { ... return true; }())` in
      // `_simpleNotificationV2TypeFromInt` logs a `debugPrint` warning
      // for drift but must NOT throw — throwing would tear down the
      // streaming decode pipeline for any contributor running a debug
      // build against a live server the moment upstream ships a new
      // NotificationType. Release builds strip the assert entirely.
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // Use enum value 99 (beyond current known max = 9).
      final List<int> notification = <int>[
        ..._varintField(1, 99),
        ..._stringField(2, '未知種別'),
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
      expect(message.simpleNotificationV2!.message, '未知種別');
    });

    test('NotificationType raw=9 (USER_FOLLOW) maps to userFollow — upper '
        'boundary of known range (Issue #478)', () {
      // Locks down the case 9 branch so a one-off in the switch
      // (e.g. accidentally dropping the USER_FOLLOW case when
      // extending the enum for drift) would fail fast in CI.
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> notification = <int>[
        ..._varintField(1, 9),
        ..._stringField(2, 'フォロー'),
      ];
      final List<int> nicoliveMessage = <int>[..._bytesField(23, notification)];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(2, nicoliveMessage),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(
        message.simpleNotificationV2!.type,
        NdgrSimpleNotificationV2Type.userFollow,
      );
    });

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

    test(
      'malformed NicoliveMessage does not drop a valid operator comment in the same chunk',
      () {
        // Symmetry check for the case 2 try/catch isolation: when the
        // NicoliveMessage (field 2) payload is malformed, the decoder must
        // still surface the valid operator comment carried in
        // NicoliveState (field 4) of the SAME chunk.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        final List<int> malformedMessage = <int>[
          // Tag for field 1 (chat), wire type 2 (length-delimited).
          (1 << 3) | 2,
          // Declared length 0x7F (127) but payload contains only 1 byte ->
          // EOF when the reader tries to consume it.
          0x7F,
          0x00,
        ];

        final List<int> operatorComment = <int>[
          ..._stringField(1, '運営本文'),
          ..._stringField(2, '運営'),
        ];
        final List<int> marqueeDisplay = <int>[
          ..._bytesField(1, operatorComment),
        ];
        final List<int> marquee = <int>[..._bytesField(1, marqueeDisplay)];
        final List<int> state = <int>[..._bytesField(4, marquee)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, malformedMessage),
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        // Chat / statistics / simpleNotificationV2 are dropped because the
        // NicoliveMessage decode failed.
        expect(message.chat, isNull);
        expect(message.statistics, isNull);
        expect(message.simpleNotificationV2, isNull);
        // But the valid operator comment from the same chunk must survive.
        expect(message.operatorComment, isNotNull);
        expect(message.operatorComment!.content, '運営本文');
      },
    );

    group('NicoliveMessage.statistics regression (Issue #461 follow-up)', () {
      test('field 8 Gift coexists with a NicoliveState payload without '
          'populating Statistics', () {
        // Pre-fix behaviour: field 8 on NicoliveMessage was wrongly
        // decoded as Statistics, which also meant every Gift event
        // spuriously emitted a null-viewer Statistics event. After the
        // fix, field 8 is correctly interpreted as Gift; Statistics must
        // come from NicoliveState (Issue #461 — not wired yet) and the
        // coexistence of a state payload must not upset the gift decode.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Gift: item_name(6) only — minimal payload.
        final List<int> gift = <int>[..._stringField(6, 'こんぺいとう')];
        final List<int> nicoliveMessage = <int>[..._bytesField(8, gift)];

        // Arbitrary NicoliveState payload carrying only a marquee so
        // the state decoder has real work to do.
        final List<int> operatorComment = <int>[..._stringField(1, '運営')];
        final List<int> display = <int>[..._bytesField(1, operatorComment)];
        final List<int> marquee = <int>[..._bytesField(1, display)];
        final List<int> state = <int>[..._bytesField(4, marquee)];

        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(2, nicoliveMessage),
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(
          message.statistics,
          isNull,
          reason:
              'Statistics is not delivered on NicoliveMessage; '
              'waiting on Issue #461 to wire the NicoliveState path',
        );
        expect(message.gift, isNotNull);
        expect(message.gift!.itemName, 'こんぺいとう');
        expect(message.operatorComment, isNotNull);
      });
    });

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
      'one malformed ChunkedMessage in a packed segment does not drop the others',
      () {
        // The PackedSegment loop must isolate per-message failures so a
        // single bad entry does not silently discard the remaining valid
        // messages in the batch.
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        // Build a valid chunked message with id "ok-1".
        final List<int> validMeta = <int>[..._stringField(1, 'ok-1')];
        final List<int> validChat = <int>[..._stringField(1, 'hello')];
        final List<int> validMessage = <int>[..._bytesField(1, validChat)];
        final List<int> validChunk = <int>[
          ..._bytesField(1, validMeta),
          ..._bytesField(2, validMessage),
        ];

        // Build a malformed chunked message: declares a length-delimited
        // meta field that overruns the payload.
        final List<int> malformedChunk = <int>[
          (1 << 3) | 2, // field 1 (meta), wire type 2
          0x7F, // declared length 127
          0x00, // only 1 byte actually present
        ];

        // Build a second valid chunked message with id "ok-2" so we can
        // assert that messages BEFORE and AFTER the malformed one survive.
        final List<int> validMeta2 = <int>[..._stringField(1, 'ok-2')];
        final List<int> validChat2 = <int>[..._stringField(1, 'bye')];
        final List<int> validMessage2 = <int>[..._bytesField(1, validChat2)];
        final List<int> validChunk2 = <int>[
          ..._bytesField(1, validMeta2),
          ..._bytesField(2, validMessage2),
        ];

        final Uint8List packed = Uint8List.fromList(<int>[
          ..._bytesField(1, validChunk),
          ..._bytesField(1, malformedChunk),
          ..._bytesField(1, validChunk2),
        ]);

        final NdgrPackedSegment decoded = decoder.decodePackedSegment(packed);

        // The two valid chunks survive; the malformed one is silently
        // dropped so downstream code never sees partial / corrupt state.
        expect(decoded.messages.length, 2);
        expect(decoded.messages[0].id, 'ok-1');
        expect(decoded.messages[1].id, 'ok-2');
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

    test('decodes ProgramStatus.Ended from NicoliveState.program_status', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // ProgramStatus: state(1) = Ended (1)
      final List<int> programStatus = <int>[..._varintField(1, 1)];
      // NicoliveState: program_status(9)
      final List<int> state = <int>[..._bytesField(9, programStatus)];
      // ChunkedMessage: state(4)
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.programStatus, NdgrProgramStatus.ended);
      expect(message.operatorComment, isNull);
      expect(message.chat, isNull);
    });

    test('decodes ProgramStatus.Unknown (0) as unknown', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // ProgramStatus: state(1) = Unknown (0)
      final List<int> programStatus = <int>[..._varintField(1, 0)];
      final List<int> state = <int>[..._bytesField(9, programStatus)];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.programStatus, NdgrProgramStatus.unknown);
    });

    test('programStatus is null when NicoliveState has no program_status', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      // NicoliveState with only marquee(4), no program_status(9).
      final List<int> operatorComment = <int>[..._stringField(1, 'test')];
      final List<int> display = <int>[..._bytesField(1, operatorComment)];
      final List<int> marquee = <int>[..._bytesField(1, display)];
      final List<int> state = <int>[..._bytesField(4, marquee)];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.programStatus, isNull);
      expect(message.operatorComment, isNotNull);
    });

    test(
      'decodes both operator comment and ProgramStatus from same NicoliveState',
      () {
        final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

        final List<int> operatorComment = <int>[..._stringField(1, '終了のお知らせ')];
        final List<int> display = <int>[..._bytesField(1, operatorComment)];
        final List<int> marquee = <int>[..._bytesField(1, display)];
        // ProgramStatus: state(1) = Ended (1)
        final List<int> programStatus = <int>[..._varintField(1, 1)];
        // NicoliveState: marquee(4) + program_status(9)
        final List<int> state = <int>[
          ..._bytesField(4, marquee),
          ..._bytesField(9, programStatus),
        ];
        final Uint8List bytes = Uint8List.fromList(<int>[
          ..._bytesField(4, state),
        ]);

        final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

        expect(message.programStatus, NdgrProgramStatus.ended);
        expect(message.operatorComment, isNotNull);
        expect(message.operatorComment!.content, '終了のお知らせ');
      },
    );

    test('malformed ProgramStatus does not drop operator comment', () {
      final NdgrProtobufDecoder decoder = NdgrProtobufDecoder();

      final List<int> operatorComment = <int>[..._stringField(1, '有効なコメント')];
      final List<int> display = <int>[..._bytesField(1, operatorComment)];
      final List<int> marquee = <int>[..._bytesField(1, display)];
      // Malformed ProgramStatus: truncated varint
      final List<int> malformedProgramStatus = <int>[0x80];
      final List<int> state = <int>[
        ..._bytesField(4, marquee),
        ..._bytesField(9, malformedProgramStatus),
      ];
      final Uint8List bytes = Uint8List.fromList(<int>[
        ..._bytesField(4, state),
      ]);

      final NdgrChunkedMessage message = decoder.decodeChunkedMessage(bytes);

      expect(message.operatorComment, isNotNull);
      expect(message.operatorComment!.content, '有効なコメント');
      expect(message.programStatus, isNull);
    });

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

  group('NdgrProtobufDecoder.capGraphemes', () {
    test('returns input unchanged when shorter than cap', () {
      expect(NdgrProtobufDecoder.capGraphemesForTest('たろう', 64), 'たろう');
    });

    test('returns input unchanged when exactly at cap', () {
      final String value = 'あ' * 64;
      expect(NdgrProtobufDecoder.capGraphemesForTest(value, 64), value);
    });

    test(
      'truncates at grapheme cluster boundary without splitting surrogates',
      () {
        // 1 face-with-tears-of-joy emoji = 1 grapheme = 2 UTF-16 code units.
        // 40 emoji = 40 graphemes = 80 code units. Prefixed with 25 ASCII
        // chars so the total is 65 graphemes, crossing the cap inside the
        // emoji region.
        final String heading = 'a' * 25;
        final String emojis = '\u{1F602}' * 40;
        final String crafted = heading + emojis;

        final String capped = NdgrProtobufDecoder.capGraphemesForTest(
          crafted,
          64,
        );

        // Must not contain U+FFFD (broken-surrogate replacement character).
        expect(
          capped.contains('�'),
          isFalse,
          reason: 'cap must not split a surrogate pair into a lone surrogate',
        );
        // Every high surrogate must still be followed by a low surrogate.
        for (int i = 0; i < capped.length; i++) {
          final int unit = capped.codeUnitAt(i);
          final bool isHigh = unit >= 0xD800 && unit <= 0xDBFF;
          final bool isLow = unit >= 0xDC00 && unit <= 0xDFFF;
          if (isHigh) {
            expect(i + 1 < capped.length, isTrue);
            final int next = capped.codeUnitAt(i + 1);
            expect(next >= 0xDC00 && next <= 0xDFFF, isTrue);
            i++;
          } else {
            expect(isLow, isFalse, reason: 'lone low surrogate at offset $i');
          }
        }
      },
    );

    test('preserves ZWJ-composed emoji family at cluster boundary', () {
      // Family emoji = man + ZWJ + woman + ZWJ + girl.  Single grapheme
      // cluster across 8 UTF-16 code units. Must survive as a unit when
      // inside the kept prefix.
      const String family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
      final String value = 'A' * 63 + family;
      // 63 ASCII + 1 family = 64 graphemes total; within cap — expect
      // unchanged.
      expect(NdgrProtobufDecoder.capGraphemesForTest(value, 64), value);
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
