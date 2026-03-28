import 'replace_rule.dart';

/// Configuration for the speech engine. Defaults match the Kotlin side.
class SpeechSettings {
  final bool enabled;
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
    this.speakerId = 0,
    this.speedScale = 1.15,
    this.pitchScale = 0.0,
    this.intonationScale = 1.0,
    this.volumeScale = 1.0,
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
}
