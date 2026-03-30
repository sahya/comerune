package com.example.comerune.speech.infrastructure.engine

/**
 * JNI bridge to the VOICEVOX Core native library.
 *
 * All methods delegate to C++ functions in voicevox_jni.cpp via JNI.
 * Thread safety is handled on the native side with a mutex.
 *
 * **Naming note:** The `speakerId` parameter used throughout this codebase
 * corresponds to VOICEVOX's `VoicevoxStyleId`. VOICEVOX identifies voice
 * variations (styles) by style ID, not by speaker ID. The name `speakerId`
 * was chosen for domain clarity within this app, but the underlying value
 * is always passed as a `VoicevoxStyleId` to the native API.
 *
 * Note: VOICEVOX Core 0.16.2 TTS one-shot API does not support
 * speed/pitch/intonation/volume parameters. Those fields are accepted
 * for future compatibility (audio_query path) but are currently ignored
 * on the native side.
 */
object NativeVoicevoxBridge {

    init {
        // Pre-load dependencies in the correct order so that the Android
        // linker can find them when voicevox_jni is loaded.
        //
        // voicevox_jni → voicevox_core → voicevox_onnxruntime
        //
        // Without explicit pre-loading, Android's linker namespace isolation
        // prevents the C++ dlopen from resolving these libraries.
        try {
            System.loadLibrary("voicevox_onnxruntime")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.w("NativeVoicevoxBridge", "voicevox_onnxruntime preload failed: ${e.message}")
        }
        try {
            System.loadLibrary("voicevox_core")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.w("NativeVoicevoxBridge", "voicevox_core preload failed: ${e.message}")
        }
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
     * Check whether the native synthesizer is initialized and ready to accept
     * TTS requests. This checks that [nativeInitialize] has been called
     * successfully and the synthesizer pointer is non-null.
     *
     * Note: The [speakerId] parameter is accepted for API compatibility but
     * is not currently used in the check. A future enhancement may verify
     * that a model providing the given style ID is loaded.
     *
     * @param speakerId reserved for future per-style readiness check
     * @return true if the native synthesizer is initialized
     */
    external fun nativeIsSynthesizerReady(speakerId: Int): Boolean

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
