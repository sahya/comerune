import '../utils/unicode_sanitizer.dart';

/// NG word detection-specific text normalizer.
///
/// Produces the canonical matching form used by [NgMatcher] on both the
/// display (comment list) and speech (TTS) axes. The implementation must
/// stay behavior-compatible with the Kotlin-side
/// `com.example.comerune.speech.domain.normalizer.NgWordTextNormalizer`
/// so that display-side and speech-side filtering agree on what text
/// matches a given NG word; if either side changes, the other must be
/// updated in the same PR.
///
/// Directory note: this package (`domain/normalizers/`) hosts *matching-form*
/// normalizers whose output is compared byte-for-byte against a normalized
/// NG-word list. That is distinct from `domain/normalization/`, which holds
/// *message-shape* normalizers (e.g. `message_normalizer.dart`) that
/// restructure raw chat payloads into app-facing models. New matching-form
/// helpers belong here; new message-shape helpers belong in
/// `domain/normalization/`.
///
/// Processing order (step order matters — the look-alike table assumes
/// ASCII/katakana have already been folded; the duplicate compression
/// assumes symbols have been stripped):
///   1. full-width ASCII → half-width ASCII (plus U+3000 ideographic space)
///   2. half-width katakana → full-width katakana (with voiced / semi-voiced
///      combining pair handling)
///   3. control / invisible / variation-selector / bidi removal
///   4. visual look-alike kanji → katakana
///   5. katakana → hiragana
///   6. ASCII lowercase
///   7. strip whitespace and symbols (keep letters / digits / CJK)
///   8. compress any run of 3+ identical code points down to 2
String normalizeNgWordText(String text) {
  String result = text;
  result = _normalizeFullWidthAscii(result);
  result = _normalizeHalfWidthKatakana(result);
  result = removeControlAndInvisibleChars(result);
  result = _applyLookAlikeTable(result);
  result = _katakanaToHiragana(result);
  result = result.toLowerCase();
  result = _removeSpacesAndSymbols(result);
  result = _compressDuplicates(result);
  return result;
}

String _normalizeFullWidthAscii(String text) {
  final StringBuffer sb = StringBuffer();
  for (final int cp in text.runes) {
    if (cp == 0x3000) {
      sb.write(' ');
    } else if (cp >= 0xFF10 && cp <= 0xFF19) {
      sb.writeCharCode(cp - 0xFEE0);
    } else if (cp >= 0xFF21 && cp <= 0xFF3A) {
      sb.writeCharCode(cp - 0xFEE0);
    } else if (cp >= 0xFF41 && cp <= 0xFF5A) {
      sb.writeCharCode(cp - 0xFEE0);
    } else {
      sb.writeCharCode(cp);
    }
  }
  return sb.toString();
}

String _normalizeHalfWidthKatakana(String text) {
  if (text.isEmpty) {
    return text;
  }
  const Map<String, String> map = <String, String>{
    'ｱ': 'ア',
    'ｲ': 'イ',
    'ｳ': 'ウ',
    'ｴ': 'エ',
    'ｵ': 'オ',
    'ｶ': 'カ',
    'ｷ': 'キ',
    'ｸ': 'ク',
    'ｹ': 'ケ',
    'ｺ': 'コ',
    'ｻ': 'サ',
    'ｼ': 'シ',
    'ｽ': 'ス',
    'ｾ': 'セ',
    'ｿ': 'ソ',
    'ﾀ': 'タ',
    'ﾁ': 'チ',
    'ﾂ': 'ツ',
    'ﾃ': 'テ',
    'ﾄ': 'ト',
    'ﾅ': 'ナ',
    'ﾆ': 'ニ',
    'ﾇ': 'ヌ',
    'ﾈ': 'ネ',
    'ﾉ': 'ノ',
    'ﾊ': 'ハ',
    'ﾋ': 'ヒ',
    'ﾌ': 'フ',
    'ﾍ': 'ヘ',
    'ﾎ': 'ホ',
    'ﾏ': 'マ',
    'ﾐ': 'ミ',
    'ﾑ': 'ム',
    'ﾒ': 'メ',
    'ﾓ': 'モ',
    'ﾔ': 'ヤ',
    'ﾕ': 'ユ',
    'ﾖ': 'ヨ',
    'ﾗ': 'ラ',
    'ﾘ': 'リ',
    'ﾙ': 'ル',
    'ﾚ': 'レ',
    'ﾛ': 'ロ',
    'ﾜ': 'ワ',
    'ｦ': 'ヲ',
    'ﾝ': 'ン',
    'ｧ': 'ァ',
    'ｨ': 'ィ',
    'ｩ': 'ゥ',
    'ｪ': 'ェ',
    'ｫ': 'ォ',
    'ｯ': 'ッ',
    'ｬ': 'ャ',
    'ｭ': 'ュ',
    'ｮ': 'ョ',
    'ｰ': 'ー',
  };
  const Map<String, String> voiced = <String, String>{
    'ｳ': 'ヴ',
    'ｶ': 'ガ',
    'ｷ': 'ギ',
    'ｸ': 'グ',
    'ｹ': 'ゲ',
    'ｺ': 'ゴ',
    'ｻ': 'ザ',
    'ｼ': 'ジ',
    'ｽ': 'ズ',
    'ｾ': 'ゼ',
    'ｿ': 'ゾ',
    'ﾀ': 'ダ',
    'ﾁ': 'ヂ',
    'ﾂ': 'ヅ',
    'ﾃ': 'デ',
    'ﾄ': 'ド',
    'ﾊ': 'バ',
    'ﾋ': 'ビ',
    'ﾌ': 'ブ',
    'ﾍ': 'ベ',
    'ﾎ': 'ボ',
    'ﾜ': 'ヷ',
    'ｦ': 'ヺ',
  };
  const Map<String, String> semiVoiced = <String, String>{
    'ﾊ': 'パ',
    'ﾋ': 'ピ',
    'ﾌ': 'プ',
    'ﾍ': 'ペ',
    'ﾎ': 'ポ',
  };
  final List<String> chars = text.split('');
  final StringBuffer sb = StringBuffer();
  int i = 0;
  while (i < chars.length) {
    final String ch = chars[i];
    final String? next = i + 1 < chars.length ? chars[i + 1] : null;
    if (next == 'ﾞ') {
      final String? combined = voiced[ch];
      if (combined != null) {
        sb.write(combined);
        i += 2;
        continue;
      }
    } else if (next == 'ﾟ') {
      final String? combined = semiVoiced[ch];
      if (combined != null) {
        sb.write(combined);
        i += 2;
        continue;
      }
    }
    sb.write(map[ch] ?? ch);
    i++;
  }
  return sb.toString();
}

String _applyLookAlikeTable(String text) {
  const Map<String, String> lookAlike = <String, String>{
    '工': 'エ',
    '口': 'ロ',
    '冂': 'ロ',
    '力': 'カ',
    '夕': 'タ',
    '二': 'ニ',
    '卜': 'ト',
    '八': 'ハ',
    '千': 'チ',
    '十': 'ジ',
    '人': 'ヒ',
    '入': 'イ',
    '匕': 'ヒ',
    '乃': 'ノ',
    '又': 'マ',
    '丁': 'テ',
    '己': 'コ',
    '匚': 'コ',
    '巳': 'ミ',
    '也': 'ヤ',
    '刀': 'カ',
  };
  return text.split('').map((String ch) => lookAlike[ch] ?? ch).join();
}

String _katakanaToHiragana(String text) {
  final StringBuffer sb = StringBuffer();
  for (final int cp in text.runes) {
    if (cp >= 0x30A1 && cp <= 0x30F6) {
      sb.writeCharCode(cp - 0x60);
    } else if (cp == 0x30F7) {
      sb.write('わ');
    } else if (cp == 0x30F8) {
      sb.write('ゐ');
    } else if (cp == 0x30F9) {
      sb.write('ゑ');
    } else if (cp == 0x30FA) {
      sb.write('を');
    } else {
      sb.writeCharCode(cp);
    }
  }
  return sb.toString();
}

String _removeSpacesAndSymbols(String text) {
  final StringBuffer sb = StringBuffer();
  for (final int cp in text.runes) {
    if (_isLetterOrDigitCodePoint(cp)) {
      sb.writeCharCode(cp);
    }
  }
  return sb.toString();
}

bool _isLetterOrDigitCodePoint(int cp) {
  final bool asciiAlphaNum =
      (cp >= 0x30 && cp <= 0x39) ||
      (cp >= 0x41 && cp <= 0x5A) ||
      (cp >= 0x61 && cp <= 0x7A);
  if (asciiAlphaNum) {
    return true;
  }
  final bool fullWidthAlphaNum =
      (cp >= 0xFF10 && cp <= 0xFF19) ||
      (cp >= 0xFF21 && cp <= 0xFF3A) ||
      (cp >= 0xFF41 && cp <= 0xFF5A);
  if (fullWidthAlphaNum) {
    return true;
  }
  final bool jpLetters = (cp >= 0x3040 && cp <= 0x30FF);
  if (jpLetters) {
    return true;
  }
  final bool cjk = (cp >= 0x3400 && cp <= 0x9FFF);
  return cjk;
}

String _compressDuplicates(String text) {
  if (text.length < 3) {
    return text;
  }
  final List<int> codePoints = text.runes.toList(growable: false);
  if (codePoints.length < 3) {
    return text;
  }
  final StringBuffer sb = StringBuffer();
  int i = 0;
  while (i < codePoints.length) {
    final int cp = codePoints[i];
    int count = 1;
    int j = i + 1;
    while (j < codePoints.length && codePoints[j] == cp) {
      count++;
      j++;
    }
    final int output = count > 2 ? 2 : count;
    for (int k = 0; k < output; k++) {
      sb.writeCharCode(cp);
    }
    i = j;
  }
  return sb.toString();
}
