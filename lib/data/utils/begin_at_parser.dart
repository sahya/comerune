const int _millisecondsEpochThreshold = 1000000000000;

/// Parses the `beginAt` field from a JSON map into a [DateTime].
///
/// Thin wrapper over [parseDateTimeFlexible] that keeps the existing
/// `Map`-based call site ergonomic. See [parseDateTimeFlexible] for the
/// accepted value shapes and the null-on-bad-shape contract.
DateTime? parseBeginAt(Map<String, dynamic> data) {
  return parseDateTimeFlexible(data['beginAt']);
}

/// Parses a "date-time or epoch" JSON value into a [DateTime] defensively.
///
/// Accepts the shapes the niconico programinfo API is known to emit for
/// this kind of field:
///   - ISO 8601 string (e.g. "2026-04-15T12:00:00+09:00")
///   - integer seconds since Unix epoch
///   - integer milliseconds since Unix epoch (13+ digits)
///
/// Returns `null` for any other shape (missing key, empty string, float,
/// non-parseable string, map, list, etc.). This is deliberately strict so
/// that unexpected server-side shapes fall back to whatever the caller
/// uses for "no value" rather than producing garbage timestamps.
DateTime? parseDateTimeFlexible(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    final int absRaw = raw.abs();
    final bool isMillisecondsEpoch = absRaw >= _millisecondsEpochThreshold;
    final int milliseconds = isMillisecondsEpoch ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
  return null;
}
