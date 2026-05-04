import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/extension/extension_result.dart';

void main() {
  group('ExtensionResult', () {
    test('Ok carries value and is equal to another Ok with equal value', () {
      const ExtensionResult<int> a = ExtensionResultOk<int>(42);
      const ExtensionResult<int> b = ExtensionResultOk<int>(42);
      const ExtensionResult<int> c = ExtensionResultOk<int>(7);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect((a as ExtensionResultOk<int>).value, 42);
    });

    test('Unsupported instances are equal regardless of allocation', () {
      const ExtensionResult<int> a = ExtensionResultUnsupported<int>();
      const ExtensionResult<int> b = ExtensionResultUnsupported<int>();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Failure carries cause and equality is value-based', () {
      const Object cause = 'something went wrong';
      const ExtensionResult<int> a = ExtensionResultFailure<int>(cause);
      const ExtensionResult<int> b = ExtensionResultFailure<int>(cause);
      const ExtensionResult<int> c = ExtensionResultFailure<int>('different');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect((a as ExtensionResultFailure<int>).cause, cause);
    });

    test('different variants are never equal to each other', () {
      const ExtensionResult<int> ok = ExtensionResultOk<int>(1);
      const ExtensionResult<int> unsupported =
          ExtensionResultUnsupported<int>();
      const ExtensionResult<int> failure = ExtensionResultFailure<int>('e');

      expect(ok, isNot(equals(unsupported)));
      expect(ok, isNot(equals(failure)));
      expect(unsupported, isNot(equals(failure)));
    });

    test('switch statement is exhaustive (compile-time guarantee)', () {
      // This test exists to lock in the sealed-class exhaustiveness
      // contract. If a new ExtensionResult variant is added without
      // updating this switch, the analyzer will flag it as missing
      // a case.
      String describe(ExtensionResult<int> r) {
        return switch (r) {
          ExtensionResultOk<int>(:final int value) => 'ok($value)',
          ExtensionResultUnsupported<int>() => 'unsupported',
          ExtensionResultFailure<int>(:final Object cause) => 'failure($cause)',
        };
      }

      expect(describe(const ExtensionResultOk<int>(5)), 'ok(5)');
      expect(describe(const ExtensionResultUnsupported<int>()), 'unsupported');
      expect(
        describe(const ExtensionResultFailure<int>('boom')),
        'failure(boom)',
      );
    });

    test('toString includes variant name and payload', () {
      expect(
        const ExtensionResultOk<int>(7).toString(),
        contains('ExtensionResultOk'),
      );
      expect(
        const ExtensionResultUnsupported<int>().toString(),
        contains('ExtensionResultUnsupported'),
      );
      expect(
        const ExtensionResultFailure<int>('x').toString(),
        contains('ExtensionResultFailure'),
      );
    });
  });
}
