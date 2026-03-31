import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/elapsed_formatter.dart';

void main() {
  group('formatCommentElapsed', () {
    test('returns elapsed time in H:MM:SS format', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 11, 23, 45);

      expect(formatCommentElapsed(beginAt, timestamp), '1:23:45');
    });

    test('returns 0:00:00 when timestamp equals beginAt', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);

      expect(formatCommentElapsed(beginAt, beginAt), '0:00:00');
    });

    test('pads minutes and seconds with leading zeros', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 5, 3);

      expect(formatCommentElapsed(beginAt, timestamp), '0:05:03');
    });

    test('handles multi-hour elapsed time', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 22, 30, 15);

      expect(formatCommentElapsed(beginAt, timestamp), '12:30:15');
    });

    test('returns null when beginAt is null', () {
      final DateTime timestamp = DateTime(2026, 3, 22, 12, 0, 0);

      expect(formatCommentElapsed(null, timestamp), isNull);
    });

    test('returns null when timestamp is before beginAt', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 12, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 11, 59, 59);

      expect(formatCommentElapsed(beginAt, timestamp), isNull);
    });
  });

  group('formatElapsed', () {
    test('returns null when start is null', () {
      expect(formatElapsed(null), isNull);
    });

    test('returns null when start is in the future', () {
      final DateTime future = DateTime.now().add(const Duration(hours: 1));
      expect(formatElapsed(future), isNull);
    });

    test('returns elapsed time for past start', () {
      final DateTime start = DateTime.now()
          .subtract(const Duration(hours: 1, minutes: 2, seconds: 3));
      final String? result = formatElapsed(start);
      expect(result, isNotNull);
      // Allow ±1 second tolerance due to test execution time.
      expect(result, anyOf('1:02:03', '1:02:02', '1:02:04'));
    });
  });

  group('formatWallClockHms', () {
    test('formats local time as HH:MM:SS', () {
      // Use a local DateTime to avoid timezone conversion surprises.
      final DateTime value = DateTime(2026, 3, 22, 9, 5, 3);
      expect(formatWallClockHms(value), '09:05:03');
    });

    test('pads hours, minutes, and seconds with leading zeros', () {
      final DateTime value = DateTime(2026, 1, 1, 0, 0, 0);
      expect(formatWallClockHms(value), '00:00:00');
    });

    test('handles afternoon times', () {
      final DateTime value = DateTime(2026, 6, 15, 23, 59, 59);
      expect(formatWallClockHms(value), '23:59:59');
    });
  });

  group('formatCommentTime', () {
    test('returns elapsed time when beginAt is provided and valid', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 23, 45);

      expect(formatCommentTime(value, beginAt: beginAt), '1:23:45');
    });

    test('falls back to wall-clock time when beginAt is null', () {
      final DateTime value = DateTime(2026, 3, 22, 14, 5, 3);

      expect(formatCommentTime(value), '14:05:03');
    });

    test('falls back to wall-clock time when value is before beginAt', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 12, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 59, 59);

      expect(formatCommentTime(value, beginAt: beginAt), '11:59:59');
    });
  });
}
