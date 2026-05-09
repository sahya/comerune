package com.example.comerune.speech.domain.model

enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
    DOWNLOADING,
    EXTRACTING,
    READY,
    SYNTHESIZING,
    ERROR
}

/**
 * Represents the current state of the WAV audio player.
 *
 * - [IDLE]: The player is ready and waiting for audio, or has finished playing the
 *   previous item. This is the initial state and the state after successful playback.
 * - [PLAYING]: Audio is actively being played.
 * - [PAUSED]: Playback was temporarily paused (e.g., due to transient audio focus loss).
 *   Playback will resume automatically when audio focus is regained.
 * - [STOPPED]: Playback was manually interrupted (e.g., by a skip or stop command).
 * - [ERROR]: An unrecoverable playback failure occurred.
 */
enum class PlayerState {
    IDLE,
    PLAYING,
    PAUSED,
    STOPPED,
    ERROR
}

// TODO(#741 Problem 4): a `PlayerState.shouldBePlaying` extension that
// folds together `PLAYING` and `PAUSED` (i.e. "the user wants audio out
// even though the AudioFocus has been transiently lost") would let the
// AudioFocus / WAV player code stop hand-rolling the same OR check.
// Deferred here because Issue #735 (PR #746) introduces an
// AudioFocusGuard that already adds a similar predicate per WavPlayer
// implementation; consolidating is owned by that work to avoid two
// competing definitions.

/**
 * Snapshot of speech-engine runtime state, marshalled to the Flutter side
 * via `CommentSpeechPlugin.getStatus()`.
 *
 * @property started Whether the queue worker loop is currently armed
 *   (i.e. `start()` has been called and `stop()`/`release()` has not).
 *   This is the **ground truth** for the Flutter-side `_speechStarted`
 *   mirror flag (Issue #915). It represents *worker-loop intent* only —
 *   it is independent of [engineState] (e.g. the worker can be `started`
 *   while the engine is still `INITIALIZING`).
 */
data class SpeechRuntimeStatus(
    val enabled: Boolean,
    val engineState: TtsEngineState,
    val playerState: PlayerState,
    val queueSize: Int,
    val currentCommentId: String?,
    val currentText: String?,
    val currentSpeakerId: Int,
    val started: Boolean
)

/**
 * Represents a speech-related event emitted to the Flutter side via EventChannel.
 *
 * @property type The event type identifier (e.g., "speech_started", "queue_updated",
 *   "comment_skipped"). See [com.example.comerune.speech.domain.event.SpeechEvents]
 *   for the full set of factory methods and their type strings.
 * @property payload A map of event-specific data. The keys and value types depend
 *   on [type]. For example, "speech_started" includes "commentId" and "text",
 *   while "queue_updated" includes "size".
 */
data class SpeechEvent(
    val type: String,
    val payload: Map<String, Any?>
)
