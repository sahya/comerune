import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/connection/ndgr_message_normalizer.dart';
import '../../../lib/domain/connection/ndgr_protobuf_decoder.dart';
import '../../../lib/domain/models/app_message.dart';

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

      final NdgrChunkedMessage source = NdgrChunkedMessage(
        chat: const NdgrChat(
          content: 'content',
          hashedUserId: 'hashed-user',
          no: 77,
        ),
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
  });
}
