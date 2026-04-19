/// Defines how a matching NG word affects a comment.
///
/// - [blockAll]: suppress both display and speech.
///   **Reserved for future use.** v1 does not emit this value from the preset
///   catalog; every shipped category uses [blockSpeechOnly] because the
///   product design (Epic #611) keeps display opt-in for all categories.
/// - [blockSpeechOnly]: display the comment but skip speech playback (v1
///   conservative default used by preset categories).
///
/// The enum is intentionally small and stable so that additional policies can
/// be added later without breaking existing persisted values.
enum NgPolicy {
  blockAll,
  blockSpeechOnly;

  /// The conservative default applied when a policy string is missing or
  /// unknown. Keeping the default on the "speech only" side preserves the v1
  /// behavior where preset NG words never hide a comment from the UI.
  static const NgPolicy defaultPolicy = NgPolicy.blockSpeechOnly;

  /// Stable wire string, used for JSON serialization. Intentionally matches
  /// the enum name exactly to keep the two representations easy to reason
  /// about.
  String get wireName {
    switch (this) {
      case NgPolicy.blockAll:
        return 'blockAll';
      case NgPolicy.blockSpeechOnly:
        return 'blockSpeechOnly';
    }
  }

  /// Parses a wire string to an [NgPolicy].
  ///
  /// Returns [NgPolicy.defaultPolicy] when [value] is null, empty, or does not
  /// match a known policy name. Callers that need to distinguish "missing"
  /// from "invalid" should use [tryParse].
  static NgPolicy fromWireName(String? value) =>
      tryParse(value) ?? defaultPolicy;

  /// Parses a wire string to an [NgPolicy], returning null on unknown input.
  static NgPolicy? tryParse(String? value) {
    if (value == null) {
      return null;
    }
    switch (value) {
      case 'blockAll':
        return NgPolicy.blockAll;
      case 'blockSpeechOnly':
        return NgPolicy.blockSpeechOnly;
      default:
        return null;
    }
  }
}
