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
  final int hours = elapsed.inHours;
  final int minutes = elapsed.inMinutes % 60;
  final int seconds = elapsed.inSeconds % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = seconds.toString().padLeft(2, '0');
  return '$hours:$mm:$ss';
}
