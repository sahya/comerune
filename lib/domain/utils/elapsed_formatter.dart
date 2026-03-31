/// Formats a [Duration] as `H:MM:SS`.
String _formatDurationHms(Duration duration) {
  final int hours = duration.inHours;
  final int minutes = duration.inMinutes % 60;
  final int seconds = duration.inSeconds % 60;
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

/// Formats a [DateTime] as a wall-clock `HH:MM:SS` string in local time.
String formatWallClockHms(DateTime value) {
  final DateTime local = value.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  final String ss = local.second.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// Formats [value] as elapsed time from [beginAt] when available,
/// otherwise falls back to a wall-clock `HH:MM:SS` string.
String formatCommentTime(DateTime value, {DateTime? beginAt}) {
  return formatCommentElapsed(beginAt, value) ?? formatWallClockHms(value);
}
