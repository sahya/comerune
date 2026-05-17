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
      expect(v.preRelease, isEmpty);
    });

    test('accepts and strips a leading v', () {
      expect(SemanticVersion.tryParse('v2.0.1'), SemanticVersion(2, 0, 1));
      expect(SemanticVersion.tryParse('V2.0.1'), SemanticVersion(2, 0, 1));
    });

    test('ignores build metadata for precedence', () {
      expect(SemanticVersion.tryParse('1.0.0+7'), SemanticVersion(1, 0, 0));
      expect(
        SemanticVersion.tryParse('1.0.0-beta+exp.sha'),
        SemanticVersion(1, 0, 0, preRelease: <String>['beta']),
      );
    });

    test('parses prerelease identifiers', () {
      final SemanticVersion? v = SemanticVersion.tryParse('1.0.0-beta.2');
      expect(v, isNotNull);
      expect(v!.preRelease, <String>['beta', '2']);
    });

    test('returns null for malformed input', () {
      expect(SemanticVersion.tryParse(null), isNull);
      expect(SemanticVersion.tryParse(''), isNull);
      expect(SemanticVersion.tryParse('   '), isNull);
      expect(SemanticVersion.tryParse('1.2'), isNull);
      expect(SemanticVersion.tryParse('1.2.3.4'), isNull);
      expect(SemanticVersion.tryParse('1.2.x'), isNull);
      expect(SemanticVersion.tryParse('-1.2.3'), isNull);
      expect(SemanticVersion.tryParse('1.2.3-'), isNull);
      expect(SemanticVersion.tryParse('1.2.3-beta..1'), isNull);
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
      expect(SemanticVersion(2, 0, 0) > SemanticVersion(1, 9, 9), isTrue);
    });

    test('prerelease is lower than the same released version', () {
      final SemanticVersion pre = SemanticVersion.tryParse('1.0.0-beta')!;
      final SemanticVersion rel = SemanticVersion.tryParse('1.0.0')!;
      expect(pre < rel, isTrue);
      expect(rel > pre, isTrue);
    });

    test('numeric prerelease identifiers compare numerically', () {
      final SemanticVersion a = SemanticVersion.tryParse('1.0.0-alpha.2')!;
      final SemanticVersion b = SemanticVersion.tryParse('1.0.0-alpha.10')!;
      expect(a < b, isTrue);
    });

    test('numeric identifiers are lower than alphanumeric', () {
      final SemanticVersion a = SemanticVersion.tryParse('1.0.0-1')!;
      final SemanticVersion b = SemanticVersion.tryParse('1.0.0-alpha')!;
      expect(a < b, isTrue);
    });

    test('more prerelease identifiers is higher when prefixes match', () {
      final SemanticVersion a = SemanticVersion.tryParse('1.0.0-alpha')!;
      final SemanticVersion b = SemanticVersion.tryParse('1.0.0-alpha.1')!;
      expect(a < b, isTrue);
    });

    test('equality and hashCode ignore build metadata', () {
      final SemanticVersion a = SemanticVersion.tryParse('1.2.3+1')!;
      final SemanticVersion b = SemanticVersion.tryParse('1.2.3+2')!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('toString round-trips base and prerelease', () {
      expect(SemanticVersion(1, 2, 3).toString(), '1.2.3');
      expect(
        SemanticVersion(1, 0, 0, preRelease: <String>['rc', '1']).toString(),
        '1.0.0-rc.1',
      );
    });
  });
}
