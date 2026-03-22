class VoicevoxEndpoint {
  const VoicevoxEndpoint({
    this.host = defaultHost,
    this.port = defaultPort,
  });

  static const String defaultHost = '10.0.2.2';
  static const int defaultPort = 50021;

  final String host;
  final int port;

  Uri get _baseUri => Uri(
        scheme: 'http',
        host: host,
        port: port,
      );

  Uri audioQueryUri({
    required String text,
    required int speakerId,
  }) {
    return _baseUri.replace(
      path: '/audio_query',
      queryParameters: <String, String>{
        'text': text,
        'speaker': speakerId.toString(),
      },
    );
  }

  Uri synthesisUri({
    required int speakerId,
  }) {
    return _baseUri.replace(
      path: '/synthesis',
      queryParameters: <String, String>{
        'speaker': speakerId.toString(),
      },
    );
  }

  Uri get speakersUri {
    return _baseUri.replace(path: '/speakers');
  }
}

class VoicevoxSpeechSettings {
  const VoicevoxSpeechSettings({
    this.speakerId = 0,
    this.speedScale = 1.0,
    this.pitchScale = 0.0,
    this.intonationScale = 1.0,
    this.volumeScale = 1.0,
  });

  final int speakerId;
  final double speedScale;
  final double pitchScale;
  final double intonationScale;
  final double volumeScale;
}

class VoicevoxSpeakerOption {
  const VoicevoxSpeakerOption({
    required this.id,
    required this.label,
  });

  static const VoicevoxSpeakerOption fallback = VoicevoxSpeakerOption(
    id: 0,
    label: '取得失敗',
  );

  final int id;
  final String label;
}

typedef VoicevoxSettingsResolver = VoicevoxSpeechSettings Function();
