import 'package:comerune/domain/models/ng_display_subcategory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NgDisplaySubcategory', () {
    test('wireName round-trips for every value', () {
      for (final NgDisplaySubcategory value in NgDisplaySubcategory.values) {
        expect(NgDisplaySubcategory.tryParse(value.wireName), value);
      }
    });

    test('wireName matches the documented strings', () {
      expect(NgDisplaySubcategory.violence.wireName, 'violence');
      expect(NgDisplaySubcategory.sexual.wireName, 'sexual');
      expect(NgDisplaySubcategory.discrimination.wireName, 'discrimination');
      expect(NgDisplaySubcategory.minors.wireName, 'minors');
    });

    test('tryParse returns null for null input', () {
      expect(NgDisplaySubcategory.tryParse(null), isNull);
    });

    test('tryParse returns null for unknown strings', () {
      expect(NgDisplaySubcategory.tryParse(''), isNull);
      expect(NgDisplaySubcategory.tryParse('violent'), isNull); // typo
      expect(
        NgDisplaySubcategory.tryParse('VIOLENCE'),
        isNull,
      ); // case sensitive
      expect(NgDisplaySubcategory.tryParse(' minors '), isNull); // not trimmed
      expect(NgDisplaySubcategory.tryParse('other'), isNull);
    });

    test('values has exactly 4 entries (regression guard for UI toggles)', () {
      expect(NgDisplaySubcategory.values.length, 4);
    });
  });
}
