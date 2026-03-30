#include <jni.h>
#include <string>
#include <mutex>
#include <cmath>
#include <cstdio>
#include <android/log.h>
#include "voicevox_core.h"

#define LOG_TAG "VoicevoxJNI"
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static std::mutex g_mutex;
static const VoicevoxOnnxruntime* g_onnxruntime = nullptr;
static OpenJtalkRc* g_open_jtalk = nullptr;
static VoicevoxSynthesizer* g_synthesizer = nullptr;

/**
 * Replace the numeric value of a top-level JSON key in an AudioQuery JSON
 * string. The key must appear as "key": <number> at the top level.
 *
 * This is intentionally minimal: VOICEVOX AudioQuery JSON has a fixed
 * structure with top-level numeric fields (speedScale, pitchScale, etc.)
 * and this helper only needs to handle those.
 *
 * IMPORTANT: This function assumes the target key exists only at the
 * top level of the VOICEVOX AudioQuery JSON. If a future VOICEVOX version
 * introduces nested objects with the same key names, this simple string
 * search may match the wrong occurrence. Review when upgrading VOICEVOX Core.
 */
static bool replaceJsonFloat(std::string& json,
                             const std::string& key,
                             float value) {
    // Search for "key":
    std::string needle = "\"" + key + "\":";
    auto pos = json.find(needle);
    if (pos == std::string::npos) {
        // Also try with a space before the colon: "key" :
        needle = "\"" + key + "\" :";
        pos = json.find(needle);
        if (pos == std::string::npos) {
            return false;
        }
    }

    // Move past the needle to find the start of the value
    auto valueStart = pos + needle.length();

    // Skip whitespace
    while (valueStart < json.length() &&
           (json[valueStart] == ' ' || json[valueStart] == '\t')) {
        valueStart++;
    }

    // Find the end of the numeric value (may include '-', '.', digits, 'e/E')
    auto valueEnd = valueStart;
    while (valueEnd < json.length()) {
        char c = json[valueEnd];
        if (c == '-' || c == '+' || c == '.' ||
            (c >= '0' && c <= '9') || c == 'e' || c == 'E') {
            valueEnd++;
        } else {
            break;
        }
    }

    if (valueEnd == valueStart) {
        return false;
    }

    // Format the new value
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.6g", static_cast<double>(value));

    json.replace(valueStart, valueEnd - valueStart, buf);
    return true;
}

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
    std::lock_guard<std::mutex> lock(g_mutex);

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
    std::lock_guard<std::mutex> lock(g_mutex);

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
    std::lock_guard<std::mutex> lock(g_mutex);

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
        jfloat speedScale, jfloat pitchScale,
        jfloat intonationScale, jfloat volumeScale,
        jfloat prePhonemeLength, jfloat postPhonemeLength) {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (g_synthesizer == nullptr) {
        LOGE("nativeTts: synthesizer not initialized");
        return nullptr;
    }

    std::string textStr = jstringToString(env, text);
    if (textStr.empty()) {
        LOGE("nativeTts: text is null or empty");
        return nullptr;
    }

    VoicevoxStyleId styleId = static_cast<VoicevoxStyleId>(speakerId);

    // Step 1: Create an AudioQuery from text.
    char* audioQueryJson = nullptr;
    VoicevoxResultCode result = voicevox_synthesizer_create_audio_query(
            g_synthesizer, textStr.c_str(), styleId, &audioQueryJson);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("AudioQuery creation failed (text length=%zu): %s",
             textStr.length(), voicevox_error_result_to_message(result));
        return nullptr;
    }

    // Guard against NaN / Infinity — fall back to VOICEVOX defaults.
    if (std::isnan(speedScale) || std::isinf(speedScale)) speedScale = 1.0f;
    if (std::isnan(pitchScale) || std::isinf(pitchScale)) pitchScale = 0.0f;
    if (std::isnan(intonationScale) || std::isinf(intonationScale)) intonationScale = 1.0f;
    if (std::isnan(volumeScale) || std::isinf(volumeScale)) volumeScale = 1.0f;
    if (std::isnan(prePhonemeLength) || std::isinf(prePhonemeLength)) prePhonemeLength = 0.1f;
    if (std::isnan(postPhonemeLength) || std::isinf(postPhonemeLength)) postPhonemeLength = 0.1f;

    // Step 2: Modify the AudioQuery JSON to apply user parameters.
    std::string queryStr(audioQueryJson);
    voicevox_json_free(audioQueryJson);

    if (!replaceJsonFloat(queryStr, "speedScale", speedScale)) {
        LOGI("Warning: speedScale key not found in AudioQuery JSON");
    }
    if (!replaceJsonFloat(queryStr, "pitchScale", pitchScale)) {
        LOGI("Warning: pitchScale key not found in AudioQuery JSON");
    }
    if (!replaceJsonFloat(queryStr, "intonationScale", intonationScale)) {
        LOGI("Warning: intonationScale key not found in AudioQuery JSON");
    }
    if (!replaceJsonFloat(queryStr, "volumeScale", volumeScale)) {
        LOGI("Warning: volumeScale key not found in AudioQuery JSON");
    }
    if (!replaceJsonFloat(queryStr, "prePhonemeLength", prePhonemeLength)) {
        LOGI("Warning: prePhonemeLength key not found in AudioQuery JSON");
    }
    if (!replaceJsonFloat(queryStr, "postPhonemeLength", postPhonemeLength)) {
        LOGI("Warning: postPhonemeLength key not found in AudioQuery JSON");
    }

    // Step 3: Synthesize WAV from the modified AudioQuery.
    VoicevoxSynthesisOptions synthOptions =
            voicevox_make_default_synthesis_options();

    uintptr_t wavLength = 0;
    uint8_t* wav = nullptr;

    result = voicevox_synthesizer_synthesis(
            g_synthesizer, queryStr.c_str(), styleId, synthOptions,
            &wavLength, &wav);
    if (result != VOICEVOX_RESULT_OK) {
        LOGE("Synthesis failed (text length=%zu): %s",
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
    LOGD("TTS params: speed=%.2f, pitch=%.2f, intonation=%.2f, volume=%.2f, prePh=%.2f, postPh=%.2f",
         speedScale, pitchScale, intonationScale, volumeScale,
         prePhonemeLength, postPhonemeLength);
    return javaWav;
}

JNIEXPORT void JNICALL
Java_com_example_comerune_speech_infrastructure_engine_NativeVoicevoxBridge_nativeRelease(
        JNIEnv* /* env */, jobject /* thiz */) {
    std::lock_guard<std::mutex> lock(g_mutex);

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
