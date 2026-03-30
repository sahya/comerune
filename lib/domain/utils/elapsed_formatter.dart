/// Formats a [Duration] as `H:MM:SS`.
String _formatDurationHms(Duration d) {
  final int hours = d.inHours;
  final int minutes = d.inMinutes % 60;
  final int seconds = d.inSeconds % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  return '$hours:$mm:$ss';
}

/// Formats the elapsed time since [start] as `H:MM:SS`.
/// Returns null if [start] is null or in the future.
String? formatElapsed(DateTime? start) {
  if (start == null) {
    return null;
  }
  final Duration elapsed = DateTime.now().difference(start);
  if (elapsed.isNegative) {
    return null;
  }
  return _formatDurationHms(elapsed);
}

/// Formats [timestamp] as elapsed time from [beginAt] in `H:MM:SS` format.
///
/// If [beginAt] is null or [timestamp] is before [beginAt], returns null so
/// the caller can fall back to a local-time display.
String? formatCommentElapsed(DateTime? beginAt, DateTime timestamp) {
  if (beginAt == null) {
    return null;
  }
  final Duration elapsed = timestamp.difference(beginAt);
  if (elapsed.isNegative) {
    return null;
  }
  return _formatDurationHms(elapsed);
}

/// Formats a [DateTime] as a wall-clock time string in `HH:MM:SS` format
/// using the local timezone.
String formatWallClock(DateTime value) {
  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// Formats a timestamp, preferring elapsed time from [beginAt] when available.
///
/// If [beginAt] is provided and [value] is after [beginAt], returns elapsed
/// time in `H:MM:SS` format. Otherwise, returns a wall-clock time in
/// `HH:MM:SS` format.
String formatTimestamp(DateTime value, {DateTime? beginAt}) {
  final String? elapsed = formatCommentElapsed(beginAt, value);
  if (elapsed != null) {
    return elapsed;
  }
  return formatWallClock(value);
}
