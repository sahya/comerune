import 'package:comerune/data/utils/begin_at_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBeginAt', () {
    test('parses ISO 8601 string with timezone offset', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': '2025-07-01T12:00:00+09:00',
      });

      expect(result, isNotNull);
      expect(result!.year, 2025);
      expect(result.month, 7);
      expect(result.day, 1);
    });

    test('parses ISO 8601 UTC string', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': '2025-07-01T03:00:00Z',
      });

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.year, 2025);
      expect(result.month, 7);
      expect(result.day, 1);
      expect(result.hour, 3);
    });

    test('parses integer value as seconds-since-epoch', () {
      // 1719835200 = 2024-07-01T12:00:00Z
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': 1719835200,
      });

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(
        result.millisecondsSinceEpoch,
        1719835200 * 1000,
      );
    });

    test('returns null when beginAt is missing', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{});

      expect(result, isNull);
    });

    test('returns null when beginAt is null', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': null,
      });

      expect(result, isNull);
    });

    test('returns null when beginAt is empty string', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': '',
      });

      expect(result, isNull);
    });

    test('returns null for unparseable string', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': 'not-a-date',
      });

      expect(result, isNull);
    });

    test('returns null for unsupported type (double)', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': 1719835200.5,
      });

      expect(result, isNull);
    });

    test('returns null for unsupported type (bool)', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': true,
      });

      expect(result, isNull);
    });
  });
}
