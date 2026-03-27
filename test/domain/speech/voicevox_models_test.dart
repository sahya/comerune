import 'package:comerune/domain/speech/voicevox_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoicevoxSpeechSettings', () {
    test('accepts values within spec range', () {
      expect(
        () => VoicevoxSpeechSettings(
          speedScale: VoicevoxSpeechSettings.minSpeedScale,
          pitchScale: VoicevoxSpeechSettings.minPitchScale,
          intonationScale: VoicevoxSpeechSettings.maxIntonationScale,
          volumeScale: VoicevoxSpeechSettings.maxVolumeScale,
        ),
        returnsNormally,
      );
    });

    test('throws assertion when speedScale is out of range', () {
      expect(
        () => VoicevoxSpeechSettings(
          speedScale: VoicevoxSpeechSettings.minSpeedScale - 0.01,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws assertion when pitchScale is out of range', () {
      expect(
        () => VoicevoxSpeechSettings(
          pitchScale: VoicevoxSpeechSettings.maxPitchScale + 0.01,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws assertion when intonationScale is out of range', () {
      expect(
        () => VoicevoxSpeechSettings(
          intonationScale: VoicevoxSpeechSettings.maxIntonationScale + 0.01,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('throws assertion when volumeScale is out of range', () {
      expect(
        () => VoicevoxSpeechSettings(
          volumeScale: VoicevoxSpeechSettings.minVolumeScale - 0.01,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
