/// /teach コマンドの解析結果。
class TeachCommand {
  const TeachCommand({required this.pattern, required this.replacement});

  /// 辞書に登録するパターン文字列。
  final String pattern;

  /// パターンに対する読み替え文字列。
  final String replacement;
}

/// /unteach コマンドの解析結果。
class UnteachCommand {
  const UnteachCommand({required this.pattern});

  /// 辞書から削除するパターン文字列。
  final String pattern;
}

/// コメントテキストから teach/unteach コマンドを解析するパーサー。
class TeachCommandParser {
  /// `/teach パターン 読み` を解析する。失敗時は `null` を返す。
  ///
  /// パターンと読みはそれぞれ1つ以上の非空白文字で構成される。
  /// 読みにはスペースを含めることができる（3番目以降のトークンはすべて
  /// 読みの一部として扱う）。
  static TeachCommand? parseTeach(String text) {
    if (!text.startsWith('/teach ')) {
      return null;
    }
    final String body = text.substring('/teach '.length).trim();
    if (body.isEmpty) {
      return null;
    }
    final int spaceIndex = body.indexOf(' ');
    if (spaceIndex < 0) {
      return null;
    }
    final String pattern = body.substring(0, spaceIndex);
    final String replacement = body.substring(spaceIndex + 1).trim();
    if (pattern.isEmpty || replacement.isEmpty) {
      return null;
    }
    return TeachCommand(pattern: pattern, replacement: replacement);
  }

  /// `/unteach パターン` を解析する。失敗時は `null` を返す。
  static UnteachCommand? parseUnteach(String text) {
    if (!text.startsWith('/unteach ')) {
      return null;
    }
    final String pattern = text.substring('/unteach '.length).trim();
    if (pattern.isEmpty) {
      return null;
    }
    return UnteachCommand(pattern: pattern);
  }

  /// コメントが teach/unteach コマンドかどうか判定する。
  static bool isTeachCommand(String text) {
    return text.startsWith('/teach ') || text.startsWith('/unteach ');
  }
}
