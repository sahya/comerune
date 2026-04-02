import 'package:comerune/domain/utils/nico_icon_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildNicoIconUrl', () {
    test('returns null for null value', () {
      expect(buildNicoIconUrl(null), isNull);
    });

    test('returns null for empty value', () {
      expect(buildNicoIconUrl(''), isNull);
    });

    test('returns null for non numeric value', () {
      expect(buildNicoIconUrl('ch2648853'), isNull);
    });

    test('builds icon URL from numeric user id', () {
      expect(
        buildNicoIconUrl('18897569'),
        'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/1889/18897569.jpg',
      );
    });
  });
}
