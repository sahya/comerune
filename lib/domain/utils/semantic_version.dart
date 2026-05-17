/// SemVer 2.0.0 のうち本アプリで必要な範囲を扱う値オブジェクト。
///
/// 依存追加禁止方針（`pubspec.yaml` のピン留め運用）に従い、`pub_semver`
/// 等の外部パッケージを使わず最小限を自前実装する。バージョン更新判定
/// （現在版 < 最新版 / 現在版 < サポート下限版）に必要な比較のみを提供し、
/// 範囲制約（`^1.2.0` 等）や `pubspec` の `+build` 番号は扱わない。
///
/// 解析は防御的に行い、不正な文字列では例外を投げず [tryParse] が null を
/// 返す。呼び出し側（更新判定）はこの null を「判定不能」として安全側
/// （強制ブロックしない）に倒す。
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const <String>[],
  });

  final int major;
  final int minor;
  final int patch;

  /// プレリリース識別子（`1.0.0-beta.1` の `['beta', '1']`）。
  /// 空ならば正式版。プレリリースは同じ `X.Y.Z` の正式版より低い。
  final List<String> preRelease;

  /// `X.Y.Z`・`X.Y.Z-pre`・先頭 `v`・`X.Y.Z+build` を受け付ける。
  ///
  /// 解析できない場合は null を返す（例外を投げない）。`+build`
  /// メタデータは SemVer 仕様どおり順序比較で無視するため捨てる。
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

    // ビルドメタデータは順序に影響しないので除去する。
    final int plusIndex = text.indexOf('+');
    if (plusIndex >= 0) {
      text = text.substring(0, plusIndex);
    }

    List<String> preRelease = const <String>[];
    final int dashIndex = text.indexOf('-');
    if (dashIndex >= 0) {
      final String preText = text.substring(dashIndex + 1);
      text = text.substring(0, dashIndex);
      if (preText.isEmpty) {
        return null;
      }
      preRelease = preText.split('.');
      for (final String id in preRelease) {
        if (id.isEmpty) {
          return null;
        }
      }
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
    return SemanticVersion(major, minor, patch, preRelease: preRelease);
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
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    // SemVer: プレリリース有りは無し（正式版）より低い。
    final bool aPre = preRelease.isNotEmpty;
    final bool bPre = other.preRelease.isNotEmpty;
    if (aPre && !bPre) {
      return -1;
    }
    if (!aPre && bPre) {
      return 1;
    }
    if (!aPre && !bPre) {
      return 0;
    }
    return _comparePreRelease(preRelease, other.preRelease);
  }

  static int _comparePreRelease(List<String> a, List<String> b) {
    final int len = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final String x = a[i];
      final String y = b[i];
      final int? xn = int.tryParse(x);
      final int? yn = int.tryParse(y);
      final bool xNumeric = xn != null && RegExp(r'^\d+$').hasMatch(x);
      final bool yNumeric = yn != null && RegExp(r'^\d+$').hasMatch(y);
      if (xNumeric && yNumeric) {
        if (xn != yn) {
          return xn.compareTo(yn);
        }
      } else if (xNumeric != yNumeric) {
        // 数値識別子は非数値識別子より低い。
        return xNumeric ? -1 : 1;
      } else {
        final int c = x.compareTo(y);
        if (c != 0) {
          return c;
        }
      }
    }
    // 共通部分が同じなら識別子が多い方が高い。
    return a.length.compareTo(b.length);
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
    return other is SemanticVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, Object.hashAll(preRelease));

  @override
  String toString() {
    final String base = '$major.$minor.$patch';
    return preRelease.isEmpty ? base : '$base-${preRelease.join('.')}';
  }
}
