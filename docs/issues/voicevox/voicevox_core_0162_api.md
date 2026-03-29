# VOICEVOX Core 0.16.2 API Reference and Design Decisions

## Header Location
- `android/app/src/main/cpp/include/voicevox_core.h` (57KB)

## ONNX Runtime Loading Mode
The header defines `VOICEVOX_LOAD_ONNXRUNTIME` (not `VOICEVOX_LINK_ONNXRUNTIME`).
This means we use `voicevox_onnxruntime_load_once()` to load ONNX Runtime dynamically at runtime, rather than `voicevox_onnxruntime_init_once()` which is for static linking (iOS only).

## Key API Functions Used

### Initialization Sequence
1. `voicevox_make_default_load_onnxruntime_options()` - get default ONNX RT options
2. `voicevox_onnxruntime_load_once(options, &onnxruntime)` - load ONNX Runtime
3. `voicevox_open_jtalk_rc_new(dict_dir, &open_jtalk)` - create OpenJTalk instance
4. `voicevox_make_default_initialize_options()` - get default synthesizer options
5. `voicevox_synthesizer_new(onnxruntime, open_jtalk, options, &synthesizer)` - create synthesizer

### Model Loading
6. `voicevox_voice_model_file_open(vvm_path, &model)` - open a VVM file
7. `voicevox_synthesizer_load_voice_model(synthesizer, model)` - load model into synthesizer
8. `voicevox_voice_model_file_delete(model)` - close the VVM file handle

### Synthesis
9. `voicevox_make_default_tts_options()` - get default TTS options
10. `voicevox_synthesizer_tts(synthesizer, text, style_id, options, &wav_length, &wav)` - TTS one-shot
11. `voicevox_wav_free(wav)` - free the WAV output buffer

### Cleanup
12. `voicevox_synthesizer_delete(synthesizer)` - destroy synthesizer
13. `voicevox_open_jtalk_rc_delete(open_jtalk)` - destroy OpenJTalk

### Error Handling
14. `voicevox_error_result_to_message(result_code)` - get human-readable error message

## Key Types
- `VoicevoxStyleId` = `uint32_t` (maps to speakerId in our Kotlin layer)
- `VoicevoxVoiceModelId` = `const uint8_t (*)[16]` (16-byte UUID, used for model load checks)
- `VoicevoxResultCode` = `int32_t` (0 = OK)
- `VoicevoxTtsOptions` = `{ bool enable_interrogative_upspeak; }` (only field in 0.16.2)

## Design Decisions

### Q13: TTS Method - One-shot (`voicevox_synthesizer_tts`)
We use the one-shot TTS approach (`voicevox_synthesizer_tts`) rather than the two-step `audio_query` -> `synthesis` path. This is simpler and sufficient for the initial implementation. The one-shot API does NOT support speed/pitch/intonation/volume control. Those parameters are accepted in the JNI bridge signature for forward compatibility but are currently ignored.

**Future enhancement**: Switch to `voicevox_synthesizer_create_audio_query` + JSON manipulation + `voicevox_synthesizer_synthesis` to enable speed/pitch/intonation/volume control.

### Q14: Speaker ID - Direct styleId
The `speakerId` in `SpeechRequest` maps directly to `VoicevoxStyleId` (uint32_t). No additional mapping layer is needed.

### Q15: Default VVM
All `.vvm` files found in the `voicevox_models` asset directory are loaded at initialization time. The default speaker ID comes from `VoicevoxConfig.defaultSpeakerId`.

### Model Load Check Limitation
`voicevox_synthesizer_is_loaded_voice_model` takes a `VoicevoxVoiceModelId` (16-byte UUID), not a styleId. Since we don't maintain a styleId-to-modelId mapping, `nativeIsModelLoaded(speakerId)` currently just checks whether the synthesizer is initialized. A more precise implementation would require parsing the model metadata JSON to build this mapping.
