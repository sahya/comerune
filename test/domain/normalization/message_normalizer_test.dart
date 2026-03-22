import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/models/app_message.dart';
import '../../../lib/domain/normalization/message_normalizer.dart';

void main() {
  group('MessageNormalizer.normalizeLegacyJson', () {
    test('extracts chat payload into AppMessage', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        '{"chat":{"content":"hello","user_id":"user-1","timestamp":1710939600}}',
      );

      expect(message, isNotNull);
      expect(message!.id, 'legacy-1');
      expect(message.type, AppMessageType.chat);
      expect(message.content, 'hello');
      expect(message.userId, 'user-1');
      expect(
        message.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1710939600 * 1000, isUtc: true),
      );
    });

    test('returns unsupported-format message when chat key is missing', () {
      final DateTime receivedAt = DateTime.parse('2026-03-22T00:00:00Z');
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        '{"ping":"pong"}',
        receivedAt: receivedAt,
      );

      expect(message, isNotNull);
      expect(message!.type, AppMessageType.notification);
      expect(message.content, kLegacyUnsupportedFormatContent);
      expect(message.userId, isNull);
      expect(message.timestamp, receivedAt);
    });

    test('returns null when JSON parse fails', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson('{invalid-json');

      expect(message, isNull);
    });

    test('uses injected extractor implementation', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
        legacyChatExtractor: const _InjectedExtractor(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson('{"other":true}');

      expect(message, isNotNull);
      expect(message!.type, AppMessageType.chat);
      expect(message.content, 'from-injected-extractor');
      expect(message.userId, 'injected-user');
      expect(message.timestamp, DateTime.parse('2026-03-22T12:34:56Z'));
    });
  });
}

LegacyMessageIdGenerator _sequentialIdGenerator() {
  int sequence = 1;
  return () {
    final String id = 'legacy-$sequence';
    sequence += 1;
    return id;
  };
}

class _InjectedExtractor implements LegacyChatExtractor {
  const _InjectedExtractor();

  @override
  LegacyChatExtraction? extract(
    Map<String, Object?> payload, {
    required DateTime receivedAt,
  }) {
    return LegacyChatExtraction(
      content: 'from-injected-extractor',
      userId: 'injected-user',
      timestamp: DateTime.parse('2026-03-22T12:34:56Z'),
    );
  }
}
