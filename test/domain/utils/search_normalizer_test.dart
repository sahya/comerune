import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/search_normalizer.dart';

void main() {
  group('normalizeForSearch (Issue #472)', () {
    test('returns empty string unchanged', () {
      expect(normalizeForSearch(''), '');
    });

    test('lowercases ASCII', () {
      expect(normalizeForSearch('Hello WORLD'), 'hello world');
    });

    test('folds fullwidth ASCII to halfwidth', () {
      // ＡＢＣ１２３！? → abc123!? (then lowercased)
      expect(normalizeForSearch('ＡＢＣ１２３！？'), 'abc123!?');
    });

    test('folds ideographic space to ASCII space', () {
      expect(normalizeForSearch('ab\u3000cd'), 'ab cd');
    });

    test('folds halfwidth katakana to fullwidth katakana', () {
      // ｱｲｳｴｵ → アイウエオ
      expect(normalizeForSearch('ｱｲｳｴｵ'), 'アイウエオ');
    });

    test('composes halfwidth dakuten into voiced katakana', () {
      // ｶﾞｷﾞｸﾞｹﾞｺﾞ → ガギグゲゴ
      expect(normalizeForSearch('ｶﾞｷﾞｸﾞｹﾞｺﾞ'), 'ガギグゲゴ');
      // ｻﾞｼﾞｽﾞｾﾞｿﾞ → ザジズゼゾ
      expect(normalizeForSearch('ｻﾞｼﾞｽﾞｾﾞｿﾞ'), 'ザジズゼゾ');
      // ｳﾞ → ヴ (non-adjacent special case)
      expect(normalizeForSearch('ｳﾞ'), 'ヴ');
    });

    test('composes halfwidth handakuten into semi-voiced katakana', () {
      // ﾊﾟﾋﾟﾌﾟﾍﾟﾎﾟ → パピプペポ
      expect(normalizeForSearch('ﾊﾟﾋﾟﾌﾟﾍﾟﾎﾟ'), 'パピプペポ');
    });

    test('folds hiragana to katakana (仕様判断 A)', () {
      // Issue #472 選択: A（含める）
      expect(normalizeForSearch('こめんと'), normalizeForSearch('コメント'));
    });

    test('combined case: halfwidth kana + fullwidth alphanum + hiragana', () {
      // "ｱｲｳ ＡＢＣ こめんと" → "アイウ abc コメント"
      final String q = normalizeForSearch('ｱｲｳ ＡＢＣ こめんと');
      final String body = normalizeForSearch('アイウ abc コメント');
      expect(q, body);
    });

    test('preserves CJK characters unchanged', () {
      expect(normalizeForSearch('日本語'), '日本語');
      expect(normalizeForSearch('漢字テスト'), '漢字テスト');
    });

    test('halfwidth dakuten preserved when base does not take voicing', () {
      // ｱ (アが濁点化しない) + ﾞ → アﾞ (dakuten stays standalone)
      // Base "ア" cannot take dakuten, so the combining mark is emitted raw.
      final String out = normalizeForSearch('ｱﾞ');
      // Expect: base "ア" (U+30A2), then raw halfwidth dakuten (U+FF9E).
      expect(out.codeUnits, <int>[0x30A2, 0xFF9E]);
    });

    test(
      'trailing halfwidth dakuten (no following base char) is preserved',
      () {
        // A lone ﾞ at the end of a string must not cause an out-of-range
        // codeUnits access. It should simply pass through.
        expect(normalizeForSearch('ｶﾞﾞ').codeUnits.first, 0x30AC); // ガ
      },
    );

    test('hiragana combining dakuten stays as-is (out of fold range)', () {
      // Hiragana fold range is U+3041–U+3096. U+309B (゛) is NOT folded.
      // This test locks down that we do not accidentally rotate the
      // whole BMP — only the intended slice.
      expect(normalizeForSearch('\u309B'), '\u309B');
    });

    test('idempotent on already-normalized strings', () {
      final String once = normalizeForSearch('ＡＢＣ ｱｲｳ こめんと');
      expect(normalizeForSearch(once), once);
    });

    test('long input performance safeguard: linear in length', () {
      // Guards against accidental O(N^2) rewrites. Completes quickly.
      final String huge = 'ｱｲｳｴｵ' * 4000; // 20_000 codepoints
      final String result = normalizeForSearch(huge);
      expect(result.length, 20000);
      expect(result.codeUnits.first, 0x30A2); // ア
    });
  });
}
