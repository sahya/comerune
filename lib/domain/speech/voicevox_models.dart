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
  })  : assert(
          speedScale >= minSpeedScale && speedScale <= maxSpeedScale,
          'speedScale must be in [$minSpeedScale, $maxSpeedScale]',
        ),
        assert(
          pitchScale >= minPitchScale && pitchScale <= maxPitchScale,
          'pitchScale must be in [$minPitchScale, $maxPitchScale]',
        ),
        assert(
          intonationScale >= minIntonationScale &&
              intonationScale <= maxIntonationScale,
          'intonationScale must be in [$minIntonationScale, $maxIntonationScale]',
        ),
        assert(
          volumeScale >= minVolumeScale && volumeScale <= maxVolumeScale,
          'volumeScale must be in [$minVolumeScale, $maxVolumeScale]',
        );

  static const double minSpeedScale = 0.5;
  static const double maxSpeedScale = 2.0;
  static const double minPitchScale = -0.15;
  static const double maxPitchScale = 0.15;
  static const double minIntonationScale = 0.0;
  static const double maxIntonationScale = 2.0;
  static const double minVolumeScale = 0.0;
  static const double maxVolumeScale = 2.0;

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
