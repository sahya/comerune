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

// Resolved by Issue #916: the intent-vs-physical-state split is now
// modelled by `WavPlayer.shouldBePlaying()` on the player contract, not
// by an extension on the [PlayerState] enum. Folding `PLAYING + PAUSED`
// into a single derived predicate would have conflated focus-loss pause
// with explicit pause; the per-player intent flag is the authoritative
// source instead.
//
// Resolved by Issue #915: `started` is now exposed on
// [SpeechRuntimeStatus] (see below) so the Flutter side can reconcile
// its local `_speechStarted` flag with the native worker loop after
// process recreation.

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
