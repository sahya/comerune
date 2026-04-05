/// Result of a broadcast control operation (start, stop, or extend).
class BroadcastControlResult {
  const BroadcastControlResult({
    required this.success,
    this.startTime,
    this.endTime,
    this.errorCode,
    this.errorMessage,
  });

  /// Whether the operation completed successfully.
  final bool success;

  /// Unix timestamp (seconds) when the broadcast started.
  final int? startTime;

  /// Unix timestamp (seconds) when the broadcast ends (or ended).
  final int? endTime;

  /// Error code from the API (e.g. "CONFLICT", "FORBIDDEN").
  final String? errorCode;

  /// Human-readable error description.
  final String? errorMessage;

  /// Whether the error indicates the program already ended (HTTP 409).
  bool get isAlreadyEnded => errorCode == 'CONFLICT';
}
