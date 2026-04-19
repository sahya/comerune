import 'ng_display_subcategory.dart';
import 'ng_policy.dart';

/// Structured representation of a single preset NG-word category loaded from
/// `preset_ng_words.json` (schema v3).
///
/// This is an immutable value object. Parsing is implemented as pure static
/// functions so that the parsing logic is unit-testable without any file IO.
///
/// For forward compatibility the parser is deliberately permissive:
/// * missing `policy` -> [NgPolicy.defaultPolicy]
/// * unknown `policy` -> [NgPolicy.defaultPolicy]
/// * missing / null / unknown `displaySubcategory` -> null on the model
///   (caller treats it as "not shown in display toggles")
/// * `words` missing, not a list, or containing non-string entries -> those
///   entries are skipped. A fully invalid category is skipped entirely.
class NgPresetCategory {
  /// Stable identifier (the JSON category key, e.g. `criminal_incitement`).
  final String id;

  /// Optional human-readable description (primarily for documentation).
  final String description;

  /// Policy that applies when any of the [words] matches a comment. For v1
  /// every preset category uses [NgPolicy.blockSpeechOnly].
  final NgPolicy policy;

  /// Optional display categorization used by the future UI toggles.
  /// Null means "not classified" and the category should be skipped by the
  /// display-side filtering, but still participate in speech filtering.
  final NgDisplaySubcategory? displaySubcategory;

  /// The NG words belonging to this category. Already trimmed and deduplicated
  /// within the category. Matching-side normalization is performed elsewhere.
  final List<String> words;

  const NgPresetCategory({
    required this.id,
    required this.description,
    required this.policy,
    required this.displaySubcategory,
    required this.words,
  });

  /// Parses the full preset NG words document.
  ///
  /// Accepts any [Object] so that callers can forward the raw `jsonDecode`
  /// result without casting. Any structural problem results in an empty list
  /// rather than an exception; malformed individual categories are skipped.
  ///
  /// Supports:
  /// * v3: each category has an explicit `policy` and `displaySubcategory`.
  /// * v2 (and missing `version`): each category is treated as
  ///   [NgPolicy.blockSpeechOnly] with `displaySubcategory = null`, which
  ///   preserves the pre-v3 behavior (speech-only filtering, no display
  ///   toggles).
  static List<NgPresetCategory> parseDocument(Object? decoded) {
    if (decoded is! Map) {
      return const <NgPresetCategory>[];
    }
    final Object? categoriesObject = decoded['categories'];
    if (categoriesObject is! Map) {
      return const <NgPresetCategory>[];
    }
    final List<NgPresetCategory> result = <NgPresetCategory>[];
    categoriesObject.forEach((Object? key, Object? value) {
      if (key is! String || key.isEmpty) {
        return;
      }
      if (value is! Map) {
        return;
      }
      final NgPresetCategory? parsed = _parseCategory(key, value);
      if (parsed != null) {
        result.add(parsed);
      }
    });
    return List<NgPresetCategory>.unmodifiable(result);
  }

  /// Collects the words from a parsed [categories] list and deduplicates
  /// across all categories while preserving first-seen order.
  ///
  /// This is the v1-compatible "flat list of NG words" view used by existing
  /// matching code (`comment_screen.dart`, `CommentSpeechPlugin.kt`).
  static List<String> flattenWords(Iterable<NgPresetCategory> categories) {
    final Set<String> seen = <String>{};
    final List<String> out = <String>[];
    for (final NgPresetCategory category in categories) {
      for (final String word in category.words) {
        if (seen.add(word)) {
          out.add(word);
        }
      }
    }
    return List<String>.unmodifiable(out);
  }

  static NgPresetCategory? _parseCategory(
    String id,
    Map<Object?, Object?> raw,
  ) {
    final Object? wordsObject = raw['words'];
    if (wordsObject is! List) {
      return null;
    }
    // Deduplicate within the category while preserving first-seen order.
    final Set<String> seen = <String>{};
    final List<String> ordered = <String>[];
    for (final Object? wordObject in wordsObject) {
      if (wordObject is! String) {
        continue;
      }
      final String trimmed = wordObject.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (seen.add(trimmed)) {
        ordered.add(trimmed);
      }
    }
    // Empty categories are kept so the presence of the category key is still
    // discoverable by the UI layer; the caller decides how to present them.
    final List<String> words = List<String>.unmodifiable(ordered);
    // Defensive type checks: `as String?` would throw on e.g. numeric or
    // boolean values, which would break the parser's "silent fallback"
    // contract and diverge from the Kotlin parser (which uses optString).
    final Object? policyRaw = raw['policy'];
    final NgPolicy policy = NgPolicy.fromWireName(
      policyRaw is String ? policyRaw : null,
    );
    final Object? subcategoryRaw = raw['displaySubcategory'];
    final NgDisplaySubcategory? subcategory = NgDisplaySubcategory.tryParse(
      subcategoryRaw is String ? subcategoryRaw : null,
    );
    final Object? descriptionRaw = raw['description'];
    final String description = descriptionRaw is String ? descriptionRaw : '';
    return NgPresetCategory(
      id: id,
      description: description,
      policy: policy,
      displaySubcategory: subcategory,
      words: words,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NgPresetCategory &&
          id == other.id &&
          description == other.description &&
          policy == other.policy &&
          displaySubcategory == other.displaySubcategory &&
          _listEquals(words, other.words);

  @override
  int get hashCode => Object.hash(
    id,
    description,
    policy,
    displaySubcategory,
    Object.hashAll(words),
  );

  @override
  String toString() =>
      'NgPresetCategory(id: $id, policy: ${policy.wireName}, '
      'displaySubcategory: ${displaySubcategory?.wireName}, '
      'words: ${words.length})';
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
