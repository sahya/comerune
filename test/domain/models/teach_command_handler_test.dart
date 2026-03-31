import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/comment_speech/src/models/replace_rule.dart';
import 'package:comerune/domain/models/teach_command.dart';
import 'package:comerune/domain/models/teach_command_handler.dart';

void main() {
  bool neverNg(String _) => false;

  group('TeachCommandHandler.executeTeach', () {
    test('adds a new rule to an empty list', () {
      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'テスト', replacement: 'てすと'),
        currentRules: const <ReplaceRule>[],
        containsNgWord: neverNg,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules, isNotNull);
      expect(result.updatedRules!.length, 1);
      expect(result.updatedRules!.first.pattern, RegExp.escape('テスト'));
      expect(result.updatedRules!.first.replacement, 'てすと');
      expect(result.message, contains('登録しました'));
    });

    test('appends a new rule to existing rules', () {
      const List<ReplaceRule> existing = <ReplaceRule>[
        ReplaceRule(pattern: r'[wｗ]{3,}', replacement: 'わらわら'),
      ];

      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'テスト', replacement: 'てすと'),
        currentRules: existing,
        containsNgWord: neverNg,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.length, 2);
      expect(result.updatedRules!.first.pattern, r'[wｗ]{3,}');
      expect(result.updatedRules!.last.pattern, RegExp.escape('テスト'));
    });

    test('updates existing rule with the same escaped pattern', () {
      final String escapedPattern = RegExp.escape('テスト');
      final List<ReplaceRule> existing = <ReplaceRule>[
        ReplaceRule(pattern: escapedPattern, replacement: '旧読み'),
      ];

      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'テスト', replacement: '新読み'),
        currentRules: existing,
        containsNgWord: neverNg,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.length, 1);
      expect(result.updatedRules!.first.replacement, '新読み');
      expect(result.message, contains('更新しました'));
    });

    test('rejects pattern containing NG word', () {
      bool containsNg(String text) => text.contains('NG');

      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'NG単語', replacement: '読み'),
        currentRules: const <ReplaceRule>[],
        containsNgWord: containsNg,
      );

      expect(result.success, isFalse);
      expect(result.updatedRules, isNull);
      expect(result.message, contains('不適切'));
    });

    test('rejects replacement containing NG word', () {
      bool containsNg(String text) => text.contains('NG');

      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'パターン', replacement: 'NG読み'),
        currentRules: const <ReplaceRule>[],
        containsNgWord: containsNg,
      );

      expect(result.success, isFalse);
      expect(result.updatedRules, isNull);
      expect(result.message, contains('不適切'));
    });

    test('escapes regex special characters in pattern', () {
      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: '(test)', replacement: 'テスト'),
        currentRules: const <ReplaceRule>[],
        containsNgWord: neverNg,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.first.pattern, r'\(test\)');
    });

    test('escapes dot in pattern', () {
      final TeachCommandResult result = TeachCommandHandler.executeTeach(
        command: const TeachCommand(pattern: 'a.b', replacement: 'エードットビー'),
        currentRules: const <ReplaceRule>[],
        containsNgWord: neverNg,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.first.pattern, r'a\.b');
    });
  });

  group('TeachCommandHandler.executeUnteach', () {
    test('removes existing rule', () {
      final String escapedPattern = RegExp.escape('テスト');
      final List<ReplaceRule> existing = <ReplaceRule>[
        const ReplaceRule(pattern: r'[wｗ]{3,}', replacement: 'わらわら'),
        ReplaceRule(pattern: escapedPattern, replacement: 'てすと'),
      ];

      final TeachCommandResult result = TeachCommandHandler.executeUnteach(
        command: const UnteachCommand(pattern: 'テスト'),
        currentRules: existing,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.length, 1);
      expect(result.updatedRules!.first.pattern, r'[wｗ]{3,}');
      expect(result.message, contains('削除しました'));
    });

    test('returns error when pattern not found', () {
      final TeachCommandResult result = TeachCommandHandler.executeUnteach(
        command: const UnteachCommand(pattern: '存在しない'),
        currentRules: const <ReplaceRule>[],
      );

      expect(result.success, isFalse);
      expect(result.updatedRules, isNull);
      expect(result.message, contains('登録されていません'));
    });

    test('does not modify original list', () {
      final String escapedPattern = RegExp.escape('テスト');
      final List<ReplaceRule> original = <ReplaceRule>[
        ReplaceRule(pattern: escapedPattern, replacement: 'てすと'),
      ];

      final TeachCommandResult result = TeachCommandHandler.executeUnteach(
        command: const UnteachCommand(pattern: 'テスト'),
        currentRules: original,
      );

      expect(result.success, isTrue);
      expect(result.updatedRules!.length, 0);
      // Original list should remain unchanged.
      expect(original.length, 1);
    });
  });
}
