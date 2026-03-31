/// Parses the `beginAt` field from a JSON map into a [DateTime].
///
/// The `beginAt` field is an ISO 8601 date-time string (e.g.
/// "2025-07-01T12:00:00+09:00"). Falls back to treating an integer value
/// as seconds-since-epoch (observed in some legacy responses).
///
/// Returns `null` when the value is missing, empty, or not a recognised type.
DateTime? parseBeginAt(Map<String, dynamic> data) {
  final Object? raw = data['beginAt'];
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw * 1000, isUtc: true);
  }
  return null;
}
