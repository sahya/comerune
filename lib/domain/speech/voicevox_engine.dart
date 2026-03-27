import 'dart:convert';
import 'dart:developer';

import 'speech_engine.dart';
import 'voicevox_audio_player.dart';
import 'voicevox_models.dart';
import 'voicevox_transport.dart';

class VoicevoxEngine implements SpeechEngine {
  VoicevoxEngine({
    VoicevoxEndpoint endpoint = const VoicevoxEndpoint(),
    VoicevoxSettingsResolver? settingsResolver,
    required VoicevoxTransport transport,
    required VoicevoxAudioPlayer audioPlayer,
  })  : _endpoint = endpoint,
        _settingsResolver =
            settingsResolver ?? (() => const VoicevoxSpeechSettings()),
        _transport = transport,
        _audioPlayer = audioPlayer;

  static const int _httpStatusOk = 200;
  static const String _jsonContentType = 'application/json';

  final VoicevoxEndpoint _endpoint;
  final VoicevoxSettingsResolver _settingsResolver;
  final VoicevoxTransport _transport;
  final VoicevoxAudioPlayer _audioPlayer;

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
      if (audioQueryResponse.statusCode != _httpStatusOk) {
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
        headers: const <String, String>{
          'content-type': _jsonContentType,
        },
        bodyBytes: utf8.encode(jsonEncode(decodedAudioQuery)),
      );
      if (synthesisResponse.statusCode != _httpStatusOk) {
        _logSkip('synthesis failed: ${synthesisResponse.statusCode}');
        return;
      }
      if (synthesisResponse.bodyBytes.isEmpty) {
        _logSkip('synthesis returned empty audio');
        return;
      }

      await _audioPlayer.playBytes(synthesisResponse.bodyBytes);
    } catch (error, stackTrace) {
      _logSkip(
        'voice synthesis/playback error: $error',
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<VoicevoxSpeakerOption>> fetchSpeakers() async {
    try {
      final VoicevoxHttpResponse response = await _transport.get(
        _endpoint.speakersUri,
      );
      if (response.statusCode != _httpStatusOk) {
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
    await _audioPlayer.dispose();
    await _transport.dispose();
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
