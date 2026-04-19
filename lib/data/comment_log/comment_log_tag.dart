import '../../domain/models/ng_display_subcategory.dart';

/// Tags prepended to a comment's content when it is written to the
/// auto-saved comment log file.
///
/// Format: `[<reason>:<subcategory>]` where `<reason>` is one of
/// `filtered` / `speech_blocked` and `<subcategory>` is the wire name of
/// an [NgDisplaySubcategory] (`violence` / `sexual` / `discrimination` /
/// `minors`).
///
/// The format is intentionally regex-friendly — see [logTagPattern] — so
/// downstream consumers (e.g. log viewers, share-sheet readers) can strip
/// or highlight these prefixes without re-parsing the whole line.
class CommentLogTag {
  const CommentLogTag._();

  /// Reason string for comments that are dropped from the displayed list
  /// because the user has the corresponding display toggle OFF.
  static const String reasonFiltered = 'filtered';

  /// Reason string for comments that ARE displayed but had their TTS
  /// playback blocked by the preset NG word policy. Reserved for use after
  /// the display toggles are wired through (#615); #614 does not yet emit
  /// this reason, but the format is fixed here so the wire format does not
  /// drift between issues.
  static const String reasonSpeechBlocked = 'speech_blocked';

  /// Returns the `[filtered:<subcategory>]` tag for [subcategory].
  static String filtered(NgDisplaySubcategory subcategory) =>
      '[$reasonFiltered:${subcategory.wireName}]';

  /// Returns the `[speech_blocked:<subcategory>]` tag for [subcategory].
  static String speechBlocked(NgDisplaySubcategory subcategory) =>
      '[$reasonSpeechBlocked:${subcategory.wireName}]';

  /// Prepends [tag] to [content] separated by a single space. Returns
  /// [content] unchanged when [tag] is null. The single-space separator
  /// matches the example in Issue #614 and keeps [logTagPattern] simple.
  static String applyTag({required String content, String? tag}) {
    if (tag == null || tag.isEmpty) {
      return content;
    }
    return '$tag $content';
  }

  /// Regex that matches a [filtered] or [speechBlocked] tag at the start
  /// of a line. Capture group 1 is the reason, group 2 is the subcategory.
  ///
  /// Anchored to the beginning of the string so callers can apply it to a
  /// single content cell without false positives in the middle of a
  /// comment body.
  ///
  /// The subcategory alternation is generated from
  /// [NgDisplaySubcategory.values] so that adding a new enum value keeps
  /// this regex in sync automatically.
  static final RegExp logTagPattern = RegExp(
    '^\\[($reasonFiltered|$reasonSpeechBlocked):'
    '(${NgDisplaySubcategory.values.map((NgDisplaySubcategory s) => s.wireName).join('|')})'
    '\\]\\s',
  );
}
