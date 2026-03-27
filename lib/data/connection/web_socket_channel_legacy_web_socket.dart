import 'package:comerune/domain/connection/legacy_comment_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketChannelLegacyWebSocket implements LegacyWebSocket {
  WebSocketChannelLegacyWebSocket(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<Object?> get stream => _channel.stream.cast<Object?>();

  @override
  Future<void> close([int? code, String? reason]) async {
    await _channel.sink.close(code, reason);
  }

  static Future<LegacyWebSocket> connect(String url) async {
    final Uri uri = Uri.parse(url);
    final WebSocketChannel channel = WebSocketChannel.connect(uri);
    return WebSocketChannelLegacyWebSocket(channel);
  }
}
