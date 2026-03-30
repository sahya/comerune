package com.example.comerune.speech.domain.event

object SpeechEvents {
    fun engineStateChanged(state: String): Map<String, Any?> =
        mapOf("type" to "engine_state_changed", "payload" to mapOf("state" to state))

    fun queueUpdated(size: Int): Map<String, Any?> =
        mapOf("type" to "queue_updated", "payload" to mapOf("size" to size))

    fun commentSkipped(commentId: String, reason: String): Map<String, Any?> =
        mapOf("type" to "comment_skipped", "payload" to mapOf("commentId" to commentId, "reason" to reason))

    // Privacy note: text is included in this event so the Flutter UI can display
    // which comment is currently being spoken. The text has already been normalized
    // (NG words filtered, URLs replaced, etc.) before reaching this point.
    fun speechStarted(commentId: String, text: String): Map<String, Any?> =
        mapOf("type" to "speech_started", "payload" to mapOf("commentId" to commentId, "text" to text))

    fun speechCompleted(commentId: String): Map<String, Any?> =
        mapOf("type" to "speech_completed", "payload" to mapOf("commentId" to commentId))

    fun speechFailed(commentId: String, message: String): Map<String, Any?> =
        mapOf("type" to "speech_failed", "payload" to mapOf("commentId" to commentId, "message" to message))

    fun playerStateChanged(state: String): Map<String, Any?> =
        mapOf("type" to "player_state_changed", "payload" to mapOf("state" to state))

    fun downloadStarted(fileName: String): Map<String, Any?> =
        mapOf("type" to "download_started", "payload" to mapOf("fileName" to fileName))

    fun downloadProgress(bytesDownloaded: Long, totalBytes: Long, fileName: String): Map<String, Any?> =
        mapOf(
            "type" to "download_progress",
            "payload" to mapOf(
                "bytesDownloaded" to bytesDownloaded,
                "totalBytes" to totalBytes,
                "fileName" to fileName
            )
        )

    fun downloadCompleted(): Map<String, Any?> =
        mapOf("type" to "download_completed", "payload" to mapOf<String, Any?>())

    fun error(code: String, message: String): Map<String, Any?> =
        mapOf("type" to "error", "payload" to mapOf("code" to code, "message" to message))
}
