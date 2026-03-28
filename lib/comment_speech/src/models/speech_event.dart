/// An event emitted from the native speech engine via EventChannel.
class SpeechEvent {
  final String type;
  final Map<String, dynamic> payload;

  const SpeechEvent({required this.type, required this.payload});

  factory SpeechEvent.fromMap(Map<dynamic, dynamic> map) => SpeechEvent(
        type: map['type'] as String,
        payload: Map<String, dynamic>.from(map['payload'] as Map),
      );
}
