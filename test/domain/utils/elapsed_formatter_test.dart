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

  group('formatWallClock', () {
    test('returns local time in HH:MM:SS format', () {
      final DateTime dt = DateTime(2026, 3, 22, 9, 5, 3);
      expect(formatWallClock(dt), '09:05:03');
    });

    test('pads hours, minutes, and seconds with leading zeros', () {
      final DateTime dt = DateTime(2026, 1, 1, 0, 0, 0);
      expect(formatWallClock(dt), '00:00:00');
    });

    test('handles afternoon times', () {
      final DateTime dt = DateTime(2026, 3, 22, 23, 59, 59);
      expect(formatWallClock(dt), '23:59:59');
    });
  });

  group('formatTimestamp', () {
    test('returns elapsed time when beginAt is provided and valid', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 23, 45);
      expect(formatTimestamp(value, beginAt: beginAt), '1:23:45');
    });

    test('falls back to wall-clock when beginAt is null', () {
      final DateTime value = DateTime(2026, 3, 22, 14, 30, 5);
      expect(formatTimestamp(value), '14:30:05');
    });

    test('falls back to wall-clock when value is before beginAt', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 12, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 59, 59);
      expect(formatTimestamp(value, beginAt: beginAt), '11:59:59');
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

    test('returns H:MM:SS format (hours not zero-padded)', () {
      // Regression: hours should NOT be zero-padded (H:MM:SS not HH:MM:SS).
      final DateTime start =
          DateTime.now().subtract(const Duration(hours: 2, minutes: 5, seconds: 9));
      final String? result = formatElapsed(start);
      expect(result, isNotNull);
      // Must match single-digit-hour pattern like '2:05:09', not '02:05:09'.
      expect(result, anyOf('2:05:09', '2:05:08', '2:05:10'));
      expect(result!.startsWith('02:'), isFalse,
          reason: 'Hours must not be zero-padded in elapsed format');
    });

    test('returns 0:00:00 for a start of exactly now (within 1 second)', () {
      final DateTime start = DateTime.now();
      final String? result = formatElapsed(start);
      expect(result, isNotNull);
      expect(result, anyOf('0:00:00', '0:00:01'));
    });
  });

  // ---------------------------------------------------------------------------
  // formatWallClock — additional edge cases
  // ---------------------------------------------------------------------------
  group('formatWallClock edge cases', () {
    test('midnight returns 00:00:00', () {
      final DateTime midnight = DateTime(2026, 1, 1, 0, 0, 0);
      expect(formatWallClock(midnight), '00:00:00');
    });

    test('noon returns 12:00:00', () {
      final DateTime noon = DateTime(2026, 6, 15, 12, 0, 0);
      expect(formatWallClock(noon), '12:00:00');
    });

    test('single-digit hour is zero-padded', () {
      // e.g. 9 AM → '09:...'
      final DateTime dt = DateTime(2026, 3, 22, 9, 0, 0);
      expect(formatWallClock(dt), startsWith('09:'));
    });

    test('single-digit minute is zero-padded', () {
      final DateTime dt = DateTime(2026, 3, 22, 10, 4, 0);
      expect(formatWallClock(dt), '10:04:00');
    });

    test('single-digit second is zero-padded', () {
      final DateTime dt = DateTime(2026, 3, 22, 10, 0, 7);
      expect(formatWallClock(dt), '10:00:07');
    });

    test('end-of-day returns 23:59:59', () {
      final DateTime eod = DateTime(2026, 12, 31, 23, 59, 59);
      expect(formatWallClock(eod), '23:59:59');
    });

    test('UTC DateTime is converted to local before formatting', () {
      // A UTC DateTime and its local equivalent must produce the same output,
      // because formatWallClock always calls toLocal() internally.
      final DateTime utc = DateTime.utc(2026, 3, 22, 8, 30, 0);
      final DateTime local = utc.toLocal();
      // Both should produce the same string.
      expect(formatWallClock(utc), formatWallClock(local));
    });

    test('local DateTime is not double-converted', () {
      // Passing an already-local DateTime must not shift the time a second time.
      final DateTime local = DateTime(2026, 3, 22, 15, 45, 30); // local
      // toLocal() on an already-local DateTime is a no-op, so this must equal
      // the straightforward formatted value.
      expect(formatWallClock(local), '15:45:30');
    });
  });

  // ---------------------------------------------------------------------------
  // formatTimestamp — additional edge cases
  // ---------------------------------------------------------------------------
  group('formatTimestamp edge cases', () {
    test('beginAt exactly equals value → returns 0:00:00 elapsed', () {
      final DateTime t = DateTime(2026, 3, 22, 10, 0, 0);
      expect(formatTimestamp(t, beginAt: t), '0:00:00');
    });

    test('beginAt 1 second before value → returns 0:00:01 elapsed', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 10, 0, 1);
      expect(formatTimestamp(value, beginAt: beginAt), '0:00:01');
    });

    test('very large elapsed duration >24 h → hours > 24', () {
      final DateTime beginAt = DateTime(2026, 3, 20, 10, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 30, 0);
      // 49 hours 30 minutes
      expect(formatTimestamp(value, beginAt: beginAt), '49:30:00');
    });

    test('beginAt in future relative to value → falls back to wall clock', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 15, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 14, 0, 0); // before beginAt
      expect(formatTimestamp(value, beginAt: beginAt), '14:00:00');
    });

    test('elapsed format uses single-digit hours (H:MM:SS), not HH:MM:SS', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 8, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 9, 5, 3);
      // 1 hour elapsed → '1:05:03', NOT '01:05:03'
      final String result = formatTimestamp(value, beginAt: beginAt);
      expect(result, '1:05:03');
      expect(result.startsWith('01:'), isFalse,
          reason: 'Elapsed hours must not be zero-padded');
    });

    test('wall-clock fallback uses double-digit hours (HH:MM:SS)', () {
      // Single-digit hour with no beginAt → hours must be zero-padded.
      final DateTime value = DateTime(2026, 3, 22, 9, 5, 3);
      final String result = formatTimestamp(value);
      expect(result, '09:05:03');
    });
  });

  // ---------------------------------------------------------------------------
  // formatCommentElapsed — additional regression tests
  // ---------------------------------------------------------------------------
  group('formatCommentElapsed regression', () {
    test('1 second elapsed returns 0:00:01', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 0, 1);
      expect(formatCommentElapsed(beginAt, timestamp), '0:00:01');
    });

    test('exactly 59 seconds returns 0:00:59', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 0, 59);
      expect(formatCommentElapsed(beginAt, timestamp), '0:00:59');
    });

    test('exactly 1 minute returns 0:01:00', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 1, 0);
      expect(formatCommentElapsed(beginAt, timestamp), '0:01:00');
    });

    test('duration spanning midnight is counted correctly', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 23, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 23, 1, 0, 0);
      // 2 hours across midnight
      expect(formatCommentElapsed(beginAt, timestamp), '2:00:00');
    });

    test('elapsed >24 hours → hours exceed 24', () {
      final DateTime beginAt = DateTime(2026, 3, 20, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 30, 15);
      // 48 h 30 m 15 s
      expect(formatCommentElapsed(beginAt, timestamp), '48:30:15');
    });

    test('hours field is never zero-padded (H:MM:SS format)', () {
      // Regression: single-digit hours must stay single-digit.
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 11, 23, 45);
      final String? result = formatCommentElapsed(beginAt, timestamp);
      expect(result, '1:23:45');
      expect(result!.startsWith('01:'), isFalse,
          reason: 'Hours must not be zero-padded in elapsed format');
    });

    test('minutes and seconds are always two digits', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 3, 7);
      expect(formatCommentElapsed(beginAt, timestamp), '0:03:07');
    });

    test('known value regression: 1:23:45 still matches after refactor', () {
      // This is the canonical value from the original test — must never change.
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 11, 23, 45);
      expect(formatCommentElapsed(beginAt, timestamp), '1:23:45');
    });

    test('known value regression: 12:30:15 still matches after refactor', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 22, 30, 15);
      expect(formatCommentElapsed(beginAt, timestamp), '12:30:15');
    });

    test('known value regression: 0:05:03 still matches after refactor', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime timestamp = DateTime(2026, 3, 22, 10, 5, 3);
      expect(formatCommentElapsed(beginAt, timestamp), '0:05:03');
    });
  });

  // ---------------------------------------------------------------------------
  // Duration formatting consistency across functions
  // ---------------------------------------------------------------------------
  group('Duration formatting consistency', () {
    test('formatCommentElapsed and formatTimestamp produce identical elapsed output', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime value = DateTime(2026, 3, 22, 11, 23, 45);
      expect(
        formatTimestamp(value, beginAt: beginAt),
        formatCommentElapsed(beginAt, value),
      );
    });

    test('formatWallClock output length is always 8 characters (HH:MM:SS)', () {
      final List<DateTime> samples = [
        DateTime(2026, 1, 1, 0, 0, 0),
        DateTime(2026, 6, 15, 12, 0, 0),
        DateTime(2026, 12, 31, 23, 59, 59),
        DateTime(2026, 3, 22, 9, 5, 3),
      ];
      for (final dt in samples) {
        final String result = formatWallClock(dt);
        expect(result.length, 8,
            reason: 'formatWallClock("$dt") → "$result" must be 8 chars');
      }
    });

    test('formatCommentElapsed output matches H:MM:SS pattern', () {
      final List<(DateTime, DateTime, String)> cases = [
        (DateTime(2026, 3, 22, 10, 0, 0), DateTime(2026, 3, 22, 10, 0, 0), '0:00:00'),
        (DateTime(2026, 3, 22, 10, 0, 0), DateTime(2026, 3, 22, 10, 0, 1), '0:00:01'),
        (DateTime(2026, 3, 22, 10, 0, 0), DateTime(2026, 3, 22, 11, 23, 45), '1:23:45'),
        (DateTime(2026, 3, 22, 10, 0, 0), DateTime(2026, 3, 22, 22, 30, 15), '12:30:15'),
      ];
      for (final (beginAt, ts, expected) in cases) {
        expect(formatCommentElapsed(beginAt, ts), expected,
            reason: 'beginAt=$beginAt ts=$ts');
      }
    });

    test('formatTimestamp switches format correctly based on beginAt', () {
      final DateTime beginAt = DateTime(2026, 3, 22, 10, 0, 0);
      final DateTime valueAfter = DateTime(2026, 3, 22, 11, 0, 0);
      final DateTime valueBefore = DateTime(2026, 3, 22, 9, 5, 3);

      // With valid beginAt → elapsed (H:MM:SS, hours not zero-padded)
      expect(formatTimestamp(valueAfter, beginAt: beginAt), '1:00:00');

      // Without beginAt → wall clock (HH:MM:SS, all fields zero-padded)
      expect(formatTimestamp(valueBefore), '09:05:03');

      // With future beginAt → wall clock fallback (HH:MM:SS)
      expect(formatTimestamp(valueBefore, beginAt: beginAt), '09:05:03');
    });
  });
}
