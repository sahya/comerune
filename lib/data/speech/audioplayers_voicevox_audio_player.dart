import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../../domain/speech/voicevox_audio_player.dart';

class AudioplayersVoicevoxAudioPlayer implements VoicevoxAudioPlayer {
  AudioplayersVoicevoxAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    await _player.play(BytesSource(bytes));
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}
