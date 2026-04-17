package app.spectacles_software.comerune.speech.domain.event

interface SpeechEventEmitter {
    fun emit(event: Map<String, Any?>)
}
