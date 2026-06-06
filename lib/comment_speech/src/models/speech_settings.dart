import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'replace_rule.dart';

/// VOICEVOX synthesis mode.
///
/// - [audioQuery]: Two-step AudioQuery → Synthesis path. Supports speed/pitch/
///   intonation/volume parameters. Higher quality but slower.
/// - [oneShot]: Single-step TTS path. Faster but ignores all audio parameters.
enum SynthesisMode {
  audioQuery,
  oneShot;

  String get storageValue {
    switch (this) {
      case SynthesisMode.audioQuery:
        return 'AUDIO_QUERY';
      case SynthesisMode.oneShot:
        return 'ONE_SHOT';
    }
  }

  String get label {
    switch (this) {
      case SynthesisMode.audioQuery:
        return '高品質（AudioQuery）';
      case SynthesisMode.oneShot:
        return '低遅延（ワンショット）';
    }
  }

  static SynthesisMode fromStorageValue(String? raw) {
    switch (raw) {
      case 'ONE_SHOT':
        return SynthesisMode.oneShot;
      case 'AUDIO_QUERY':
      case null:
        return SynthesisMode.audioQuery;
      default:
        // 未知の値（旧バージョンの保存値・破損値・改ざん）は黙ってデフォルト
        // へフォールバックする。例外を投げると `SettingsStore.load()` 全体が
        // 失敗し、設定画面が無限スピナーや空表示になりかねないため、ここで
        // 必ず安全な値を返す。観測性のためログだけ残す。
        developer.log(
          'Unknown SynthesisMode storage value: "$raw", '
          'falling back to AUDIO_QUERY',
          name: 'SynthesisMode',
        );
        return SynthesisMode.audioQuery;
    }
  }
}

abstract class SpeechEngineType {
  static const String voicevox = 'voicevox';
  static const String androidTts = 'android_tts';
}

/// Configuration for the speech engine. Defaults match the Kotlin side.
class SpeechSettings {
  final bool enabled;
  final String engineType;
  final SynthesisMode synthesisMode;
  final int speakerId;
  final double speedScale;
  final double pitchScale;
  final double intonationScale;
  final double volumeScale;
  final double prePhonemeLength;
  final double postPhonemeLength;
  final int maxTextLength;
  final int maxQueueSize;
  final int duplicateWindowMs;
  final bool skipEmojiOnly;
  final bool skipUrlOnly;
  final String replaceUrlWith;
  final String trimLongTextSuffix;
  final List<ReplaceRule> dictionaryRules;
  final List<String> ngWords;
  final String playerType;
  final double androidTtsSpeed;
  final double androidTtsPitch;
  final double androidTtsVolume;

  /// Issue #965: safety-net timeout for a single Android TTS utterance in
  /// milliseconds. Mirrors the Kotlin-side `SpeechSettings.speakTimeoutMs`.
  /// Default 15000 matches the historical hardcoded value preserved by
  /// PR #963; advanced callers can extend it for slow devices / long
  /// utterances without touching native code.
  final int speakTimeoutMs;

  const SpeechSettings({
    this.enabled = true,
    this.engineType = 'voicevox',
    this.synthesisMode = SynthesisMode.audioQuery,
    this.speakerId = 10004, // VOICEVOX Nemo・女声3（UI の voicevoxSpeaker と同期）
    this.speedScale = 1.15,
    this.pitchScale = 0.0,
    this.intonationScale = 1.0,
    this.volumeScale = 0.7,
    this.prePhonemeLength = 0.1,
    this.postPhonemeLength = 0.1,
    this.maxTextLength = 50,
    this.maxQueueSize = 20,
    this.duplicateWindowMs = 5000,
    this.skipEmojiOnly = true,
    this.skipUrlOnly = true,
    this.replaceUrlWith = 'URL省略',
    this.trimLongTextSuffix = '、以下省略',
    this.dictionaryRules = const [],
    this.ngWords = const [],
    this.playerType = 'audio_track',
    this.androidTtsSpeed = 1.0,
    this.androidTtsPitch = 1.0,
    this.androidTtsVolume = 1.0,
    this.speakTimeoutMs = 15000,
  });

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'engineType': engineType,
    'synthesisMode': synthesisMode.storageValue,
    'speakerId': speakerId,
    'speedScale': speedScale,
    'pitchScale': pitchScale,
    'intonationScale': intonationScale,
    'volumeScale': volumeScale,
    'prePhonemeLength': prePhonemeLength,
    'postPhonemeLength': postPhonemeLength,
    'maxTextLength': maxTextLength,
    'maxQueueSize': maxQueueSize,
    'duplicateWindowMs': duplicateWindowMs,
    'skipEmojiOnly': skipEmojiOnly,
    'skipUrlOnly': skipUrlOnly,
    'replaceUrlWith': replaceUrlWith,
    'trimLongTextSuffix': trimLongTextSuffix,
    'dictionaryRules': dictionaryRules.map((r) => r.toMap()).toList(),
    'ngWords': ngWords,
    'playerType': playerType,
    'androidTtsSpeed': androidTtsSpeed,
    'androidTtsPitch': androidTtsPitch,
    'androidTtsVolume': androidTtsVolume,
    'speakTimeoutMs': speakTimeoutMs,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeechSettings &&
          enabled == other.enabled &&
          engineType == other.engineType &&
          synthesisMode == other.synthesisMode &&
          speakerId == other.speakerId &&
          speedScale == other.speedScale &&
          pitchScale == other.pitchScale &&
          intonationScale == other.intonationScale &&
          volumeScale == other.volumeScale &&
          prePhonemeLength == other.prePhonemeLength &&
          postPhonemeLength == other.postPhonemeLength &&
          maxTextLength == other.maxTextLength &&
          maxQueueSize == other.maxQueueSize &&
          duplicateWindowMs == other.duplicateWindowMs &&
          skipEmojiOnly == other.skipEmojiOnly &&
          skipUrlOnly == other.skipUrlOnly &&
          replaceUrlWith == other.replaceUrlWith &&
          trimLongTextSuffix == other.trimLongTextSuffix &&
          listEquals(dictionaryRules, other.dictionaryRules) &&
          listEquals(ngWords, other.ngWords) &&
          playerType == other.playerType &&
          androidTtsSpeed == other.androidTtsSpeed &&
          androidTtsPitch == other.androidTtsPitch &&
          androidTtsVolume == other.androidTtsVolume &&
          speakTimeoutMs == other.speakTimeoutMs;

  @override
  int get hashCode => Object.hashAll([
    enabled,
    engineType,
    synthesisMode,
    speakerId,
    speedScale,
    pitchScale,
    intonationScale,
    volumeScale,
    prePhonemeLength,
    postPhonemeLength,
    maxTextLength,
    maxQueueSize,
    duplicateWindowMs,
    skipEmojiOnly,
    skipUrlOnly,
    replaceUrlWith,
    trimLongTextSuffix,
    Object.hashAll(dictionaryRules),
    Object.hashAll(ngWords),
    playerType,
    androidTtsSpeed,
    androidTtsPitch,
    androidTtsVolume,
    speakTimeoutMs,
  ]);
}
