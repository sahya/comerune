import 'package:comerune/application/filter/broadcaster_id_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #727: direct boundary tests for [redactBroadcasterId].
///
/// Locks in the redaction policy: the helper must never leak more than
/// the documented prefix, and short IDs must be reduced to `***` only.
void main() {
  group('redactBroadcasterId', () {
    test('empty string is fully redacted', () {
      expect(redactBroadcasterId(''), '***');
    });

    test('single-character ID is fully redacted', () {
      expect(redactBroadcasterId('a'), '***');
    });

    test('exactly 4 chars is fully redacted (boundary: length > 4)', () {
      expect(redactBroadcasterId('abcd'), '***');
    });

    test('5-char ID keeps the 4-char prefix and appends ***', () {
      expect(redactBroadcasterId('abcde'), 'abcd***');
    });

    test('long ID still keeps only the first 4 chars + ***', () {
      expect(redactBroadcasterId('abcdefghij'), 'abcd***');
    });
  });
}
