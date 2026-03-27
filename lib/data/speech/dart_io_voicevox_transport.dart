import 'dart:io';
import 'dart:typed_data';

import '../../domain/speech/voicevox_transport.dart';

class DartIoVoicevoxTransport implements VoicevoxTransport {
  DartIoVoicevoxTransport({
    HttpClient? client,
    Duration requestTimeout = const Duration(seconds: 5),
    Duration responseReadTimeout = const Duration(seconds: 5),
  })  : _client = client ?? HttpClient(),
        _requestTimeout = requestTimeout,
        _responseReadTimeout = responseReadTimeout {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be greater than zero',
      );
    }
    if (responseReadTimeout <= Duration.zero) {
      throw ArgumentError.value(
        responseReadTimeout,
        'responseReadTimeout',
        'must be greater than zero',
      );
    }
  }

  final HttpClient _client;
  final Duration _requestTimeout;
  final Duration _responseReadTimeout;

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
    final HttpClientRequest request =
        await _client.openUrl(method, uri).timeout(_requestTimeout);
    headers.forEach(request.headers.set);
    if (bodyBytes != null) {
      request.add(bodyBytes);
    }

    final HttpClientResponse response =
        await request.close().timeout(_requestTimeout);
    final BytesBuilder bytesBuilder = BytesBuilder(copy: false);
    await for (final List<int> chunk
        in response.timeout(_responseReadTimeout)) {
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
