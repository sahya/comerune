import 'dart:convert';
import 'dart:typed_data';

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
