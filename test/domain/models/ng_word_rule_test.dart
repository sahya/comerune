import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgWordRule', () {
    test('toMap and fromMap round-trip preserves all fields', () {
      const NgWordRule rule = NgWordRule(pattern: 'test', enabled: false);
      final NgWordRule restored = NgWordRule.fromMap(rule.toMap());
      expect(restored.pattern, 'test');
      expect(restored.enabled, isFalse);
      expect(restored, equals(rule));
    });

    test('fromMap defaults enabled to true when missing', () {
      final NgWordRule rule = NgWordRule.fromMap(<String, dynamic>{
        'pattern': 'hello',
      });
      expect(rule.pattern, 'hello');
      expect(rule.enabled, isTrue);
    });

    test('constructor defaults enabled to true', () {
      const NgWordRule rule = NgWordRule(pattern: 'word');
      expect(rule.enabled, isTrue);
    });

    test('equality compares pattern and enabled', () {
      const NgWordRule a = NgWordRule(pattern: 'x', enabled: true);
      const NgWordRule b = NgWordRule(pattern: 'x', enabled: true);
      const NgWordRule c = NgWordRule(pattern: 'x', enabled: false);
      const NgWordRule d = NgWordRule(pattern: 'y', enabled: true);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('hashCode is consistent with equality', () {
      const NgWordRule a = NgWordRule(pattern: 'x', enabled: true);
      const NgWordRule b = NgWordRule(pattern: 'x', enabled: true);
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes pattern and enabled', () {
      const NgWordRule rule = NgWordRule(pattern: 'abc');
      expect(rule.toString(), contains('abc'));
      expect(rule.toString(), contains('true'));
    });
  });
}
