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
      default:
        return SynthesisMode.audioQuery;
    }
  }
}

/// Configuration for the speech engine. Defaults match the Kotlin side.
class SpeechSettings {
  final bool enabled;
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

  const SpeechSettings({
    this.enabled = true,
    this.synthesisMode = SynthesisMode.audioQuery,
    this.speakerId = 10000, // VOICEVOX Nemo・男声2（UI の voicevoxSpeaker と同期）
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
  });

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
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
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeechSettings &&
          enabled == other.enabled &&
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
          listEquals(ngWords, other.ngWords);

  @override
  int get hashCode => Object.hash(
    enabled,
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
  );
}
