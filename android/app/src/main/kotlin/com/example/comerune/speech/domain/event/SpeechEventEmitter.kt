package com.example.comerune.speech.domain.event

interface SpeechEventEmitter {
    fun emit(event: Map<String, Any?>)
}
