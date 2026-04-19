import '../models/app_settings.dart';
import '../models/ng_display_subcategory.dart';
import '../models/ng_policy.dart';
import '../models/ng_preset_category.dart';

/// User-visible toggle state for each display subcategory.
///
/// The defaults are deliberately conservative (all `false`): when a toggle is
/// `false` the corresponding subcategory is still hidden from the comment
/// list, which preserves the v1 behavior where preset NG words never surface
/// in the UI. Issue #614 will wire these flags to the real `AppSettings`
/// value; in #613 the matcher just receives the default instance.
class NgDisplayPreferences {
  final bool allowViolence;
  final bool allowSexual;
  final bool allowDiscrimination;
  final bool allowMinors;

  const NgDisplayPreferences({
    this.allowViolence = false,
    this.allowSexual = false,
    this.allowDiscrimination = false,
    this.allowMinors = false,
  });

  /// Convenience default used by callers that have not opted any subcategory
  /// in. Kept as a `const` so it can be used in constructors.
  static const NgDisplayPreferences defaults = NgDisplayPreferences();

  /// Build an [NgDisplayPreferences] from the user's persisted [AppSettings]
  /// subcategory toggles.
  ///
  /// Pure function — no widget or framework dependency — so that tests can
  /// compose [AppSettings] directly and assert matcher behavior without
  /// instantiating a widget. Each `show*Comment` flag maps one-to-one to
  /// the corresponding `allow*` field.
  factory NgDisplayPreferences.fromAppSettings(AppSettings settings) {
    return NgDisplayPreferences(
      allowViolence: settings.showViolentComment,
      allowSexual: settings.showSexualComment,
      allowDiscrimination: settings.showDiscriminationComment,
      allowMinors: settings.showMinorsRelatedComment,
    );
  }

  /// Number of subcategories currently allowed (0..4). Pure helper used by
  /// the settings screen subtitle and by tests.
  int get enabledCount {
    int n = 0;
    if (allowViolence) n++;
    if (allowSexual) n++;
    if (allowDiscrimination) n++;
    if (allowMinors) n++;
    return n;
  }

  /// Returns `true` when comments matching [subcategory] should be shown.
  /// Null (unclassified) is never allowed by display-side toggles — the
  /// caller must either treat it as "hide" or bypass the display filter
  /// entirely. See [NgMatcher.shouldBlockDisplay].
  bool allows(NgDisplaySubcategory? subcategory) {
    if (subcategory == null) {
      return false;
    }
    switch (subcategory) {
      case NgDisplaySubcategory.violence:
        return allowViolence;
      case NgDisplaySubcategory.sexual:
        return allowSexual;
      case NgDisplaySubcategory.discrimination:
        return allowDiscrimination;
      case NgDisplaySubcategory.minors:
        return allowMinors;
    }
  }
}

/// Result of a single NG match lookup.
///
/// Holds only the subset of information callers need today (subcategory for
/// display-side filtering, and the matched pattern for the protection
/// snackbar). More fields (e.g. the source category id) can be added
/// without breaking existing call sites because this class has no public
/// constructor contract beyond its getters.
class NgMatchResult {
  /// The subcategory of the first preset entry that matched, or `null` when
  /// the match came from a user-configured NG word (no category) or from a
  /// preset category that declared no `displaySubcategory`.
  final NgDisplaySubcategory? matchedSubcategory;

  /// The policy of the matched source. `NgPolicy.blockAll` is used for
  /// user-configured NG words (they always block both display and speech).
  final NgPolicy matchedPolicy;

  /// The normalized pattern that matched. Used by the protection snackbar
  /// as the "what was filtered" label.
  final String matchedPattern;

  const NgMatchResult({
    required this.matchedSubcategory,
    required this.matchedPolicy,
    required this.matchedPattern,
  });
}

/// Single source of truth for NG-word matching.
///
/// Responsibilities:
///   * normalize the incoming comment text using [normalizer]
///   * scan the configured NG-word entries (preset categories + user list)
///   * return a structured [NgMatchResult] or `null`
///   * expose two-axis decision helpers
///     ([shouldBlockDisplay] / [shouldBlockSpeech]) so the caller does not
///     have to know about policies or display subcategories.
///
/// The matcher is intentionally stateless beyond the pre-normalized entry
/// list — every call recomputes the normalized form of the input so that
/// callers do not have to manage a cache. Previously the equivalent logic
/// lived in `CommentScreenState` and was duplicated in `AppSettings` and
/// `DefaultCommentNormalizer`; consolidating it here makes it possible to
/// verify the display / speech axes with a single unit-test file.
class NgMatcher {
  final List<_NgEntry> _entries;
  final String Function(String) _normalizer;

  NgMatcher._(this._entries, this._normalizer);

  /// Creates a matcher from a structured list of preset categories and a
  /// flat user NG-word list.
  ///
  /// [normalizer] must be the same function used to produce NG-word matching
  /// text in both the Dart and Kotlin paths — it is injected rather than
  /// bundled into this class so that callers can keep using the project-wide
  /// normalization helpers without this class taking on a platform
  /// dependency. Passing an unnormalized input is safe: the matcher always
  /// normalizes both sides.
  ///
  /// Cross-platform contract: Dart callers typically pass
  /// `_normalizeNgWordText` from `comment_screen.dart`, which must produce
  /// the same output as the Kotlin-side
  /// `com.example.comerune.speech.domain.normalizer.NgWordTextNormalizer`.
  /// If either implementation changes, the other must be updated in the
  /// same PR to keep display-side and speech-side filtering consistent.
  /// Unifying both into a single domain helper is tracked as a future
  /// refactor (out of scope for #613).
  ///
  /// Empty / whitespace-only words are filtered out. Duplicate normalized
  /// forms are collapsed (first-seen wins), which mirrors the previous
  /// behavior of `_refreshNormalizedNgWords` in `comment_screen.dart`.
  factory NgMatcher({
    required Iterable<NgPresetCategory> presetCategories,
    required Iterable<String> userNgWords,
    required String Function(String) normalizer,
  }) {
    final List<_NgEntry> entries = <_NgEntry>[];
    final Set<String> seen = <String>{};

    void add(String word, NgPolicy policy, NgDisplaySubcategory? subcategory) {
      if (word.trim().isEmpty) {
        return;
      }
      final String normalized = normalizer(word);
      if (normalized.isEmpty) {
        return;
      }
      if (!seen.add(normalized)) {
        return;
      }
      entries.add(
        _NgEntry(
          normalized: normalized,
          policy: policy,
          subcategory: subcategory,
        ),
      );
    }

    for (final NgPresetCategory category in presetCategories) {
      for (final String word in category.words) {
        add(word, category.policy, category.displaySubcategory);
      }
    }
    // User-configured NG words are treated as `blockAll` with no
    // subcategory: this is the pre-#613 behavior (they always block both
    // display and speech, regardless of display preferences).
    for (final String word in userNgWords) {
      add(word, NgPolicy.blockAll, null);
    }

    return NgMatcher._(List<_NgEntry>.unmodifiable(entries), normalizer);
  }

  /// Convenience constructor that skips the preset-category structure and
  /// treats every provided word as `blockAll` with no subcategory. Kept so
  /// call sites that have not yet migrated to structured preset categories
  /// can still use the matcher (and so that this class does not force a
  /// larger refactor of `comment_screen.dart` in one PR).
  factory NgMatcher.fromFlatWords({
    required Iterable<String> words,
    required String Function(String) normalizer,
  }) {
    return NgMatcher(
      presetCategories: const <NgPresetCategory>[],
      userNgWords: words,
      normalizer: normalizer,
    );
  }

  /// Returns `true` when the matcher has no effective NG entries.
  bool get isEmpty => _entries.isEmpty;

  /// Returns the first match in [text], or `null` when nothing matches.
  NgMatchResult? match(String text) {
    if (_entries.isEmpty) {
      return null;
    }
    final String normalizedText = _normalizer(text);
    if (normalizedText.isEmpty) {
      return null;
    }
    for (final _NgEntry entry in _entries) {
      if (normalizedText.contains(entry.normalized)) {
        return NgMatchResult(
          matchedSubcategory: entry.subcategory,
          matchedPolicy: entry.policy,
          matchedPattern: entry.normalized,
        );
      }
    }
    return null;
  }

  /// Returns `true` when [text] should be hidden from the comment list given
  /// the caller's [prefs].
  ///
  /// Display-axis rules:
  ///   * no match                                            → `false`
  ///   * match with [NgPolicy.blockAll]                      → `true`
  ///   * match with [NgPolicy.blockSpeechOnly] + allowed sub → `false`
  ///   * match with [NgPolicy.blockSpeechOnly] + other sub   → `true`
  ///
  /// When [prefs] is omitted the matcher uses [NgDisplayPreferences.defaults]
  /// (all `false`), which reproduces the v1 behavior: any match hides the
  /// comment regardless of subcategory.
  bool shouldBlockDisplay(
    String text, [
    NgDisplayPreferences prefs = NgDisplayPreferences.defaults,
  ]) {
    final NgMatchResult? result = match(text);
    if (result == null) {
      return false;
    }
    switch (result.matchedPolicy) {
      case NgPolicy.blockAll:
        return true;
      case NgPolicy.blockSpeechOnly:
        // When the match carries no subcategory (preset categories whose
        // displaySubcategory is null, or user words marked blockSpeechOnly
        // in the future) we treat it as "not user-toggleable" and keep the
        // conservative "hide" decision. See `NgDisplayPreferences.allows`.
        return !prefs.allows(result.matchedSubcategory);
    }
  }

  /// Returns `true` when [text] should be skipped by the TTS engine.
  ///
  /// v1: any match blocks speech regardless of [NgDisplayPreferences]. This
  /// is deliberate — VOICEVOX's terms of use require strict speech-side
  /// filtering, so the matcher does not distinguish engines yet.
  ///
  /// Future extension (not in scope for #613): a `shouldBlockSpeech(text,
  /// {SpeechEngine engine})` overload can route per-category decisions
  /// through an engine-specific table (for example, Android's stock TTS
  /// has looser terms and could permit some categories while VOICEVOX
  /// blocks them). The current API is shaped so this addition is purely
  /// additive — existing callers keep compiling because the engine
  /// argument would be optional.
  bool shouldBlockSpeech(String text) {
    return match(text) != null;
  }
}

class _NgEntry {
  final String normalized;
  final NgPolicy policy;
  final NgDisplaySubcategory? subcategory;

  const _NgEntry({
    required this.normalized,
    required this.policy,
    required this.subcategory,
  });
}
