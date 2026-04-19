import 'package:comerune/domain/models/ng_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgPolicy', () {
    test('wireName round-trips for every value', () {
      for (final NgPolicy policy in NgPolicy.values) {
        expect(NgPolicy.tryParse(policy.wireName), policy);
        expect(NgPolicy.fromWireName(policy.wireName), policy);
      }
    });

    test('wireName matches the documented strings', () {
      expect(NgPolicy.blockAll.wireName, 'blockAll');
      expect(NgPolicy.blockSpeechOnly.wireName, 'blockSpeechOnly');
    });

    test('defaultPolicy is the conservative speech-only option', () {
      expect(NgPolicy.defaultPolicy, NgPolicy.blockSpeechOnly);
    });

    test('tryParse returns null for null input', () {
      expect(NgPolicy.tryParse(null), isNull);
    });

    test('tryParse returns null for unknown strings', () {
      expect(NgPolicy.tryParse('blockNone'), isNull);
      expect(NgPolicy.tryParse(''), isNull);
      expect(NgPolicy.tryParse('BLOCKALL'), isNull);
      expect(NgPolicy.tryParse(' blockAll '), isNull);
    });

    test('fromWireName falls back to defaultPolicy on null or invalid', () {
      expect(NgPolicy.fromWireName(null), NgPolicy.defaultPolicy);
      expect(NgPolicy.fromWireName(''), NgPolicy.defaultPolicy);
      expect(NgPolicy.fromWireName('blockNone'), NgPolicy.defaultPolicy);
    });

    test('values has exactly 2 entries (regression guard)', () {
      expect(NgPolicy.values.length, 2);
    });
  });
}
