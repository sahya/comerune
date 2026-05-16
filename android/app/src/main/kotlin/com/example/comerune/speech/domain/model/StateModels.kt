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
// TODO(#741 Problem 3): consider exposing `started` on
// [SpeechRuntimeStatus] so the Flutter side can reconcile its local
// `_speechStarted` flag with the native worker loop after process
// recreation (currently the two can drift). Deferred until Issue #743
// (engine-switch fix) lands so the changes don't conflict.

data class SpeechRuntimeStatus(
    val enabled: Boolean,
    val engineState: TtsEngineState,
    val playerState: PlayerState,
    val queueSize: Int,
    val currentCommentId: String?,
    val currentText: String?,
    val currentSpeakerId: Int
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
