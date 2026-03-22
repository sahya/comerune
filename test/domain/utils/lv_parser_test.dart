import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/utils/lv_parser.dart';

void main() {
  test('returns lv when input is lv string', () {
    expect(LvParser.extract('lv345678901'), 'lv345678901');
  });

  test('returns lv when input is watch URL', () {
    expect(
      LvParser.extract('https://live.nicovideo.jp/watch/lv345678901'),
      'lv345678901',
    );
  });

  test('returns null when input does not include lv', () {
    expect(LvParser.extract('invalid'), isNull);
  });

  test('returns first match when there are multiple lv values', () {
    expect(
      LvParser.extract('lv111111111 and lv222222222'),
      'lv111111111',
    );
  });

  test('returns null when input is null', () {
    expect(LvParser.extract(null), isNull);
  });

  test('returns null when input is empty string', () {
    expect(LvParser.extract(''), isNull);
  });
}
