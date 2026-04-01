import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/models/teach_command.dart';

void main() {
  group('TeachCommandParser.parseTeach', () {
    test('parses valid /teach command', () {
      final TeachCommand? result = TeachCommandParser.parseTeach(
        '/teach ニコニコ にこにこ',
      );
      expect(result, isNotNull);
      expect(result!.pattern, 'ニコニコ');
      expect(result.replacement, 'にこにこ');
    });

    test('parses /teach with multiple spaces in replacement', () {
      final TeachCommand? result = TeachCommandParser.parseTeach(
        '/teach hello good morning',
      );
      expect(result, isNotNull);
      expect(result!.pattern, 'hello');
      expect(result.replacement, 'good morning');
    });

    test('returns null for /teach without arguments', () {
      expect(TeachCommandParser.parseTeach('/teach '), isNull);
    });

    test('returns null for /teach with only pattern (no replacement)', () {
      expect(TeachCommandParser.parseTeach('/teach パターン'), isNull);
    });

    test('returns null for text not starting with /teach ', () {
      expect(TeachCommandParser.parseTeach('/teachパターン 読み'), isNull);
    });

    test('returns null for empty string', () {
      expect(TeachCommandParser.parseTeach(''), isNull);
    });

    test('returns null for /teach command only', () {
      expect(TeachCommandParser.parseTeach('/teach'), isNull);
    });
  });

  group('TeachCommandParser.parseUnteach', () {
    test('parses valid /unteach command', () {
      final UnteachCommand? result = TeachCommandParser.parseUnteach(
        '/unteach ニコニコ',
      );
      expect(result, isNotNull);
      expect(result!.pattern, 'ニコニコ');
    });

    test('returns null for /unteach without arguments', () {
      expect(TeachCommandParser.parseUnteach('/unteach '), isNull);
    });

    test('returns null for /unteach only', () {
      expect(TeachCommandParser.parseUnteach('/unteach'), isNull);
    });

    test('returns null for text not starting with /unteach ', () {
      expect(TeachCommandParser.parseUnteach('/unteachパターン'), isNull);
    });

    test('returns null for empty string', () {
      expect(TeachCommandParser.parseUnteach(''), isNull);
    });
  });

  group('TeachCommandParser.isTeachCommand', () {
    test('returns true for /teach command', () {
      expect(TeachCommandParser.isTeachCommand('/teach パターン 読み'), isTrue);
    });

    test('returns true for /unteach command', () {
      expect(TeachCommandParser.isTeachCommand('/unteach パターン'), isTrue);
    });

    test('returns false for normal comment', () {
      expect(TeachCommandParser.isTeachCommand('普通のコメント'), isFalse);
    });

    test('returns false for /teach without trailing space', () {
      expect(TeachCommandParser.isTeachCommand('/teachパターン'), isFalse);
    });

    test('returns false for /unteach without trailing space', () {
      expect(TeachCommandParser.isTeachCommand('/unteachパターン'), isFalse);
    });

    test('returns false for other slash commands', () {
      expect(TeachCommandParser.isTeachCommand('/nicoad'), isFalse);
    });

    test('returns false for empty string', () {
      expect(TeachCommandParser.isTeachCommand(''), isFalse);
    });
  });
}
