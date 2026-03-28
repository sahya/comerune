package com.example.comerune.speech.domain.event

object SpeechEvents {
    fun engineStateChanged(state: String): Map<String, Any?> =
        mapOf("type" to "engine_state_changed", "payload" to mapOf("state" to state))

    fun queueUpdated(size: Int): Map<String, Any?> =
        mapOf("type" to "queue_updated", "payload" to mapOf("size" to size))

    fun commentSkipped(commentId: String, reason: String): Map<String, Any?> =
        mapOf("type" to "comment_skipped", "payload" to mapOf("commentId" to commentId, "reason" to reason))

    fun speechStarted(commentId: String, text: String): Map<String, Any?> =
        mapOf("type" to "speech_started", "payload" to mapOf("commentId" to commentId, "text" to text))

    fun speechCompleted(commentId: String): Map<String, Any?> =
        mapOf("type" to "speech_completed", "payload" to mapOf("commentId" to commentId))

    fun speechFailed(commentId: String, message: String): Map<String, Any?> =
        mapOf("type" to "speech_failed", "payload" to mapOf("commentId" to commentId, "message" to message))

    fun playerStateChanged(state: String): Map<String, Any?> =
        mapOf("type" to "player_state_changed", "payload" to mapOf("state" to state))

    fun error(code: String, message: String): Map<String, Any?> =
        mapOf("type" to "error", "payload" to mapOf("code" to code, "message" to message))
}
