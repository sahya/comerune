const int _millisecondsEpochThreshold = 1000000000000;

/// Parses the `beginAt` field from a JSON map into a [DateTime].
///
/// The `beginAt` field is an ISO 8601 date-time string (e.g.
/// "2025-07-01T12:00:00+09:00"). Falls back to treating an integer value
/// as epoch time. Integer values with 13+ digits are treated as milliseconds
/// since epoch, and smaller values are treated as seconds since epoch.
///
/// Returns `null` when the value is missing, empty, or not a recognised type.
DateTime? parseBeginAt(Map<String, dynamic> data) {
  final Object? raw = data['beginAt'];
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
