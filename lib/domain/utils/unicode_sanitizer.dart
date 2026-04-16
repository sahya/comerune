/// Unicode sanitisation helpers shared between presentation (snackbar labels)
/// and domain (operator-supplied names).
///
/// The purpose of the helper is to strip code points that can:
///   - inject visual line breaks (CR / LF / LINE SEPARATOR / PARAGRAPH SEPARATOR)
///   - invisibly spoof the direction of the rendered text (bidi overrides /
///     isolate controls / Arabic Letter Mark / Mongolian Vowel Separator)
///   - smuggle hidden payloads inside glyphs (Tag Characters, Trojan Source)
///   - leak other zero-width / control characters that break layout.
///
/// The helper deliberately preserves:
///   - ZWJ (U+200D): required to keep ZWJ-composed emoji sequences
///     (family, profession, flag, etc.) as a single glyph in display.
///   - Variation selectors (U+FE00-U+FE0F, U+E0100-U+E01EF): required
///     to keep emoji presentation selectors intact.
///
/// Input is processed in Unicode code points via [String.runes] so that
/// surrogate pairs are never split mid-codepoint.
String removeControlAndInvisibleChars(String text) {
  final StringBuffer sb = StringBuffer();
  for (final int cp in text.runes) {
    if (_isInvisibleOrControl(cp)) {
      continue;
    }
    sb.writeCharCode(cp);
  }
  return sb.toString();
}

bool _isInvisibleOrControl(int cp) {
  // C0 controls (U+0000-U+001F) — includes CR / LF / TAB. The caller is
  // responsible for re-inserting whitespace (e.g. collapse to single space)
  // when it needs to preserve word boundaries for display.
  if (cp >= 0x0000 && cp <= 0x001F) return true;
  // DEL + C1 controls (U+007F-U+009F)
  if (cp >= 0x007F && cp <= 0x009F) return true;

  // Zero-width / format characters that can hide payload.
  if (cp == 0x00AD) return true; // SOFT HYPHEN
  if (cp == 0x061C) return true; // ARABIC LETTER MARK
  if (cp == 0x115F) return true; // HANGUL CHOSEONG FILLER
  if (cp == 0x1160) return true; // HANGUL JUNGSEONG FILLER
  if (cp == 0x17B4) return true; // KHMER VOWEL INHERENT AQ
  if (cp == 0x17B5) return true; // KHMER VOWEL INHERENT AA
  if (cp == 0x180E) return true; // MONGOLIAN VOWEL SEPARATOR
  if (cp == 0x200B) return true; // ZERO WIDTH SPACE
  if (cp == 0x200C) return true; // ZERO WIDTH NON-JOINER
  // Note: ZWJ (U+200D) is intentionally preserved for emoji composition.
  // Isolated ZWJ at word boundaries has been used for homoglyph tricks in
  // chat apps, but removing it would break every family / profession /
  // flag emoji, which has a much higher user impact. Kept as-is.
  // WORD JOINER + invisible operators — zero-width, used by Trojan Source
  // and homoglyph attacks. Not part of emoji composition.
  if (cp == 0x2060) return true; // WORD JOINER
  if (cp >= 0x2061 && cp <= 0x2064) return true; // invisible operators
  // Interlinear annotation anchors / separators / terminators — invisible
  // in most renderers and usable as hidden payload.
  if (cp >= 0xFFF9 && cp <= 0xFFFB) return true;
  if (cp == 0xFEFF) return true; // ZERO WIDTH NO-BREAK SPACE / BOM
  if (cp == 0x3164) return true; // HANGUL FILLER — "invisible full-width"

  // Line / paragraph separators — can inject line breaks in UI.
  if (cp == 0x2028 || cp == 0x2029) return true;

  // Bidi overrides (LRE/RLE/PDF/LRO/RLO) — Trojan Source / RTL spoofing.
  if (cp >= 0x202A && cp <= 0x202E) return true;
  // Isolate controls (LRI/RLI/FSI/PDI).
  if (cp >= 0x2066 && cp <= 0x2069) return true;

  // Tag Characters (U+E0000-U+E007F) — Trojan Source defense.
  // Note: Variation Selectors Supplement (U+E0100-U+E01EF) are *outside*
  // this range and intentionally preserved for emoji presentation selectors.
  if (cp >= 0xE0000 && cp <= 0xE007F) return true;

  return false;
}
