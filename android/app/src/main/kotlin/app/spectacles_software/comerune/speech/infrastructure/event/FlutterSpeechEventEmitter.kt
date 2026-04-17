package app.spectacles_software.comerune.speech.infrastructure.event

import android.os.Handler
import android.os.Looper
import app.spectacles_software.comerune.speech.domain.event.SpeechEventEmitter

class FlutterSpeechEventEmitter : SpeechEventEmitter {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var eventSink: ((Map<String, Any?>) -> Unit)? = null

    fun setEventSink(sink: ((Map<String, Any?>) -> Unit)?) {
        this.eventSink = sink
    }

    override fun emit(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post { sink(event) }
    }
}
