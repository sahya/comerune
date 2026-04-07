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
