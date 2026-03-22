class LvParser {
  static final RegExp _pattern = RegExp(r'lv\d+');

  static String? extract(String? input) {
    if (input == null || input.isEmpty) {
      return null;
    }

    final RegExpMatch? match = _pattern.firstMatch(input);
    return match?.group(0);
  }
}
