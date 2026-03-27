import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/normalization/message_normalizer.dart';

void main() {
  group('sanitizeLegacyPayloadForLog', () {
    test('masks sensitive keys including auth and credential', () {
      final String sanitized = sanitizeLegacyPayloadForLog(
        _legacyFixture('log_sensitive_payload.json'),
      );

      expect(sanitized, contains('"auth":"***"'));
      expect(sanitized, contains('"credential":"***"'));
      expect(sanitized, contains('"token":"***"'));
      expect(sanitized, contains('"safe":"ok"'));
    });

    test('sanitizes nested url and truncates long strings', () {
      final String sanitized = sanitizeLegacyPayloadForLog(
        _legacyFixture('log_nested_payload.json'),
      );

      expect(sanitized, contains('"url":"https://example.com/path"'));
      expect(sanitized, contains('"message":"${'a' * 40}..."'));
    });

    test('falls back when payload is not json', () {
      final String sanitized = sanitizeLegacyPayloadForLog(
        _legacyFixture('log_non_json_url.txt'),
      );

      expect(sanitized, 'wss://legacy.example/ws');
    });
  });

  group('MessageNormalizer.normalizeLegacyJson', () {
    test('extracts chat payload into AppMessage', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        _legacyFixture('chat_message.json'),
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
      expect(isLegacyUnsupportedFormatMessage(message), isFalse);
    });

    test('returns unsupported-format message when chat key is missing', () {
      final DateTime receivedAt = DateTime.parse('2026-03-22T00:00:00Z');
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        _legacyFixture('unsupported_ping.json'),
        receivedAt: receivedAt,
      );

      expect(message, isNotNull);
      expect(message!.type, AppMessageType.notification);
      expect(message.content, kLegacyUnsupportedFormatContent);
      expect(message.userId, isNull);
      expect(message.timestamp, receivedAt);
      expect(isLegacyUnsupportedFormatMessage(message), isTrue);
    });

    test('does not classify user notification with same content as unsupported',
        () {
      final AppMessage message = AppMessage(
        id: 'manual-1',
        timestamp: DateTime.parse('2026-03-22T00:00:00Z'),
        userId: 'user-1',
        content: kLegacyUnsupportedFormatContent,
        type: AppMessageType.notification,
        raw: <String, Object?>{'payload': 'manual'},
      );

      expect(isLegacyUnsupportedFormatMessage(message), isFalse);
    });

    test('returns null when JSON parse fails', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message =
          normalizer.normalizeLegacyJson(_legacyFixture('invalid_json.txt'));

      expect(message, isNull);
    });

    test('uses injected extractor implementation', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
        legacyChatExtractor: const _InjectedExtractor(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        _legacyFixture('other_payload.json'),
      );

      expect(message, isNotNull);
      expect(message!.type, AppMessageType.chat);
      expect(message.content, 'from-injected-extractor');
      expect(message.userId, 'injected-user');
      expect(message.timestamp, DateTime.parse('2026-03-22T12:34:56Z'));
    });

    test('treats non-string content as unsupported-format', () {
      final MessageNormalizer normalizer = MessageNormalizer(
        idGenerator: _sequentialIdGenerator(),
      );

      final AppMessage? message = normalizer.normalizeLegacyJson(
        _legacyFixture('chat_non_string_content.json'),
      );

      expect(message, isNotNull);
      expect(message!.type, AppMessageType.notification);
      expect(isLegacyUnsupportedFormatMessage(message), isTrue);
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

String _legacyFixture(String name) {
  final Uri fixtureUri =
      Directory.current.uri.resolve('test/fixtures/legacy/$name');
  return File.fromUri(fixtureUri).readAsStringSync();
}
