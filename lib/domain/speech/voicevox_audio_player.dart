import 'dart:typed_data';

abstract class VoicevoxAudioPlayer {
  Future<void> playBytes(Uint8List bytes);

  Future<void> dispose();
}
