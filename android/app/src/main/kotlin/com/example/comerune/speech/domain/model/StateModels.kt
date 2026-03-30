package com.example.comerune.speech.domain.model

enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
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
