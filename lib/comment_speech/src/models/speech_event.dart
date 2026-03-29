/// Known event type constants for [SpeechEvent.type].
abstract class SpeechEventType {
  static const engineStateChanged = 'engine_state_changed';
  static const queueUpdated = 'queue_updated';
  static const commentSkipped = 'comment_skipped';
  static const speechStarted = 'speech_started';
  static const speechCompleted = 'speech_completed';
  static const speechFailed = 'speech_failed';
  static const playerStateChanged = 'player_state_changed';
  static const error = 'error';
  static const downloadStarted = 'download_started';
  static const downloadProgress = 'download_progress';
  static const downloadCompleted = 'download_completed';
}

/// An event emitted from the native speech engine via EventChannel.
class SpeechEvent {
  final String type;
  final Map<String, dynamic> payload;

  const SpeechEvent({required this.type, required this.payload});

  factory SpeechEvent.fromMap(Map<dynamic, dynamic> map) => SpeechEvent(
        type: (map['type'] as String?) ?? 'unknown',
        payload: map['payload'] != null
            ? Map<String, dynamic>.from(map['payload'] as Map)
            : const {},
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeechEvent &&
          type == other.type &&
          _mapEquals(payload, other.payload);

  @override
  int get hashCode => Object.hash(type, Object.hashAll(payload.entries));

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
