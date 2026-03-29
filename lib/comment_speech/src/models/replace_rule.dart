/// A text replacement rule applied during comment normalization.
class ReplaceRule {
  final String pattern;
  final String replacement;
  final bool enabled;

  const ReplaceRule({
    required this.pattern,
    required this.replacement,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => {
        'pattern': pattern,
        'replacement': replacement,
        'enabled': enabled,
      };

  factory ReplaceRule.fromMap(Map<String, dynamic> map) => ReplaceRule(
        pattern: map['pattern'] as String,
        replacement: map['replacement'] as String,
        enabled: map['enabled'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplaceRule &&
          pattern == other.pattern &&
          replacement == other.replacement &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(pattern, replacement, enabled);
}
