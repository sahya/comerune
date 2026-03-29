package com.example.comerune.speech.domain.player

import com.example.comerune.speech.domain.model.PlayerState

interface WavPlayer {
    suspend fun play(wavBytes: ByteArray): Result<Unit>
    suspend fun stop(): Result<Unit>
    fun isPlaying(): Boolean
    fun currentState(): PlayerState
    fun release()
}
