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

  /// Whether the native wire payload actually contained the `started`
  /// key.
  ///
  /// This is **wire-presence metadata, not logical state** — it records
  /// *that the field was reported*, not *what its value is*. It exists
  /// only so the forward-compat reconcile guard can distinguish
  /// "native says the worker loop is off" (`started == false` and
  /// `startedReported == true`) from "old native binary did not report
  /// the field at all" (`started == false` because [fromMap] defaulted
  /// it, and `startedReported == false`). In the latter case a reconcile
  /// call site must NOT trust the defaulted `false`, otherwise a new
  /// Flutter binary running against an old native binary would silently
  /// downgrade a genuinely-`true` mirror (the Issue #692 footgun, see
  /// the forward-compat caveat on `_speechStarted` in
  /// `comment_screen.dart`).
  ///
  /// Because it is wire metadata and not part of the logical runtime
  /// state, it is intentionally **excluded from [==] and [hashCode]**:
  /// two statuses that describe the same runtime are equal regardless of
  /// whether the field was transported. It defaults to `false` so
  /// directly-constructed instances (tests, internal callers that do not
  /// go through [fromMap]) are treated as "not wire-reported".
  final bool startedReported;

  const SpeechRuntimeStatus({
    required this.enabled,
    required this.engineState,
    required this.playerState,
    required this.queueSize,
    this.currentCommentId,
    this.currentText,
    required this.currentSpeakerId,
    this.started = false,
    this.startedReported = false,
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
        // Issue #915 forward-compat guard: record whether the native
        // payload actually carried the key, so a reconcile call site can
        // refuse to trust a defaulted `false` from an old native binary.
        startedReported: map.containsKey('started'),
      );

  // NOTE: [startedReported] is intentionally NOT part of [==]/[hashCode].
  // It is wire-presence metadata for the forward-compat reconcile guard,
  // not logical runtime state — see its Dartdoc above. Two statuses that
  // describe the same runtime must compare equal regardless of whether
  // the `started` key was transported.
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
