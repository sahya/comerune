import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/utils/unicode_sanitizer.dart';

void main() {
  group('removeControlAndInvisibleChars', () {
    test('preserves plain ASCII text unchanged', () {
      expect(removeControlAndInvisibleChars('hello world'), 'hello world');
    });

    test('preserves CJK and emoji unchanged', () {
      expect(removeControlAndInvisibleChars('運営コメント'), '運営コメント');
      expect(removeControlAndInvisibleChars('テスト🎉'), 'テスト🎉');
    });

    // --- C0 controls (U+0000-U+001F) ---
    test('strips C0 controls including CR, LF, TAB', () {
      expect(removeControlAndInvisibleChars('a\x00b'), 'ab');
      expect(removeControlAndInvisibleChars('a\nb'), 'ab');
      expect(removeControlAndInvisibleChars('a\rb'), 'ab');
      expect(removeControlAndInvisibleChars('a\tb'), 'ab');
      expect(removeControlAndInvisibleChars('a\x1Fb'), 'ab');
    });

    test('preserves U+0020 SPACE (not part of C0 range)', () {
      expect(removeControlAndInvisibleChars('a b'), 'a b');
    });

    // --- DEL + C1 controls (U+007F-U+009F) ---
    test('strips DEL and C1 controls', () {
      expect(removeControlAndInvisibleChars('a\x7Fb'), 'ab');
      expect(removeControlAndInvisibleChars('a\u0080b'), 'ab');
      expect(removeControlAndInvisibleChars('a\u009Fb'), 'ab');
    });

    // --- Non-breaking / fixed-width spaces (Issue #506) ---
    test('strips NO-BREAK SPACE (U+00A0)', () {
      expect(removeControlAndInvisibleChars('a\u00A0b'), 'ab');
    });

    test('strips FIGURE SPACE (U+2007)', () {
      expect(removeControlAndInvisibleChars('a\u2007b'), 'ab');
    });

    test('strips NARROW NO-BREAK SPACE (U+202F)', () {
      expect(removeControlAndInvisibleChars('a\u202Fb'), 'ab');
    });

    // --- Zero-width / format characters ---
    test('strips SOFT HYPHEN (U+00AD)', () {
      expect(removeControlAndInvisibleChars('a\u00ADb'), 'ab');
    });

    test('strips ARABIC LETTER MARK (U+061C)', () {
      expect(removeControlAndInvisibleChars('a\u061Cb'), 'ab');
    });

    test('strips MONGOLIAN VOWEL SEPARATOR (U+180E)', () {
      expect(removeControlAndInvisibleChars('a\u180Eb'), 'ab');
    });

    test('strips ZERO WIDTH SPACE (U+200B)', () {
      expect(removeControlAndInvisibleChars('a\u200Bb'), 'ab');
    });

    test('strips ZERO WIDTH NON-JOINER (U+200C)', () {
      expect(removeControlAndInvisibleChars('a\u200Cb'), 'ab');
    });

    test('preserves ZWJ (U+200D) for emoji composition', () {
      // Family emoji: man + ZWJ + woman + ZWJ + girl
      const String familyEmoji = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
      expect(removeControlAndInvisibleChars(familyEmoji), familyEmoji);
    });

    test('strips WORD JOINER (U+2060)', () {
      expect(removeControlAndInvisibleChars('a\u2060b'), 'ab');
    });

    test('strips invisible operators (U+2061-U+2064)', () {
      expect(removeControlAndInvisibleChars('a\u2061b'), 'ab');
      expect(removeControlAndInvisibleChars('a\u2064b'), 'ab');
    });

    // --- Line / paragraph separators ---
    test('strips LINE SEPARATOR (U+2028) and PARAGRAPH SEPARATOR (U+2029)', () {
      expect(removeControlAndInvisibleChars('a\u2028b'), 'ab');
      expect(removeControlAndInvisibleChars('a\u2029b'), 'ab');
    });

    // --- Bidi overrides (Trojan Source defense) ---
    test('strips bidi overrides LRE/RLE/PDF/LRO/RLO (U+202A-U+202E)', () {
      expect(removeControlAndInvisibleChars('a\u202Ab'), 'ab'); // LRE
      expect(removeControlAndInvisibleChars('a\u202Bb'), 'ab'); // RLE
      expect(removeControlAndInvisibleChars('a\u202Cb'), 'ab'); // PDF
      expect(removeControlAndInvisibleChars('a\u202Db'), 'ab'); // LRO
      expect(removeControlAndInvisibleChars('a\u202Eb'), 'ab'); // RLO
    });

    test('strips isolate controls LRI/RLI/FSI/PDI (U+2066-U+2069)', () {
      expect(removeControlAndInvisibleChars('a\u2066b'), 'ab'); // LRI
      expect(removeControlAndInvisibleChars('a\u2067b'), 'ab'); // RLI
      expect(removeControlAndInvisibleChars('a\u2068b'), 'ab'); // FSI
      expect(removeControlAndInvisibleChars('a\u2069b'), 'ab'); // PDI
    });

    // --- Tag Characters (U+E0000-U+E007F) ---
    test('strips Tag Characters (Trojan Source defense)', () {
      // U+E0001 (LANGUAGE TAG)
      expect(removeControlAndInvisibleChars('a\u{E0001}b'), 'ab');
      // U+E007F (CANCEL TAG)
      expect(removeControlAndInvisibleChars('a\u{E007F}b'), 'ab');
    });

    // --- Preserved: Variation Selectors ---
    test('preserves variation selectors (U+FE00-U+FE0F)', () {
      // Text presentation selector for emoji
      const String withVS = '\u2764\uFE0F'; // heart + VS16 (emoji form)
      expect(removeControlAndInvisibleChars(withVS), withVS);
    });

    test('preserves Variation Selectors Supplement (U+E0100-U+E01EF)', () {
      // U+E0100 is outside the Tag Characters range and must be preserved.
      final String withVSS = 'a${String.fromCharCode(0xE0100)}b';
      expect(removeControlAndInvisibleChars(withVSS), withVSS);
    });

    // --- Miscellaneous invisible characters ---
    test('strips HANGUL CHOSEONG FILLER (U+115F)', () {
      expect(removeControlAndInvisibleChars('a\u115Fb'), 'ab');
    });

    test('strips HANGUL JUNGSEONG FILLER (U+1160)', () {
      expect(removeControlAndInvisibleChars('a\u1160b'), 'ab');
    });

    test('strips HANGUL FILLER (U+3164)', () {
      expect(removeControlAndInvisibleChars('a\u3164b'), 'ab');
    });

    test('strips BOM / ZERO WIDTH NO-BREAK SPACE (U+FEFF)', () {
      expect(removeControlAndInvisibleChars('a\uFEFFb'), 'ab');
    });

    test('strips interlinear annotation anchors (U+FFF9-U+FFFB)', () {
      expect(removeControlAndInvisibleChars('a\uFFF9b'), 'ab');
      expect(removeControlAndInvisibleChars('a\uFFFBb'), 'ab');
    });

    // --- Attack patterns ---
    test('strips multiple mixed invisible characters in one string', () {
      // Simulates a display-spoofing attack: "運営" + bidi + NBSP + tag char
      final String attack = '運営\u202E\u00A0\u200B\u{E0001}コメント';
      expect(removeControlAndInvisibleChars(attack), '運営コメント');
    });

    test('returns empty string when input is all invisible characters', () {
      expect(removeControlAndInvisibleChars('\u200B\u200C\u2060\u00A0'), '');
    });

    test('handles empty string', () {
      expect(removeControlAndInvisibleChars(''), '');
    });
  });
}
