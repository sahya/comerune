#include <jni.h>
#include <string>
#include <shared_mutex>
#include <android/log.h>
#include "voicevox_core.h"

#define LOG_TAG "VoicevoxJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Read-write lock: exclusive for lifecycle ops (init/release/loadModel),
// shared for synthesis ops (audioQuery/synthesis/tts/isReady).
// VOICEVOX Core's VoicevoxSynthesizer is internally thread-safe for
// concurrent read operations (all take `const VoicevoxSynthesizer*`).
static std::shared_mutex g_mutex;
static const VoicevoxOnnxruntime* g_onnxruntime = nullptr;
static OpenJtalkRc* g_open_jtalk = nullptr;
static VoicevoxSynthesizer* g_synthesizer = nullptr;

/**
 * Convert a Java jstring to a C++ std::string.
 * Returns an empty string if the input is null.
 */
static std::string jstringToString(JNIEnv* env, jstring jstr) {
    if (jstr == nullptr) {
        return "";
    }
    const char* chars = env->GetStringUTFChars(jstr, nullptr);
    if (chars == nullptr) {
        return "";
    }
    std::string result(chars);
    env->ReleaseStringUTFChars(jstr, chars);
    return result;
}

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeInitialize(
        JNIEnv* env, jobject /* thiz */, jstring openJtalkDictDir) {
    std::unique_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer != nullptr) {
        LOGI("Synthesizer already initialized, skipping");
        return JNI_TRUE;
    }

    std::string dictDir = jstringToString(env, openJtalkDictDir);
    if (dictDir.empty()) {
        LOGE("nativeInitialize: openJtalkDictDir is null or empty");
        return JNI_FALSE;
    }

    // Load ONNX Runtime
    VoicevoxLoadOnnxruntimeOptions onnxOptions =
            voicevox_make_default_load_onnxruntime_options();
    VoicevoxResultCode result =
            voicevox_onnxruntime_load_once(onnxOptions, &g_onnxruntime);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Failed to load ONNX Runtime: %s",
             voicevox_error_result_to_message(result));
        return JNI_FALSE;
    }
    LOGI("ONNX Runtime loaded successfully");

    // Create OpenJtalk instance
    result = voicevox_open_jtalk_rc_new(dictDir.c_str(), &g_open_jtalk);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Failed to create OpenJtalk: %s",
             voicevox_error_result_to_message(result));
        g_onnxruntime = nullptr;
        return JNI_FALSE;
    }
    LOGI("OpenJtalk created with dict dir: %s", dictDir.c_str());

    // Create synthesizer
    VoicevoxInitializeOptions initOptions =
            voicevox_make_default_initialize_options();
    result = voicevox_synthesizer_new(
            g_onnxruntime, g_open_jtalk, initOptions, &g_synthesizer);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Failed to create synthesizer: %s",
             voicevox_error_result_to_message(result));
        voicevox_open_jtalk_rc_delete(g_open_jtalk);
        g_open_jtalk = nullptr;
        g_onnxruntime = nullptr;
        return JNI_FALSE;
    }
    LOGI("Synthesizer created successfully");

    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeLoadModel(
        JNIEnv* env, jobject /* thiz */, jstring vvmPath) {
    std::unique_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer == nullptr) {
        LOGE("nativeLoadModel: synthesizer not initialized");
        return JNI_FALSE;
    }

    std::string path = jstringToString(env, vvmPath);
    if (path.empty()) {
        LOGE("nativeLoadModel: vvmPath is null or empty");
        return JNI_FALSE;
    }

    VoicevoxVoiceModelFile* model = nullptr;
    VoicevoxResultCode result =
            voicevox_voice_model_file_open(path.c_str(), &model);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Failed to open VVM file '%s': %s",
             path.c_str(), voicevox_error_result_to_message(result));
        return JNI_FALSE;
    }

    result = voicevox_synthesizer_load_voice_model(g_synthesizer, model);
    voicevox_voice_model_file_delete(model);

    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Failed to load voice model: %s",
             voicevox_error_result_to_message(result));
        return JNI_FALSE;
    }

    LOGI("Voice model loaded from: %s", path.c_str());
    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeIsSynthesizerReady(
        JNIEnv* /* env */, jobject /* thiz */, jint /* speakerId */) {
    std::shared_lock<std::shared_mutex> lock(g_mutex);

    // Checks whether the native synthesizer has been initialized (non-null).
    // The speakerId parameter is accepted for future API compatibility but is
    // not currently used — a more precise per-style check would require
    // maintaining a speakerId-to-modelId mapping.
    return static_cast<jboolean>(g_synthesizer != nullptr);
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeTts(
        JNIEnv* env, jobject /* thiz */,
        jstring text, jint speakerId,
        jfloat /* speedScale */, jfloat /* pitchScale */,
        jfloat /* intonationScale */, jfloat /* volumeScale */,
        jfloat /* prePhonemeLength */, jfloat /* postPhonemeLength */) {
    std::shared_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer == nullptr) {
        LOGE("nativeTts: synthesizer not initialized");
        return nullptr;
    }

    std::string textStr = jstringToString(env, text);
    if (textStr.empty()) {
        LOGE("nativeTts: text is null or empty");
        return nullptr;
    }

    // VOICEVOX Core 0.16.2 TTS one-shot API does not support speed/pitch/
    // intonation/volume parameters. Those are only available via the
    // audio_query -> synthesis path. The float parameters are accepted in the
    // JNI signature for forward compatibility but are currently unused.
    VoicevoxTtsOptions options = voicevox_make_default_tts_options();

    uintptr_t wavLength = 0;
    uint8_t* wav = nullptr;

    VoicevoxStyleId styleId = static_cast<VoicevoxStyleId>(speakerId);
    VoicevoxResultCode result = voicevox_synthesizer_tts(
            g_synthesizer, textStr.c_str(), styleId, options,
            &wavLength, &wav);
    if (result != VOICEVOX_RESULT_OK) {
        // Omit user text from logs to avoid leaking private comment content
        LOGE("TTS synthesis failed (text length=%zu): %s",
             textStr.length(), voicevox_error_result_to_message(result));
        return nullptr;
    }

    if (wav == nullptr || wavLength == 0) {
        LOGE("TTS returned empty WAV data");
        if (wav != nullptr) {
            voicevox_wav_free(wav);
        }
        return nullptr;
    }

    jbyteArray javaWav = env->NewByteArray(static_cast<jsize>(wavLength));
    if (javaWav == nullptr) {
        LOGE("Failed to allocate Java byte array of size %zu", wavLength);
        voicevox_wav_free(wav);
        return nullptr;
    }

    env->SetByteArrayRegion(
            javaWav, 0, static_cast<jsize>(wavLength),
            reinterpret_cast<const jbyte*>(wav));
    voicevox_wav_free(wav);

    LOGI("TTS synthesis succeeded: %zu bytes", wavLength);
    return javaWav;
}

JNIEXPORT jstring JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeCreateAudioQuery(
        JNIEnv* env, jobject /* thiz */,
        jstring text, jint speakerId) {
    std::shared_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer == nullptr) {
        LOGE("nativeCreateAudioQuery: synthesizer not initialized");
        return nullptr;
    }

    std::string textStr = jstringToString(env, text);
    if (textStr.empty()) {
        LOGE("nativeCreateAudioQuery: text is null or empty");
        return nullptr;
    }

    char* audioQueryJson = nullptr;
    VoicevoxStyleId styleId = static_cast<VoicevoxStyleId>(speakerId);
    VoicevoxResultCode result = voicevox_synthesizer_create_audio_query(
            g_synthesizer, textStr.c_str(), styleId, &audioQueryJson);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("AudioQuery creation failed (text length=%zu): %s",
             textStr.length(), voicevox_error_result_to_message(result));
        return nullptr;
    }

    if (audioQueryJson == nullptr) {
        LOGE("AudioQuery returned null JSON");
        return nullptr;
    }

    jstring javaJson = env->NewStringUTF(audioQueryJson);
    voicevox_json_free(audioQueryJson);

    LOGI("AudioQuery created successfully");
    return javaJson;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeSynthesis(
        JNIEnv* env, jobject /* thiz */,
        jstring audioQueryJson, jint speakerId) {
    std::shared_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer == nullptr) {
        LOGE("nativeSynthesis: synthesizer not initialized");
        return nullptr;
    }

    std::string queryStr = jstringToString(env, audioQueryJson);
    if (queryStr.empty()) {
        LOGE("nativeSynthesis: audioQueryJson is null or empty");
        return nullptr;
    }

    VoicevoxSynthesisOptions options = voicevox_make_default_synthesis_options();

    uintptr_t wavLength = 0;
    uint8_t* wav = nullptr;

    VoicevoxStyleId styleId = static_cast<VoicevoxStyleId>(speakerId);
    VoicevoxResultCode result = voicevox_synthesizer_synthesis(
            g_synthesizer, queryStr.c_str(), styleId, options,
            &wavLength, &wav);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Synthesis from AudioQuery failed: %s",
             voicevox_error_result_to_message(result));
        return nullptr;
    }

    if (wav == nullptr || wavLength == 0) {
        LOGE("Synthesis returned empty WAV data");
        if (wav != nullptr) {
            voicevox_wav_free(wav);
        }
        return nullptr;
    }

    jbyteArray javaWav = env->NewByteArray(static_cast<jsize>(wavLength));
    if (javaWav == nullptr) {
        LOGE("Failed to allocate Java byte array of size %zu", wavLength);
        voicevox_wav_free(wav);
        return nullptr;
    }

    env->SetByteArrayRegion(
            javaWav, 0, static_cast<jsize>(wavLength),
            reinterpret_cast<const jbyte*>(wav));
    voicevox_wav_free(wav);

    LOGI("Synthesis from AudioQuery succeeded: %zu bytes", wavLength);
    return javaWav;
}

JNIEXPORT void JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeRelease(
        JNIEnv* /* env */, jobject /* thiz */) {
    std::unique_lock<std::shared_mutex> lock(g_mutex);

    if (g_synthesizer != nullptr) {
        voicevox_synthesizer_delete(g_synthesizer);
        g_synthesizer = nullptr;
        LOGI("Synthesizer released");
    }

    if (g_open_jtalk != nullptr) {
        voicevox_open_jtalk_rc_delete(g_open_jtalk);
        g_open_jtalk = nullptr;
        LOGI("OpenJtalk released");
    }

    // g_onnxruntime is managed by voicevox_core internally (singleton);
    // no explicit delete is needed or available.
    g_onnxruntime = nullptr;
}

} // extern "C"
