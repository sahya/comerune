/// Parses a newline-separated string into a [Set] of trimmed, non-empty values.
Set<String> parseNewlineSeparatedSet(String raw) {
  if (raw.trim().isEmpty) {
    return const <String>{};
  }
  return raw
      .split('\n')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toSet();
}

/// Parses a newline-separated string into a [List] of trimmed, non-empty,
/// lower-cased values.
List<String> parseNewlineSeparatedLowerList(String raw) {
  if (raw.trim().isEmpty) {
    return const <String>[];
  }
  return raw
      .split('\n')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .map((String s) => s.toLowerCase())
      .toList();
}
