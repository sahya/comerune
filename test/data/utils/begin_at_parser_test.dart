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
      expect(result.millisecondsSinceEpoch, 1719835200 * 1000);
    });

    test('parses integer value as milliseconds-since-epoch', () {
      // 1719835200000 = 2024-07-01T12:00:00Z
      final DateTime? result = parseBeginAt(<String, dynamic>{
        'beginAt': 1719835200000,
      });

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, 1719835200000);
    });

    test('returns null when beginAt is missing', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{});

      expect(result, isNull);
    });

    test('returns null when beginAt is null', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{'beginAt': null});

      expect(result, isNull);
    });

    test('returns null when beginAt is empty string', () {
      final DateTime? result = parseBeginAt(<String, dynamic>{'beginAt': ''});

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
      final DateTime? result = parseBeginAt(<String, dynamic>{'beginAt': true});

      expect(result, isNull);
    });
  });

  group('parseDateTimeFlexible', () {
    test('parses ISO 8601 string', () {
      final DateTime? result = parseDateTimeFlexible(
        '2025-07-01T12:00:00+09:00',
      );

      expect(result, isNotNull);
      expect(result!.toUtc(), DateTime.utc(2025, 7, 1, 3, 0, 0));
    });

    test('parses integer as seconds-since-epoch', () {
      // 1719828000 = 2024-07-01T10:00:00Z
      final DateTime? result = parseDateTimeFlexible(1719828000);

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, 1719828000 * 1000);
    });

    test('parses integer as milliseconds-since-epoch', () {
      // 1719828000000 = 2024-07-01T10:00:00Z
      final DateTime? result = parseDateTimeFlexible(1719828000000);

      expect(result, isNotNull);
      expect(result!.isUtc, isTrue);
      expect(result.millisecondsSinceEpoch, 1719828000000);
    });

    test('returns null for null', () {
      expect(parseDateTimeFlexible(null), isNull);
    });

    test('returns null for empty string', () {
      expect(parseDateTimeFlexible(''), isNull);
    });

    test('returns null for unparseable string', () {
      expect(parseDateTimeFlexible('not-a-date'), isNull);
    });

    test('returns null for double', () {
      expect(parseDateTimeFlexible(1719828000.5), isNull);
    });

    test('returns null for bool', () {
      expect(parseDateTimeFlexible(true), isNull);
    });

    test('returns null for list', () {
      expect(parseDateTimeFlexible(<String>[]), isNull);
    });

    test('returns null for map', () {
      expect(parseDateTimeFlexible(<String, Object?>{}), isNull);
    });
  });
}
