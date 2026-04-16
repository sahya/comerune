/// Search-oriented text normalization (Issue #472).
///
/// Implements a lightweight NFKC-style normalization sufficient for the
/// comment keyword search feature on a Japanese UGC platform, without
/// pulling in any new dependency:
///
///   1. Fullwidth ASCII (U+FF01–U+FF5E) → halfwidth ASCII.
///   2. Ideographic space (U+3000) → ASCII space.
///   3. Halfwidth katakana (U+FF61–U+FF9F) → fullwidth katakana, composing
///      any trailing halfwidth dakuten (U+FF9E) / handakuten (U+FF9F) into
///      the single-codepoint voiced / semi-voiced fullwidth katakana.
///   4. Hiragana (U+3041–U+3096) → Katakana (+0x60).
///      Rationale (「仕様判断」of Issue #472, option A): in Japanese UGC
///      users often type the same word in either kana script, so folding
///      hiragana into katakana gives significantly more natural matches
///      ("こめんと" should find "コメント"). The marginal risk of
///      "unintended hits" (e.g. homophones in different scripts) is
///      accepted for the UX gain.
///   5. ASCII lowercasing is applied at the end so the caller no longer
///      needs a separate [String.toLowerCase] step.
///
/// This is NOT a full NFKC implementation; it intentionally targets the
/// character classes that drive search misses on this app (see the
/// acceptance criteria in Issue #472). If we ever need full NFKC we can
/// swap this for a proper package-based implementation without changing
/// call sites.
String normalizeForSearch(String input) {
  if (input.isEmpty) return input;

  final StringBuffer out = StringBuffer();
  final List<int> codes = input.codeUnits;
  final int length = codes.length;
  int i = 0;

  while (i < length) {
    final int c = codes[i];

    // 1. Fullwidth ASCII (！-～) → halfwidth (!-~).
    if (c >= 0xFF01 && c <= 0xFF5E) {
      out.writeCharCode(c - 0xFEE0);
      i += 1;
      continue;
    }

    // 2. Ideographic space → ASCII space.
    if (c == 0x3000) {
      out.writeCharCode(0x20);
      i += 1;
      continue;
    }

    // 3. Halfwidth katakana → fullwidth katakana, composing marks.
    if (c >= 0xFF61 && c <= 0xFF9F) {
      final int? base = _kHalfToFullKana[c];
      if (base != null) {
        final int next = i + 1 < length ? codes[i + 1] : 0;
        int composed = base;
        if (next == 0xFF9E) {
          final int? voiced = _applyDakuten(base);
          if (voiced != null) {
            composed = voiced;
            i += 1; // consume combining mark
          }
        } else if (next == 0xFF9F) {
          final int? semi = _applyHandakuten(base);
          if (semi != null) {
            composed = semi;
            i += 1; // consume combining mark
          }
        }
        // 4a. Halfwidth-originating katakana participates in
        //     hira→kata folding below only indirectly (they are already
        //     katakana), so just emit and continue.
        out.writeCharCode(composed);
        i += 1;
        continue;
      }
      // Unknown halfwidth kana code point: fall through and emit raw.
    }

    // 4. Hiragana → Katakana (fold within JIS X 0208 range only).
    if (c >= 0x3041 && c <= 0x3096) {
      out.writeCharCode(c + 0x60);
      i += 1;
      continue;
    }

    out.writeCharCode(c);
    i += 1;
  }

  // 5. Case-fold ASCII at the end. We deliberately keep the rest of the
  //    string untouched (Japanese has no case concept) and rely on the
  //    caller to provide trimmed input when that is desired.
  return out.toString().toLowerCase();
}

// -----------------------------------------------------------------------------
// Internal tables
// -----------------------------------------------------------------------------

/// Halfwidth katakana (U+FF61–U+FF9D) → base fullwidth katakana mapping.
/// Source: Unicode compatibility decompositions (NFKD). The combining
/// dakuten (U+FF9E) / handakuten (U+FF9F) are handled by the caller via
/// [_applyDakuten] / [_applyHandakuten].
const Map<int, int> _kHalfToFullKana = <int, int>{
  0xFF61: 0x3002, // ｡ → 。
  0xFF62: 0x300C, // ｢ → 「
  0xFF63: 0x300D, // ｣ → 」
  0xFF64: 0x3001, // ､ → 、
  0xFF65: 0x30FB, // ･ → ・
  0xFF66: 0x30F2, // ｦ → ヲ
  0xFF67: 0x30A1, // ｧ → ァ
  0xFF68: 0x30A3, // ｨ → ィ
  0xFF69: 0x30A5, // ｩ → ゥ
  0xFF6A: 0x30A7, // ｪ → ェ
  0xFF6B: 0x30A9, // ｫ → ォ
  0xFF6C: 0x30E3, // ｬ → ャ
  0xFF6D: 0x30E5, // ｭ → ュ
  0xFF6E: 0x30E7, // ｮ → ョ
  0xFF6F: 0x30C3, // ｯ → ッ
  0xFF70: 0x30FC, // ｰ → ー
  0xFF71: 0x30A2, // ｱ → ア
  0xFF72: 0x30A4, // ｲ → イ
  0xFF73: 0x30A6, // ｳ → ウ
  0xFF74: 0x30A8, // ｴ → エ
  0xFF75: 0x30AA, // ｵ → オ
  0xFF76: 0x30AB, // ｶ → カ
  0xFF77: 0x30AD, // ｷ → キ
  0xFF78: 0x30AF, // ｸ → ク
  0xFF79: 0x30B1, // ｹ → ケ
  0xFF7A: 0x30B3, // ｺ → コ
  0xFF7B: 0x30B5, // ｻ → サ
  0xFF7C: 0x30B7, // ｼ → シ
  0xFF7D: 0x30B9, // ｽ → ス
  0xFF7E: 0x30BB, // ｾ → セ
  0xFF7F: 0x30BD, // ｿ → ソ
  0xFF80: 0x30BF, // ﾀ → タ
  0xFF81: 0x30C1, // ﾁ → チ
  0xFF82: 0x30C4, // ﾂ → ツ
  0xFF83: 0x30C6, // ﾃ → テ
  0xFF84: 0x30C8, // ﾄ → ト
  0xFF85: 0x30CA, // ﾅ → ナ
  0xFF86: 0x30CB, // ﾆ → ニ
  0xFF87: 0x30CC, // ﾇ → ヌ
  0xFF88: 0x30CD, // ﾈ → ネ
  0xFF89: 0x30CE, // ﾉ → ノ
  0xFF8A: 0x30CF, // ﾊ → ハ
  0xFF8B: 0x30D2, // ﾋ → ヒ
  0xFF8C: 0x30D5, // ﾌ → フ
  0xFF8D: 0x30D8, // ﾍ → ヘ
  0xFF8E: 0x30DB, // ﾎ → ホ
  0xFF8F: 0x30DE, // ﾏ → マ
  0xFF90: 0x30DF, // ﾐ → ミ
  0xFF91: 0x30E0, // ﾑ → ム
  0xFF92: 0x30E1, // ﾒ → メ
  0xFF93: 0x30E2, // ﾓ → モ
  0xFF94: 0x30E4, // ﾔ → ヤ
  0xFF95: 0x30E6, // ﾕ → ユ
  0xFF96: 0x30E8, // ﾖ → ヨ
  0xFF97: 0x30E9, // ﾗ → ラ
  0xFF98: 0x30EA, // ﾘ → リ
  0xFF99: 0x30EB, // ﾙ → ル
  0xFF9A: 0x30EC, // ﾚ → レ
  0xFF9B: 0x30ED, // ﾛ → ロ
  0xFF9C: 0x30EF, // ﾜ → ワ
  0xFF9D: 0x30F3, // ﾝ → ン
};

/// Returns the voiced (dakuten) fullwidth katakana for [base], or `null`
/// when no such voiced form exists (in which case the trailing
/// halfwidth dakuten is preserved as a standalone character by the
/// caller).
int? _applyDakuten(int base) {
  // Special case: ウ (U+30A6) → ヴ (U+30F4) is NOT adjacent in Unicode.
  if (base == 0x30A6) return 0x30F4;
  switch (base) {
    case 0x30AB: // カ→ガ
    case 0x30AD: // キ→ギ
    case 0x30AF: // ク→グ
    case 0x30B1: // ケ→ゲ
    case 0x30B3: // コ→ゴ
    case 0x30B5: // サ→ザ
    case 0x30B7: // シ→ジ
    case 0x30B9: // ス→ズ
    case 0x30BB: // セ→ゼ
    case 0x30BD: // ソ→ゾ
    case 0x30BF: // タ→ダ
    case 0x30C1: // チ→ヂ
    case 0x30C4: // ツ→ヅ
    case 0x30C6: // テ→デ
    case 0x30C8: // ト→ド
    case 0x30CF: // ハ→バ
    case 0x30D2: // ヒ→ビ
    case 0x30D5: // フ→ブ
    case 0x30D8: // ヘ→ベ
    case 0x30DB: // ホ→ボ
      return base + 1;
  }
  return null;
}

/// Returns the semi-voiced (handakuten) fullwidth katakana for [base],
/// or `null` when no such semi-voiced form exists.
int? _applyHandakuten(int base) {
  switch (base) {
    case 0x30CF: // ハ→パ
    case 0x30D2: // ヒ→ピ
    case 0x30D5: // フ→プ
    case 0x30D8: // ヘ→ペ
    case 0x30DB: // ホ→ポ
      return base + 2;
  }
  return null;
}
