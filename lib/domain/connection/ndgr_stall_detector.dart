class NdgrStallDetector {
  NdgrStallDetector({
    this.threshold = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration threshold;
  final DateTime Function() _now;

  DateTime? _lastReceivedAt;
  bool _stallNotified = false;

  DateTime? get lastReceivedAt => _lastReceivedAt;

  void markReceived([DateTime? timestamp]) {
    _lastReceivedAt = timestamp ?? _now();
    _stallNotified = false;
  }

  void reset() {
    _lastReceivedAt = null;
    _stallNotified = false;
  }

  Duration? elapsedSinceLastReceived() {
    if (_lastReceivedAt == null) {
      return null;
    }

    return _now().difference(_lastReceivedAt!);
  }

  bool get isStalled {
    final Duration? elapsed = elapsedSinceLastReceived();
    if (elapsed == null) {
      return false;
    }

    return elapsed >= threshold;
  }

  bool shouldNotifyStall() {
    if (!isStalled) {
      return false;
    }

    if (_stallNotified) {
      return false;
    }

    _stallNotified = true;
    return true;
  }
}
