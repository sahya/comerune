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
        enabled: (map['enabled'] as bool?) ?? false,
        engineState: (map['engineState'] as String?) ?? 'UNKNOWN',
        playerState: (map['playerState'] as String?) ?? 'UNKNOWN',
        queueSize: (map['queueSize'] as int?) ?? 0,
        currentCommentId: map['currentCommentId'] as String?,
        currentText: map['currentText'] as String?,
        currentSpeakerId: (map['currentSpeakerId'] as int?) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeechRuntimeStatus &&
          enabled == other.enabled &&
          engineState == other.engineState &&
          playerState == other.playerState &&
          queueSize == other.queueSize &&
          currentCommentId == other.currentCommentId &&
          currentText == other.currentText &&
          currentSpeakerId == other.currentSpeakerId;

  @override
  int get hashCode => Object.hash(
        enabled,
        engineState,
        playerState,
        queueSize,
        currentCommentId,
        currentText,
        currentSpeakerId,
      );
}
