import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'speech_engine.dart';
import 'voicevox_models.dart';

class VoicevoxHttpResponse {
  const VoicevoxHttpResponse({
    required this.statusCode,
    required this.bodyBytes,
  });

  final int statusCode;
  final Uint8List bodyBytes;

  String get bodyText => utf8.decode(bodyBytes);
}

abstract class VoicevoxTransport {
  Future<VoicevoxHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  });

  Future<VoicevoxHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    List<int>? bodyBytes,
  });

  Future<void> dispose();
}

class DartIoVoicevoxTransport implements VoicevoxTransport {
  DartIoVoicevoxTransport({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<VoicevoxHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return _send(
      method: 'GET',
      uri: uri,
      headers: headers,
    );
  }

  @override
  Future<VoicevoxHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    List<int>? bodyBytes,
  }) {
    return _send(
      method: 'POST',
      uri: uri,
      headers: headers,
      bodyBytes: bodyBytes,
    );
  }

  Future<VoicevoxHttpResponse> _send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const <String, String>{},
    List<int>? bodyBytes,
  }) async {
    final HttpClientRequest request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (bodyBytes != null) {
      request.add(bodyBytes);
    }

    final HttpClientResponse response = await request.close();
    final BytesBuilder bytesBuilder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      bytesBuilder.add(chunk);
    }

    return VoicevoxHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: bytesBuilder.takeBytes(),
    );
  }

  @override
  Future<void> dispose() async {
    _client.close(force: false);
  }
}

abstract class VoicevoxAudioPlayer {
  Future<void> playBytes(Uint8List bytes);

  Future<void> dispose();
}

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

class VoicevoxEngine implements SpeechEngine {
  VoicevoxEngine({
    VoicevoxEndpoint endpoint = const VoicevoxEndpoint(),
    VoicevoxSettingsResolver? settingsResolver,
    VoicevoxTransport? transport,
    VoicevoxAudioPlayer? audioPlayer,
  })  : _endpoint = endpoint,
        _settingsResolver =
            settingsResolver ?? (() => const VoicevoxSpeechSettings()),
        _transport = transport ?? DartIoVoicevoxTransport(),
        _audioPlayer = audioPlayer ?? AudioplayersVoicevoxAudioPlayer(),
        _ownsTransport = transport == null,
        _ownsAudioPlayer = audioPlayer == null;

  final VoicevoxEndpoint _endpoint;
  final VoicevoxSettingsResolver _settingsResolver;
  final VoicevoxTransport _transport;
  final VoicevoxAudioPlayer _audioPlayer;
  final bool _ownsTransport;
  final bool _ownsAudioPlayer;

  @override
  Future<void> speak(String text) async {
    final String normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return;
    }

    final VoicevoxSpeechSettings settings = _settingsResolver();
    try {
      final VoicevoxHttpResponse audioQueryResponse = await _transport.post(
        _endpoint.audioQueryUri(
          text: normalizedText,
          speakerId: settings.speakerId,
        ),
      );
      if (audioQueryResponse.statusCode != HttpStatus.ok) {
        _logSkip('audio_query failed: ${audioQueryResponse.statusCode}');
        return;
      }

      final dynamic decodedAudioQuery = jsonDecode(audioQueryResponse.bodyText);
      if (decodedAudioQuery is! Map<String, dynamic>) {
        _logSkip('audio_query response is not a JSON object');
        return;
      }

      _applyVoiceSettings(decodedAudioQuery, settings);

      final VoicevoxHttpResponse synthesisResponse = await _transport.post(
        _endpoint.synthesisUri(speakerId: settings.speakerId),
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        bodyBytes: utf8.encode(jsonEncode(decodedAudioQuery)),
      );
      if (synthesisResponse.statusCode != HttpStatus.ok) {
        _logSkip('synthesis failed: ${synthesisResponse.statusCode}');
        return;
      }
      if (synthesisResponse.bodyBytes.isEmpty) {
        _logSkip('synthesis returned empty audio');
        return;
      }

      await _audioPlayer.playBytes(synthesisResponse.bodyBytes);
    } catch (error, stackTrace) {
      _logSkip('voice synthesis/playback error: $error', stackTrace: stackTrace);
    }
  }

  Future<List<VoicevoxSpeakerOption>> fetchSpeakers() async {
    try {
      final VoicevoxHttpResponse response = await _transport.get(
        _endpoint.speakersUri,
      );
      if (response.statusCode != HttpStatus.ok) {
        log(
          'Failed to fetch speakers: ${response.statusCode}',
          name: 'VoicevoxEngine',
        );
        return _fallbackSpeakerOptions();
      }

      final dynamic decoded = jsonDecode(response.bodyText);
      if (decoded is! List<dynamic>) {
        log(
          'Failed to parse speakers: response is not a list',
          name: 'VoicevoxEngine',
        );
        return _fallbackSpeakerOptions();
      }

      final List<VoicevoxSpeakerOption> options = <VoicevoxSpeakerOption>[];
      for (final dynamic rawSpeaker in decoded) {
        if (rawSpeaker is! Map<String, dynamic>) {
          continue;
        }

        final String speakerName = rawSpeaker['name']?.toString() ?? '';
        final dynamic rawStyles = rawSpeaker['styles'];
        if (rawStyles is! List<dynamic>) {
          continue;
        }

        for (final dynamic rawStyle in rawStyles) {
          if (rawStyle is! Map<String, dynamic>) {
            continue;
          }

          final dynamic rawId = rawStyle['id'];
          if (rawId is! num) {
            continue;
          }

          final int id = rawId.toInt();
          final String styleName = rawStyle['name']?.toString() ?? '';
          final String label = _buildSpeakerLabel(
            speakerName: speakerName,
            styleName: styleName,
            fallbackId: id,
          );

          options.add(
            VoicevoxSpeakerOption(
              id: id,
              label: label,
            ),
          );
        }
      }

      if (options.isEmpty) {
        return _fallbackSpeakerOptions();
      }

      return options;
    } catch (error, stackTrace) {
      log(
        'Failed to fetch speakers: $error',
        name: 'VoicevoxEngine',
        stackTrace: stackTrace,
      );
      return _fallbackSpeakerOptions();
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsAudioPlayer) {
      await _audioPlayer.dispose();
    }
    if (_ownsTransport) {
      await _transport.dispose();
    }
  }

  void _applyVoiceSettings(
    Map<String, dynamic> queryJson,
    VoicevoxSpeechSettings settings,
  ) {
    queryJson['speedScale'] = settings.speedScale;
    queryJson['pitchScale'] = settings.pitchScale;
    queryJson['intonationScale'] = settings.intonationScale;
    queryJson['volumeScale'] = settings.volumeScale;
  }

  String _buildSpeakerLabel({
    required String speakerName,
    required String styleName,
    required int fallbackId,
  }) {
    final String trimmedSpeaker = speakerName.trim();
    final String trimmedStyle = styleName.trim();

    if (trimmedSpeaker.isEmpty && trimmedStyle.isEmpty) {
      return 'speaker:$fallbackId';
    }
    if (trimmedStyle.isEmpty) {
      return trimmedSpeaker;
    }
    if (trimmedSpeaker.isEmpty) {
      return trimmedStyle;
    }

    return '$trimmedSpeaker ($trimmedStyle)';
  }

  List<VoicevoxSpeakerOption> _fallbackSpeakerOptions() {
    return const <VoicevoxSpeakerOption>[VoicevoxSpeakerOption.fallback];
  }

  void _logSkip(String message, {StackTrace? stackTrace}) {
    log(
      message,
      name: 'VoicevoxEngine',
      stackTrace: stackTrace,
    );
  }
}
