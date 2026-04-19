/// Coarse-grained display categorization used by future UI toggles.
///
/// Each preset NG word category declares exactly one [NgDisplaySubcategory]
/// in the v3 schema. The enum values are intentionally limited to the four
/// buckets the UI design for #615 exposes; unrecognized values are treated as
/// "not classified" and cause the category to be ignored by the display-side
/// toggles.
enum NgDisplaySubcategory {
  violence,
  sexual,
  discrimination,
  minors;

  /// Stable wire string used for JSON serialization.
  String get wireName {
    switch (this) {
      case NgDisplaySubcategory.violence:
        return 'violence';
      case NgDisplaySubcategory.sexual:
        return 'sexual';
      case NgDisplaySubcategory.discrimination:
        return 'discrimination';
      case NgDisplaySubcategory.minors:
        return 'minors';
    }
  }

  /// Parses a wire string to an [NgDisplaySubcategory], returning null on
  /// unknown input or null input. Callers must decide whether unknown values
  /// should be treated as "no classification" (preferred) or as an error.
  static NgDisplaySubcategory? tryParse(String? value) {
    if (value == null) {
      return null;
    }
    switch (value) {
      case 'violence':
        return NgDisplaySubcategory.violence;
      case 'sexual':
        return NgDisplaySubcategory.sexual;
      case 'discrimination':
        return NgDisplaySubcategory.discrimination;
      case 'minors':
        return NgDisplaySubcategory.minors;
      default:
        return null;
    }
  }
}
