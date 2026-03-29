package com.example.comerune.speech.infrastructure.engine

/**
 * JNI bridge to the VOICEVOX Core native library.
 *
 * All methods delegate to C++ functions in voicevox_jni.cpp via JNI.
 * Thread safety is handled on the native side with a mutex.
 *
 * Note: VOICEVOX Core 0.16.2 TTS one-shot API does not support
 * speed/pitch/intonation/volume parameters. Those fields are accepted
 * for future compatibility (audio_query path) but are currently ignored
 * on the native side.
 */
object NativeVoicevoxBridge {

    init {
        System.loadLibrary("voicevox_jni")
    }

    /**
     * Initialize the VOICEVOX synthesizer with an OpenJTalk dictionary.
     *
     * @param openJtalkDictDir absolute path to the OpenJTalk dictionary directory
     * @return true if initialization succeeded
     */
    external fun nativeInitialize(openJtalkDictDir: String): Boolean

    /**
     * Load a VVM (voice model) file into the synthesizer.
     *
     * @param vvmPath absolute path to the .vvm file
     * @return true if the model was loaded successfully
     */
    external fun nativeLoadModel(vvmPath: String): Boolean

    /**
     * Check whether a voice model with the given speaker (style) ID is usable.
     *
     * Internally this checks whether any loaded model contains the style ID
     * by attempting a lightweight query. The native side tracks loaded model IDs.
     *
     * @param speakerId the VOICEVOX style ID to check
     * @return true if a model providing this style ID is loaded
     */
    external fun nativeIsModelLoaded(speakerId: Int): Boolean

    /**
     * Synthesize speech from text using the TTS one-shot API.
     *
     * Speed/pitch/intonation/volume parameters are reserved for a future
     * audio_query-based path and are currently ignored.
     *
     * @param text Japanese text to synthesize
     * @param speakerId VOICEVOX style ID
     * @param speedScale reserved (ignored in 0.16.2 TTS one-shot)
     * @param pitchScale reserved (ignored in 0.16.2 TTS one-shot)
     * @param intonationScale reserved (ignored in 0.16.2 TTS one-shot)
     * @param volumeScale reserved (ignored in 0.16.2 TTS one-shot)
     * @param prePhonemeLength reserved (ignored in 0.16.2 TTS one-shot)
     * @param postPhonemeLength reserved (ignored in 0.16.2 TTS one-shot)
     * @return WAV byte array, or null on error
     */
    external fun nativeTts(
        text: String,
        speakerId: Int,
        speedScale: Float,
        pitchScale: Float,
        intonationScale: Float,
        volumeScale: Float,
        prePhonemeLength: Float,
        postPhonemeLength: Float
    ): ByteArray?

    /**
     * Release all native resources (synthesizer, OpenJTalk).
     * After calling this, [nativeInitialize] must be called again before use.
     */
    external fun nativeRelease()
}
