package com.example.comerune.speech.infrastructure.engine

/**
 * JNI bridge to the VOICEVOX Core native library.
 *
 * All methods delegate to C++ functions in voicevox_jni.cpp via JNI.
 * Thread safety is handled on the native side with a shared_mutex:
 * lifecycle operations (init/release/loadModel) acquire an exclusive lock,
 * while synthesis operations (audioQuery/synthesis/tts) acquire a shared lock
 * to allow concurrent execution.
 *
 * **Naming note:** The `speakerId` parameter used throughout this codebase
 * corresponds to VOICEVOX's `VoicevoxStyleId`. VOICEVOX identifies voice
 * variations (styles) by style ID, not by speaker ID. The name `speakerId`
 * was chosen for domain clarity within this app, but the underlying value
 * is always passed as a `VoicevoxStyleId` to the native API.
 *
 * Two synthesis paths are available:
 * - **TTS one-shot** ([nativeTts]): Simple text→WAV, but does not support
 *   speed/pitch/intonation/volume parameters.
 * - **AudioQuery-based** ([nativeCreateAudioQuery] + [nativeSynthesis]):
 *   Generates an AudioQuery JSON that can be modified (e.g. volumeScale,
 *   speedScale) before synthesis. This is the preferred path for parameter
 *   control.
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
     * This is a convenience method that combines audio_query creation and
     * synthesis in one call, but does **not** support speed/pitch/intonation/
     * volume parameters. Prefer [nativeCreateAudioQuery] + [nativeSynthesis]
     * when parameter control is needed.
     *
     * @param text Japanese text to synthesize
     * @param speakerId VOICEVOX style ID
     * @param speedScale ignored in TTS one-shot
     * @param pitchScale ignored in TTS one-shot
     * @param intonationScale ignored in TTS one-shot
     * @param volumeScale ignored in TTS one-shot
     * @param prePhonemeLength ignored in TTS one-shot
     * @param postPhonemeLength ignored in TTS one-shot
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
     * Create an AudioQuery JSON from Japanese text.
     *
     * The returned JSON can be modified (e.g. to adjust volumeScale,
     * speedScale, pitchScale) before passing to [nativeSynthesis].
     *
     * @param text Japanese text to analyze
     * @param speakerId VOICEVOX style ID
     * @return AudioQuery JSON string, or null on error
     */
    external fun nativeCreateAudioQuery(
        text: String,
        speakerId: Int
    ): String?

    /**
     * Synthesize WAV audio from an AudioQuery JSON.
     *
     * @param audioQueryJson AudioQuery JSON (from [nativeCreateAudioQuery],
     *        possibly modified)
     * @param speakerId VOICEVOX style ID
     * @return WAV byte array, or null on error
     */
    external fun nativeSynthesis(
        audioQueryJson: String,
        speakerId: Int
    ): ByteArray?

    /**
     * Release all native resources (synthesizer, OpenJTalk).
     * After calling this, [nativeInitialize] must be called again before use.
     */
    external fun nativeRelease()
}
