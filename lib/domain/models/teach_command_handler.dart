import '../../comment_speech/src/models/replace_rule.dart';
import 'app_settings.dart';
import 'teach_command.dart';

/// teach/unteach コマンドの実行結果。
class TeachCommandResult {
  const TeachCommandResult({
    required this.success,
    required this.message,
    this.updatedRules,
  });

  /// コマンドが成功したかどうか。
  final bool success;

  /// ユーザーに表示するフィードバックメッセージ。
  final String message;

  /// 成功時のみ非 null。更新後の辞書ルールリスト。
  final List<ReplaceRule>? updatedRules;
}

/// teach/unteach コマンドを実行するハンドラー。
class TeachCommandHandler {
  static const int _maxPatternLength = 100;
  static const int _maxReplacementLength = 200;

  /// `/teach` コマンドを実行する。
  ///
  /// - [command] 解析済みの teach コマンド
  /// - [currentRules] 現在の辞書ルールリスト
  /// - [containsNgWord] NGワード判定関数
  static TeachCommandResult executeTeach({
    required TeachCommand command,
    required List<ReplaceRule> currentRules,
    required bool Function(String) containsNgWord,
  }) {
    // 空チェック。
    if (command.pattern.isEmpty || command.replacement.isEmpty) {
      return const TeachCommandResult(
        success: false,
        message: '使い方: /teach パターン 読み',
      );
    }

    // 文字列長の上限チェック。
    if (command.pattern.length > _maxPatternLength) {
      return const TeachCommandResult(
        success: false,
        message: 'パターンが長すぎます（100文字以内）',
      );
    }
    if (command.replacement.length > _maxReplacementLength) {
      return const TeachCommandResult(
        success: false,
        message: '読みが長すぎます（200文字以内）',
      );
    }

    // NGワードチェック（パターン）。
    if (containsNgWord(command.pattern)) {
      return const TeachCommandResult(
        success: false,
        message: '不適切な言葉を含むため登録できません',
      );
    }

    // NGワードチェック（読み）。
    if (containsNgWord(command.replacement)) {
      return const TeachCommandResult(
        success: false,
        message: '不適切な言葉を含むため登録できません',
      );
    }

    // パターンを完全一致の正規表現に変換。
    final String escapedPattern = RegExp.escape(command.pattern);
    final List<ReplaceRule> updatedRules = List<ReplaceRule>.of(currentRules);

    // 重複チェック: 同じエスケープ済みパターンが既にある場合は更新。
    final int existingIndex = updatedRules.indexWhere(
      (ReplaceRule rule) => rule.pattern == escapedPattern,
    );

    final ReplaceRule newRule = ReplaceRule(
      pattern: escapedPattern,
      replacement: command.replacement,
    );

    if (existingIndex >= 0) {
      if (isDefaultNicoDictionaryRule(updatedRules[existingIndex])) {
        return const TeachCommandResult(
          success: false,
          message: '既定の辞書ルールは編集できません。無効化してください',
        );
      }
      updatedRules[existingIndex] = newRule;
      return TeachCommandResult(
        success: true,
        message: '辞書を更新しました: ${command.pattern} -> ${command.replacement}',
        updatedRules: updatedRules,
      );
    }

    updatedRules.add(newRule);
    return TeachCommandResult(
      success: true,
      message: '辞書に登録しました: ${command.pattern} -> ${command.replacement}',
      updatedRules: updatedRules,
    );
  }

  /// `/unteach` コマンドを実行する。
  ///
  /// - [command] 解析済みの unteach コマンド
  /// - [currentRules] 現在の辞書ルールリスト
  static TeachCommandResult executeUnteach({
    required UnteachCommand command,
    required List<ReplaceRule> currentRules,
  }) {
    // 空チェック。
    if (command.pattern.isEmpty) {
      return const TeachCommandResult(
        success: false,
        message: '使い方: /unteach パターン',
      );
    }

    final String escapedPattern = RegExp.escape(command.pattern);
    final List<ReplaceRule> updatedRules = List<ReplaceRule>.of(currentRules);

    final int existingIndex = updatedRules.indexWhere(
      (ReplaceRule rule) => rule.pattern == escapedPattern,
    );

    if (existingIndex >= 0 &&
        isDefaultNicoDictionaryRule(updatedRules[existingIndex])) {
      return const TeachCommandResult(
        success: false,
        message: '既定の辞書ルールは削除できません。無効化してください',
      );
    }

    if (existingIndex < 0) {
      return TeachCommandResult(
        success: false,
        message: '辞書に「${command.pattern}」は登録されていません',
      );
    }

    updatedRules.removeAt(existingIndex);
    return TeachCommandResult(
      success: true,
      message: '辞書から削除しました: ${command.pattern}',
      updatedRules: updatedRules,
    );
  }
}
