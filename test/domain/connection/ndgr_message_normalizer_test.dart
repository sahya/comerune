import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/ndgr_message_normalizer.dart';
import 'package:comerune/domain/connection/ndgr_protobuf_decoder.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('NdgrMessageNormalizer', () {
    test('normalizes chat with server timestamp and raw user id', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-001',
        serverTimestamp: serverTime,
        chat: const NdgrChat(
          content: 'hello',
          rawUserId: 999,
          hashedUserId: 'hashed',
          no: 10,
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: DateTime.parse('2026-03-22T09:59:00Z'),
      );

      expect(normalized, isNotNull);
      expect(normalized!.id, 'ndgr-001');
      expect(normalized.timestamp, serverTime);
      expect(normalized.userId, '999');
      expect(normalized.content, 'hello');
      expect(normalized.type, AppMessageType.chat);
    });

    test('falls back to receivedAt when server timestamp is missing', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime receivedAt = DateTime.parse('2026-03-22T11:00:00Z');

      const NdgrChunkedMessage source = NdgrChunkedMessage(
        chat: NdgrChat(content: 'content', hashedUserId: 'hashed-user', no: 77),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: receivedAt,
      );

      expect(normalized, isNotNull);
      expect(normalized!.id, 'ndgr-chat-77');
      expect(normalized.timestamp, receivedAt);
      expect(normalized.userId, 'hashed-user');
    });

    test('returns null when chunked message has no chat payload', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        const NdgrChunkedMessage(),
      );

      expect(normalized, isNull);
    });

    test('normalizes empty chat.name to null userName', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-empty-name',
        serverTimestamp: serverTime,
        chat: const NdgrChat(
          content: 'hello',
          name: '',
          rawUserId: 123,
          hashedUserId: 'hashed',
          no: 1,
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userName, isNull);
    });

    test('preserves non-empty chat.name as userName', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-with-name',
        serverTimestamp: serverTime,
        chat: const NdgrChat(
          content: 'hello',
          name: 'テスト名',
          rawUserId: 456,
          no: 2,
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userName, 'テスト名');
    });

    test('returns null when chat content is empty', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        const NdgrChunkedMessage(chat: NdgrChat(content: '')),
      );

      expect(normalized, isNull);
    });

    test('normalizes null chat.name to null userName', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-null-name',
        serverTimestamp: serverTime,
        chat: const NdgrChat(content: 'hello', rawUserId: 789, no: 3),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userName, isNull);
    });

    test('resolves userId from hashedUserId when rawUserId is absent', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-hashed-only',
        serverTimestamp: serverTime,
        chat: const NdgrChat(content: 'hello', hashedUserId: 'abc123', no: 4),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userId, 'abc123');
    });

    test(
      'returns null userId when both rawUserId and hashedUserId are absent',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          id: 'ndgr-no-user',
          serverTimestamp: serverTime,
          chat: const NdgrChat(content: 'hello', no: 5),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
          receivedAt: serverTime,
        );

        expect(normalized, isNotNull);
        expect(normalized!.userId, isNull);
      },
    );

    test('preserves whitespace-only chat.name as userName', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-whitespace-name',
        serverTimestamp: serverTime,
        chat: const NdgrChat(
          content: 'hello',
          name: '  ',
          rawUserId: 100,
          no: 7,
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      // Whitespace-only is not empty per isNotEmpty, so it passes through.
      // This documents current behavior; trimming is outside this fix scope.
      expect(normalized!.userName, '  ');
    });

    test('normalizes operator comment to AppMessageType.operator', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-op-1',
        serverTimestamp: serverTime,
        operatorComment: const NdgrOperatorComment(
          content: '運営からのお知らせ',
          name: '運営',
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.type, AppMessageType.operator);
      expect(normalized.content, '運営からのお知らせ');
      expect(normalized.userName, '運営');
      expect(normalized.userId, isNull);
      expect(normalized.id, 'ndgr-op-1');
    });

    test(
      'sanitises operator name by stripping CR/LF and control characters',
      () {
        // Broadcaster-supplied names flow through verbatim (Policy A), BUT
        // the client strips CR/LF + C0/C1 control characters so a crafted
        // label cannot inject extra lines or move other UI around. This
        // keeps printable CJK / emoji characters.
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          id: 'ndgr-op-sanitise',
          serverTimestamp: serverTime,
          operatorComment: const NdgrOperatorComment(
            content: '告知',
            name: '  運営\n\r\u0000公\u0007式  ',
          ),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
          receivedAt: serverTime,
        );

        expect(normalized, isNotNull);
        expect(
          normalized!.userName,
          '運営公式',
          reason:
              'CR/LF + C0 control characters must be stripped; '
              'surrounding whitespace trimmed; printable CJK preserved',
        );
      },
    );

    test('caps operator name length at 64 characters', () {
      // A maliciously-long operator name would otherwise expand the
      // comment row and push other UI off-screen. The normalizer caps
      // the rendered label to a conservative ceiling.
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final String longName = 'A' * 500;

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-op-longname',
        serverTimestamp: serverTime,
        operatorComment: NdgrOperatorComment(content: '告知', name: longName),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userName?.length, 64);
    });

    test(
      'caps operator name at 64 grapheme clusters without splitting surrogate pairs',
      () {
        // Regression guard for the `substring(0, 64)` → dangling surrogate
        // bug flagged in post-merge sage review: `String.length` counts
        // UTF-16 code units, so a naive substring cap at UTF-16 boundary
        // 64 would leave a lone high surrogate at position 63 when the
        // clusters around the boundary are outside the BMP.
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        // 40 × face-with-tears-of-joy (U+1F602) — each is 2 UTF-16 code
        // units, so the string has length 80 but 40 grapheme clusters.
        // With the cap at 64 grapheme clusters the input fits entirely;
        // we then prepend 25 ASCII chars so the total is 65 grapheme
        // clusters, crossing the boundary inside an emoji.
        final String heading = 'a' * 25;
        final String emojis = '\u{1F602}' * 40;
        final String crafted = heading + emojis;

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          id: 'ndgr-op-surrogate-cap',
          serverTimestamp: serverTime,
          operatorComment: NdgrOperatorComment(content: '告知', name: crafted),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
          receivedAt: serverTime,
        );

        expect(normalized, isNotNull);
        final String userName = normalized!.userName!;
        // The sanitised name must not contain a U+FFFD replacement
        // character (which would indicate a broken surrogate pair).
        expect(
          userName.contains('\uFFFD'),
          isFalse,
          reason: 'cap must not split a surrogate pair into a lone surrogate',
        );
        // All UTF-16 code units must still pair up: every high surrogate
        // must be followed by a low surrogate and vice versa.
        for (int i = 0; i < userName.length; i++) {
          final int unit = userName.codeUnitAt(i);
          final bool isHighSurrogate = unit >= 0xD800 && unit <= 0xDBFF;
          final bool isLowSurrogate = unit >= 0xDC00 && unit <= 0xDFFF;
          if (isHighSurrogate) {
            expect(
              i + 1 < userName.length,
              isTrue,
              reason: 'trailing high surrogate at offset $i',
            );
            final int next = userName.codeUnitAt(i + 1);
            expect(next >= 0xDC00 && next <= 0xDFFF, isTrue);
            i++; // skip the paired low surrogate
          } else {
            expect(
              isLowSurrogate,
              isFalse,
              reason: 'lone low surrogate at offset $i',
            );
          }
        }
      },
    );

    test(
      'operator name sanitisation removes additional invisible code points',
      () {
        // Defence-in-depth for U+2060 WORD JOINER / U+3164 HANGUL FILLER
        // / U+FFF9-FFFB (interlinear annotation) et al that were missing
        // from the initial sanitiser. Each of these can render as an
        // invisible character used for display spoofing.
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        // Interleave invisible code points with printable "運営" so we can
        // assert the visible characters survive.
        const String wordJoiner = '\u2060';
        const String invisibleTimes = '\u2062';
        const String hangulFiller = '\u3164';
        const String interlinearAnchor = '\uFFF9';
        final String craftedName =
            '運$wordJoiner営$invisibleTimes$hangulFiller$interlinearAnchor';

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          id: 'ndgr-op-invisible',
          serverTimestamp: serverTime,
          operatorComment: NdgrOperatorComment(
            content: '告知',
            name: craftedName,
          ),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
          receivedAt: serverTime,
        );

        expect(normalized, isNotNull);
        expect(normalized!.userName, '運営');
      },
    );

    test('maps operator name to null when sanitation empties it', () {
      // A name consisting only of CR/LF + whitespace sanitises down to
      // an empty string; the normalizer must surface null (not '') so
      // downstream "null = no label" logic in the renderer still works.
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-op-empty-after',
        serverTimestamp: serverTime,
        operatorComment: const NdgrOperatorComment(
          content: '告知',
          name: ' \n\r\u0000\u0007 ',
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userName, isNull);
    });

    test('prefers operator comment over chat when both are present', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-op-2',
        serverTimestamp: serverTime,
        chat: const NdgrChat(content: 'fallback chat'),
        operatorComment: const NdgrOperatorComment(content: '優先される運営'),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.type, AppMessageType.operator);
      expect(normalized.content, '優先される運営');
    });

    test('returns null for operator comment with empty content', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        const NdgrChunkedMessage(
          operatorComment: NdgrOperatorComment(content: ''),
        ),
      );

      expect(normalized, isNull);
    });

    test(
      'sanitises operator content by stripping bidi / Tag / zero-width characters',
      () {
        // Trojan Source / display-spoofing defence for operator.content:
        // the broadcaster-supplied content body is sanitised symmetrically
        // with the operator name so that invisible payloads cannot be
        // smuggled into the rendered message bubble.  Printable CJK text
        // must survive verbatim.
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        // Interleave: bidi override + NBSP + zero-width space + Tag char
        const String attack = '運営\u202E\u00A0からの\u200B\u{E0001}お知らせ';

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          id: 'ndgr-op-content-sanitise',
          serverTimestamp: serverTime,
          operatorComment: NdgrOperatorComment(content: attack, name: '運営'),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
          receivedAt: serverTime,
        );

        expect(normalized, isNotNull);
        expect(
          normalized!.content,
          '運営からのお知らせ',
          reason:
              'bidi override / NBSP / ZWSP / Tag Character must be '
              'stripped; printable CJK preserved',
        );
      },
    );

    test(
      'returns null for operator comment with content that sanitises to empty',
      () {
        // Edge case: operator.content is non-empty per isNotEmpty (passes
        // the early guard) but consists entirely of invisible characters
        // (e.g. ZWSP + bidi override).  The sanitised content becomes
        // empty, and the normalizer must drop the whole message rather
        // than emit a visibly-empty operator bubble.
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          const NdgrChunkedMessage(
            operatorComment: NdgrOperatorComment(
              // U+200B (ZWSP) + U+202E (RLO) + U+FEFF (BOM) — all
              // invisible; isNotEmpty = true before sanitisation.
              content: '\u200B\u202E\uFEFF',
            ),
          ),
        );

        expect(normalized, isNull);
      },
    );

    test('maps SimpleNotificationV2 ICHIBA to AppMessageType.system', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-ichiba-1',
        serverTimestamp: serverTime,
        simpleNotificationV2: const NdgrSimpleNotificationV2(
          type: NdgrSimpleNotificationV2Type.ichiba,
          message: '市場に商品が登録されました',
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.type, AppMessageType.system);
      expect(normalized.content, '市場に商品が登録されました');
    });

    test('maps SimpleNotificationV2 EMOTION to AppMessageType.emotion', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-emotion-1',
        serverTimestamp: serverTime,
        simpleNotificationV2: const NdgrSimpleNotificationV2(
          type: NdgrSimpleNotificationV2Type.emotion,
          message: 'エモーション: 盛り上がり',
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.type, AppMessageType.emotion);
    });

    test(
      'maps other SimpleNotificationV2 types to AppMessageType.notification',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        for (final NdgrSimpleNotificationV2Type t
            in <NdgrSimpleNotificationV2Type>[
              NdgrSimpleNotificationV2Type.programExtended,
              NdgrSimpleNotificationV2Type.rankingIn,
              NdgrSimpleNotificationV2Type.supporterRegistered,
              NdgrSimpleNotificationV2Type.userLevelUp,
              NdgrSimpleNotificationV2Type.userFollow,
              NdgrSimpleNotificationV2Type.visited,
              NdgrSimpleNotificationV2Type.cruise,
              NdgrSimpleNotificationV2Type.unknown,
            ]) {
          final NdgrChunkedMessage source = NdgrChunkedMessage(
            id: 'ndgr-notif-${t.name}',
            serverTimestamp: serverTime,
            simpleNotificationV2: NdgrSimpleNotificationV2(
              type: t,
              message: 'notification: ${t.name}',
            ),
          );
          final AppMessage? normalized = normalizer.normalizeChunkedMessage(
            source,
            receivedAt: serverTime,
          );
          expect(normalized, isNotNull, reason: t.name);
          expect(normalized!.type, AppMessageType.notification, reason: t.name);
        }
      },
    );

    test('prefers operator comment over simpleNotificationV2 when both are '
        'present', () {
      // If the chunk carries both signals, the operator comment wins:
      // broadcaster announcements outrank market/emotion notifications.
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-op-notif',
        serverTimestamp: serverTime,
        operatorComment: const NdgrOperatorComment(content: '運営本文', name: '運営'),
        simpleNotificationV2: const NdgrSimpleNotificationV2(
          type: NdgrSimpleNotificationV2Type.ichiba,
          message: '商品',
        ),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.type, AppMessageType.operator);
      expect(normalized.content, '運営本文');
      expect(normalized.userName, '運営');
    });

    test('returns null for empty SimpleNotificationV2 message', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        const NdgrChunkedMessage(
          simpleNotificationV2: NdgrSimpleNotificationV2(
            type: NdgrSimpleNotificationV2Type.ichiba,
            message: '',
          ),
        ),
      );

      expect(normalized, isNull);
    });

    test('skips empty hashedUserId and returns null userId', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        id: 'ndgr-empty-hashed',
        serverTimestamp: serverTime,
        chat: const NdgrChat(content: 'hello', hashedUserId: '', no: 6),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(
        source,
        receivedAt: serverTime,
      );

      expect(normalized, isNotNull);
      expect(normalized!.userId, isNull);
    });

    // --- Fallback id shape tests (refactor guard) ---
    //
    // These lock in the exact id shape produced by `_buildNdgrId` per
    // NDGR message variant so that the refactor (consolidating three
    // per-type `_resolve*Id` helpers into a single prefix-parameterised
    // helper) does not silently change persisted / dedup-critical ids.
    //
    // The fallback sequence counter is per-normalizer so these tests
    // construct a fresh normalizer for each case and always exercise
    // sequence value `1`.

    test('chat falls back to ndgr-chat-\${no} when source id is missing', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        serverTimestamp: serverTime,
        chat: const NdgrChat(content: 'hi', no: 77),
      );

      final AppMessage? normalized = normalizer.normalizeChunkedMessage(source);
      expect(normalized, isNotNull);
      expect(normalized!.id, 'ndgr-chat-77');
    });

    test(
      'chat falls back to ndgr-\${ts}-\${seq} when both source id and no are missing',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          chat: const NdgrChat(content: 'hi'),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
        );
        expect(normalized, isNotNull);
        expect(normalized!.id, 'ndgr-${serverTime.microsecondsSinceEpoch}-1');
      },
    );

    test(
      'operator comment falls back to ndgr-operator-\${ts}-\${seq} when source id is missing',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          operatorComment: const NdgrOperatorComment(content: '運営本文'),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
        );
        expect(normalized, isNotNull);
        expect(
          normalized!.id,
          '$kNdgrOperatorIdPrefix${serverTime.microsecondsSinceEpoch}-1',
        );
      },
    );

    test(
      'notification falls back to ndgr-notify-\${ts}-\${seq} when source id is missing',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage source = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          simpleNotificationV2: const NdgrSimpleNotificationV2(
            type: NdgrSimpleNotificationV2Type.cruise,
            message: 'cruise notice',
          ),
        );

        final AppMessage? normalized = normalizer.normalizeChunkedMessage(
          source,
        );
        expect(normalized, isNotNull);
        expect(
          normalized!.id,
          '$kNdgrNotifyIdPrefix${serverTime.microsecondsSinceEpoch}-1',
        );
      },
    );

    test(
      'fallback sequence is monotonically increasing within one normalizer',
      () {
        final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
        final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

        final NdgrChunkedMessage chatSource = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          chat: const NdgrChat(content: 'hi'),
        );
        final NdgrChunkedMessage operatorSource = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          operatorComment: const NdgrOperatorComment(content: '運営'),
        );
        final NdgrChunkedMessage notifySource = NdgrChunkedMessage(
          serverTimestamp: serverTime,
          simpleNotificationV2: const NdgrSimpleNotificationV2(
            type: NdgrSimpleNotificationV2Type.emotion,
            message: 'w',
          ),
        );

        final String id1 = normalizer.normalizeChunkedMessage(chatSource)!.id;
        final String id2 = normalizer
            .normalizeChunkedMessage(operatorSource)!
            .id;
        final String id3 = normalizer.normalizeChunkedMessage(notifySource)!.id;

        expect(id1.endsWith('-1'), isTrue, reason: 'chat fallback seq=1');
        expect(id2.endsWith('-2'), isTrue, reason: 'operator fallback seq=2');
        expect(id3.endsWith('-3'), isTrue, reason: 'notify fallback seq=3');
      },
    );

    test('source id wins over all fallbacks, across all variants', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final AppMessage chat = normalizer.normalizeChunkedMessage(
        NdgrChunkedMessage(
          id: 'upstream-chat-id',
          serverTimestamp: serverTime,
          chat: const NdgrChat(content: 'hi', no: 1),
        ),
      )!;
      final AppMessage op = normalizer.normalizeChunkedMessage(
        NdgrChunkedMessage(
          id: 'upstream-op-id',
          serverTimestamp: serverTime,
          operatorComment: const NdgrOperatorComment(content: '運営'),
        ),
      )!;
      final AppMessage notify = normalizer.normalizeChunkedMessage(
        NdgrChunkedMessage(
          id: 'upstream-notify-id',
          serverTimestamp: serverTime,
          simpleNotificationV2: const NdgrSimpleNotificationV2(
            type: NdgrSimpleNotificationV2Type.ichiba,
            message: 'm',
          ),
        ),
      )!;

      expect(chat.id, 'upstream-chat-id');
      expect(op.id, 'upstream-op-id');
      expect(notify.id, 'upstream-notify-id');
    });

    test('empty source id triggers fallback, not passthrough', () {
      final NdgrMessageNormalizer normalizer = NdgrMessageNormalizer();
      final DateTime serverTime = DateTime.parse('2026-03-22T10:00:00Z');

      final AppMessage op = normalizer.normalizeChunkedMessage(
        NdgrChunkedMessage(
          id: '',
          serverTimestamp: serverTime,
          operatorComment: const NdgrOperatorComment(content: '運営'),
        ),
      )!;

      expect(op.id.startsWith(kNdgrOperatorIdPrefix), isTrue);
      expect(op.id, isNot('')); // definitely not the empty id
    });
  });
}
