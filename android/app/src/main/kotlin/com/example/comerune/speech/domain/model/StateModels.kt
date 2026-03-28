package com.example.comerune.speech.domain.model

enum class TtsEngineState {
    UNINITIALIZED,
    INITIALIZING,
    READY,
    SYNTHESIZING,
    ERROR
}

enum class PlayerState {
    IDLE,
    PLAYING,
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

data class SpeechEvent(
    val type: String,
    val payload: Map<String, Any?>
)
