/// Runtime status of the speech engine, player, and queue.
class SpeechRuntimeStatus {
  final bool enabled;
  final String engineState;
  final String playerState;
  final int queueSize;
  final String? currentCommentId;
  final String? currentText;
  final int currentSpeakerId;

  /// Whether the native queue worker loop is currently armed (i.e. the
  /// platform's `start()` has been called and `stop()` / `release()` has
  /// not). Acts as the **ground truth** for the screen-side
  /// `_speechStarted` mirror flag (Issue #915).
  ///
  /// This represents *worker-loop intent* only — it is independent of
  /// [engineState] (e.g. the worker can be `started` while the engine is
  /// still `INITIALIZING`).
  ///
  /// Defaults to `false` to stay backward-compatible with older native
  /// binaries that do not yet emit this field.
  final bool started;

  const SpeechRuntimeStatus({
    required this.enabled,
    required this.engineState,
    required this.playerState,
    required this.queueSize,
    this.currentCommentId,
    this.currentText,
    required this.currentSpeakerId,
    this.started = false,
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
        // Issue #915: default to `false` for forward compatibility with
        // older native builds that do not yet write this key.
        started: (map['started'] as bool?) ?? false,
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
          currentSpeakerId == other.currentSpeakerId &&
          started == other.started;

  @override
  int get hashCode => Object.hash(
    enabled,
    engineState,
    playerState,
    queueSize,
    currentCommentId,
    currentText,
    currentSpeakerId,
    started,
  );
}
