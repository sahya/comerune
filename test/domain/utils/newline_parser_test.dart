import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/newline_parser.dart';

void main() {
  group('parseNewlineSeparatedSet', () {
    test('returns empty set for empty string', () {
      expect(parseNewlineSeparatedSet(''), const <String>{});
    });

    test('returns empty set for whitespace-only string', () {
      expect(parseNewlineSeparatedSet('   \n  \n  '), const <String>{});
    });

    test('parses single value', () {
      expect(parseNewlineSeparatedSet('12345'), {'12345'});
    });

    test('parses multiple values', () {
      expect(
        parseNewlineSeparatedSet('111\n222\n333'),
        {'111', '222', '333'},
      );
    });

    test('trims whitespace from values', () {
      expect(
        parseNewlineSeparatedSet('  111  \n  222  '),
        {'111', '222'},
      );
    });

    test('ignores blank lines', () {
      expect(
        parseNewlineSeparatedSet('111\n\n222\n\n'),
        {'111', '222'},
      );
    });

    test('deduplicates values', () {
      expect(
        parseNewlineSeparatedSet('111\n111\n222'),
        {'111', '222'},
      );
    });
  });

  group('parseNewlineSeparatedLowerList', () {
    test('returns empty list for empty string', () {
      expect(parseNewlineSeparatedLowerList(''), const <String>[]);
    });

    test('returns empty list for whitespace-only string', () {
      expect(parseNewlineSeparatedLowerList('  \n  '), const <String>[]);
    });

    test('lowercases values', () {
      expect(
        parseNewlineSeparatedLowerList('ABC\nDef\nghi'),
        ['abc', 'def', 'ghi'],
      );
    });

    test('trims and filters blank lines', () {
      expect(
        parseNewlineSeparatedLowerList('  Hello \n\n  World  \n'),
        ['hello', 'world'],
      );
    });
  });
}
