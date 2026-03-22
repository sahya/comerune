import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/speech/voicevox_engine.dart';
import '../../../lib/domain/speech/voicevox_models.dart';

void main() {
  group('VoicevoxEngine.speak', () {
    test('calls /audio_query then /synthesis and plays synthesized audio', () async {
      final FakeVoicevoxTransport transport = FakeVoicevoxTransport();
      final FakeVoicevoxAudioPlayer audioPlayer = FakeVoicevoxAudioPlayer();

      transport.enqueuePost(
        '/audio_query',
        _jsonResponse(<String, dynamic>{
          'accent_phrases': <Object?>[],
        }),
      );
      transport.enqueuePost(
        '/synthesis',
        VoicevoxHttpResponse(
          statusCode: 200,
          bodyBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      );

      final VoicevoxEngine engine = VoicevoxEngine(
        endpoint: const VoicevoxEndpoint(host: 'voicevox.local', port: 50021),
        settingsResolver: () => const VoicevoxSpeechSettings(
          speakerId: 7,
          speedScale: 1.3,
          pitchScale: 0.1,
          intonationScale: 1.4,
          volumeScale: 1.2,
        ),
        transport: transport,
        audioPlayer: audioPlayer,
      );

      await engine.speak('hello voicevox');

      expect(transport.requests.length, 2);
      expect(transport.requests[0].method, 'POST');
      expect(transport.requests[0].uri.path, '/audio_query');
      expect(transport.requests[0].uri.queryParameters['text'], 'hello voicevox');
      expect(transport.requests[0].uri.queryParameters['speaker'], '7');

      expect(transport.requests[1].method, 'POST');
      expect(transport.requests[1].uri.path, '/synthesis');
      expect(transport.requests[1].uri.queryParameters['speaker'], '7');

      final Map<String, dynamic> synthesisPayload = jsonDecode(
        utf8.decode(transport.requests[1].bodyBytes!),
      ) as Map<String, dynamic>;
      expect(synthesisPayload['speedScale'], 1.3);
      expect(synthesisPayload['pitchScale'], 0.1);
      expect(synthesisPayload['intonationScale'], 1.4);
      expect(synthesisPayload['volumeScale'], 1.2);

      expect(audioPlayer.playedBytes.length, 1);
      expect(audioPlayer.playedBytes.single, <int>[1, 2, 3, 4]);
    });

    test('skips speaking when /audio_query fails', () async {
      final FakeVoicevoxTransport transport = FakeVoicevoxTransport();
      final FakeVoicevoxAudioPlayer audioPlayer = FakeVoicevoxAudioPlayer();

      transport.enqueuePost(
        '/audio_query',
        VoicevoxHttpResponse(
          statusCode: 500,
          bodyBytes: Uint8List.fromList(utf8.encode('error')),
        ),
      );

      final VoicevoxEngine engine = VoicevoxEngine(
        transport: transport,
        audioPlayer: audioPlayer,
      );

      await engine.speak('will be skipped');

      expect(transport.requests.length, 1);
      expect(transport.requests.single.uri.path, '/audio_query');
      expect(audioPlayer.playedBytes, isEmpty);
    });
  });

  group('VoicevoxEngine.fetchSpeakers', () {
    test('returns speaker options parsed from /speakers styles', () async {
      final FakeVoicevoxTransport transport = FakeVoicevoxTransport();
      final VoicevoxEngine engine = VoicevoxEngine(
        transport: transport,
        audioPlayer: FakeVoicevoxAudioPlayer(),
      );

      transport.enqueueGet(
        '/speakers',
        _jsonResponse(<Object?>[
          <String, Object?>{
            'name': '四国めたん',
            'styles': <Object?>[
              <String, Object?>{'id': 0, 'name': 'あまあま'},
              <String, Object?>{'id': 2, 'name': 'ノーマル'},
            ],
          },
        ]),
      );

      final List<VoicevoxSpeakerOption> speakers = await engine.fetchSpeakers();

      expect(speakers.length, 2);
      expect(speakers[0].id, 0);
      expect(speakers[0].label, '四国めたん (あまあま)');
      expect(speakers[1].id, 2);
      expect(speakers[1].label, '四国めたん (ノーマル)');
    });

    test('falls back to ID=0 when /speakers fails', () async {
      final FakeVoicevoxTransport transport = FakeVoicevoxTransport();
      transport.throwOnGet('/speakers', StateError('connection refused'));

      final VoicevoxEngine engine = VoicevoxEngine(
        transport: transport,
        audioPlayer: FakeVoicevoxAudioPlayer(),
      );

      final List<VoicevoxSpeakerOption> speakers = await engine.fetchSpeakers();

      expect(speakers.length, 1);
      expect(speakers.single.id, 0);
      expect(speakers.single.label, '取得失敗');
    });
  });
}

class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.bodyBytes,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int>? bodyBytes;
}

class FakeVoicevoxTransport implements VoicevoxTransport {
  final List<RecordedRequest> requests = <RecordedRequest>[];
  final Map<String, Queue<VoicevoxHttpResponse>> _getResponses =
      <String, Queue<VoicevoxHttpResponse>>{};
  final Map<String, Queue<VoicevoxHttpResponse>> _postResponses =
      <String, Queue<VoicevoxHttpResponse>>{};
  final Map<String, Object> _getErrors = <String, Object>{};
  final Map<String, Object> _postErrors = <String, Object>{};

  void enqueueGet(String path, VoicevoxHttpResponse response) {
    _getResponses.putIfAbsent(path, Queue<VoicevoxHttpResponse>.new).add(response);
  }

  void enqueuePost(String path, VoicevoxHttpResponse response) {
    _postResponses.putIfAbsent(path, Queue<VoicevoxHttpResponse>.new).add(response);
  }

  void throwOnGet(String path, Object error) {
    _getErrors[path] = error;
  }

  void throwOnPost(String path, Object error) {
    _postErrors[path] = error;
  }

  @override
  Future<VoicevoxHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    requests.add(RecordedRequest(method: 'GET', uri: uri, headers: headers));
    final Object? error = _getErrors[uri.path];
    if (error != null) {
      throw error;
    }

    final Queue<VoicevoxHttpResponse>? queue = _getResponses[uri.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('No fake GET response for ${uri.path}');
    }

    return queue.removeFirst();
  }

  @override
  Future<VoicevoxHttpResponse> post(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    List<int>? bodyBytes,
  }) async {
    requests.add(
      RecordedRequest(
        method: 'POST',
        uri: uri,
        headers: headers,
        bodyBytes: bodyBytes,
      ),
    );
    final Object? error = _postErrors[uri.path];
    if (error != null) {
      throw error;
    }

    final Queue<VoicevoxHttpResponse>? queue = _postResponses[uri.path];
    if (queue == null || queue.isEmpty) {
      throw StateError('No fake POST response for ${uri.path}');
    }

    return queue.removeFirst();
  }

  @override
  Future<void> dispose() async {}
}

class FakeVoicevoxAudioPlayer implements VoicevoxAudioPlayer {
  final List<List<int>> playedBytes = <List<int>>[];
  bool disposed = false;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playedBytes.add(bytes.toList(growable: false));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

VoicevoxHttpResponse _jsonResponse(Object json, {int statusCode = 200}) {
  return VoicevoxHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );
}
