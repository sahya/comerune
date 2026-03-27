class LvParser {
  static const int _maxLvDigits = 18;
  static const int _maxLvLength = 2 + _maxLvDigits;
  static final RegExp _pattern = RegExp(r'lv\d{1,18}(?!\d)');

  static String? extract(String? input) {
    if (input == null || input.isEmpty) {
      return null;
    }

    final RegExpMatch? match = _pattern.firstMatch(input);
    if (match == null) {
      return null;
    }

    final String? candidate = match.group(0);
    if (candidate == null || candidate.length > _maxLvLength) {
      return null;
    }

    return candidate;
  }
}
