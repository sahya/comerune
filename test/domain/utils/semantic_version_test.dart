import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/semantic_version.dart';

void main() {
  group('SemanticVersion.tryParse', () {
    test('parses X.Y.Z', () {
      final SemanticVersion? v = SemanticVersion.tryParse('1.2.3');
      expect(v, isNotNull);
      expect(v!.major, 1);
      expect(v.minor, 2);
      expect(v.patch, 3);
    });

    test('accepts and strips a leading v / V', () {
      expect(
        SemanticVersion.tryParse('v2.0.1'),
        const SemanticVersion(2, 0, 1),
      );
      expect(
        SemanticVersion.tryParse('V2.0.1'),
        const SemanticVersion(2, 0, 1),
      );
    });

    test('ignores build metadata and prerelease suffix for precedence', () {
      expect(
        SemanticVersion.tryParse('1.0.0+7'),
        const SemanticVersion(1, 0, 0),
      );
      expect(
        SemanticVersion.tryParse('1.0.0-beta.2'),
        const SemanticVersion(1, 0, 0),
      );
      expect(
        SemanticVersion.tryParse('1.0.0-beta+exp.sha'),
        const SemanticVersion(1, 0, 0),
      );
    });

    test('returns null for malformed input', () {
      expect(SemanticVersion.tryParse(null), isNull);
      expect(SemanticVersion.tryParse(''), isNull);
      expect(SemanticVersion.tryParse('   '), isNull);
      expect(SemanticVersion.tryParse('1.2'), isNull);
      expect(SemanticVersion.tryParse('1.2.3.4'), isNull);
      expect(SemanticVersion.tryParse('1.2.x'), isNull);
      expect(SemanticVersion.tryParse('-1.2.3'), isNull);
      expect(SemanticVersion.tryParse('one.two.three'), isNull);
    });
  });

  group('comparison', () {
    test('compares numerically, not lexically (1.10.0 > 1.2.0)', () {
      final SemanticVersion a = SemanticVersion.tryParse('1.10.0')!;
      final SemanticVersion b = SemanticVersion.tryParse('1.2.0')!;
      expect(a > b, isTrue);
      expect(b < a, isTrue);
    });

    test('major dominates minor and patch', () {
      expect(
        const SemanticVersion(2, 0, 0) > const SemanticVersion(1, 9, 9),
        isTrue,
      );
    });

    test('equality and hashCode share major/minor/patch only', () {
      const SemanticVersion a = SemanticVersion(1, 2, 3);
      const SemanticVersion b = SemanticVersion(1, 2, 3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString returns X.Y.Z', () {
      expect(const SemanticVersion(1, 2, 3).toString(), '1.2.3');
    });
  });
}
