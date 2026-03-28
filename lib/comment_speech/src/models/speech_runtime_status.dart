/// Runtime status of the speech engine, player, and queue.
class SpeechRuntimeStatus {
  final bool enabled;
  final String engineState;
  final String playerState;
  final int queueSize;
  final String? currentCommentId;
  final String? currentText;
  final int currentSpeakerId;

  const SpeechRuntimeStatus({
    required this.enabled,
    required this.engineState,
    required this.playerState,
    required this.queueSize,
    this.currentCommentId,
    this.currentText,
    required this.currentSpeakerId,
  });

  factory SpeechRuntimeStatus.fromMap(Map<String, dynamic> map) =>
      SpeechRuntimeStatus(
        enabled: map['enabled'] as bool,
        engineState: map['engineState'] as String,
        playerState: map['playerState'] as String,
        queueSize: map['queueSize'] as int,
        currentCommentId: map['currentCommentId'] as String?,
        currentText: map['currentText'] as String?,
        currentSpeakerId: map['currentSpeakerId'] as int,
      );
}
