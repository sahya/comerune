/// X.Y.Z バージョンの値オブジェクト。
///
/// 本アプリの更新判定でしか使わないため、SemVer 仕様のうち X.Y.Z のみを
/// 比較対象とし、プレリリース・ビルドメタデータは順序判定で**無視**する。
/// データ源（GitHub Releases API `/releases/latest`）はプレリリースを除外
/// するので、優先順位を厳密に扱う実装上の必要が無い。
///
/// 解析は防御的に行い、不正な文字列では例外を投げず [tryParse] が null を
/// 返す。呼び出し側はこれを「判定不能」として安全側（強制ブロックしない）
/// に倒す。
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// 受け入れる形式: `X.Y.Z` / `vX.Y.Z` / `X.Y.Z+build` / `X.Y.Z-pre` /
  /// `X.Y.Z-pre+build`。`-pre` と `+build` は順序に影響しないため捨てる。
  static SemanticVersion? tryParse(String? input) {
    if (input == null) {
      return null;
    }
    String text = input.trim();
    if (text.isEmpty) {
      return null;
    }
    if (text.startsWith('v') || text.startsWith('V')) {
      text = text.substring(1);
    }
    // ビルドメタデータとプレリリースは順序に影響しないので除去する。
    final int plusIndex = text.indexOf('+');
    if (plusIndex >= 0) {
      text = text.substring(0, plusIndex);
    }
    final int dashIndex = text.indexOf('-');
    if (dashIndex >= 0) {
      text = text.substring(0, dashIndex);
    }
    final List<String> parts = text.split('.');
    if (parts.length != 3) {
      return null;
    }
    final int? major = _parseNonNegativeInt(parts[0]);
    final int? minor = _parseNonNegativeInt(parts[1]);
    final int? patch = _parseNonNegativeInt(parts[2]);
    if (major == null || minor == null || patch == null) {
      return null;
    }
    return SemanticVersion(major, minor, patch);
  }

  static int? _parseNonNegativeInt(String value) {
    // `int.tryParse` は前後の符号や空白を許すため、数字のみを厳格に確認する。
    if (value.isEmpty || !RegExp(r'^\d+$').hasMatch(value)) {
      return null;
    }
    return int.tryParse(value);
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;
  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is SemanticVersion &&
        major == other.major &&
        minor == other.minor &&
        patch == other.patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
