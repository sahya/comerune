/// A single NG-word filtering rule with an enable/disable toggle.
///
/// Each rule holds a [pattern] string (plain text or regex) that is matched
/// against incoming comments. Disabled rules are stored but not applied.
class NgWordRule {
  final String pattern;
  final bool enabled;

  const NgWordRule({required this.pattern, this.enabled = true});

  Map<String, dynamic> toMap() => <String, dynamic>{
    'pattern': pattern,
    'enabled': enabled,
  };

  factory NgWordRule.fromMap(Map<String, dynamic> map) => NgWordRule(
    pattern: map['pattern'] as String,
    enabled: map['enabled'] as bool? ?? true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NgWordRule &&
          pattern == other.pattern &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(pattern, enabled);

  @override
  String toString() => 'NgWordRule(pattern: $pattern, enabled: $enabled)';
}

/// Returns the lower-cased, trimmed pattern strings of the enabled rules.
///
/// Mirrors the normalization performed by `AppSettings.ngWordList` so that
/// any caller — whether it reads the legacy global field or the
/// per-broadcaster snapshot — produces the same shape of `List<String>`
/// for downstream filter matching.
///
/// Filtering rules:
/// - `enabled == false` rules are dropped
/// - patterns are trimmed and lower-cased
/// - empty patterns (after trimming) are dropped
List<String> enabledNgWordPatterns(Iterable<NgWordRule> rules) {
  return rules
      .where((NgWordRule r) => r.enabled)
      .map((NgWordRule r) => r.pattern.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList();
}
