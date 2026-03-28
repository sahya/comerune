import '../models/app_message.dart';
import 'ndgr_protobuf_decoder.dart';

class NdgrMessageNormalizer {
  int _fallbackSequence = 0;

  AppMessage? normalizeChunkedMessage(
    NdgrChunkedMessage source, {
    DateTime? receivedAt,
  }) {
    final NdgrChat? chat = source.chat;
    if (chat == null) {
      return null;
    }
    if (chat.content.isEmpty) {
      return null;
    }

    final DateTime timestamp =
        source.serverTimestamp ?? receivedAt ?? DateTime.now().toUtc();

    final String id = _resolveId(source.id, chat, timestamp);

    return AppMessage(
      id: id,
      timestamp: timestamp,
      userId: _resolveUserId(chat),
      userName: chat.name,
      content: chat.content,
      type: AppMessageType.chat,
      raw: source,
    );
  }

  String _resolveId(String? sourceId, NdgrChat chat, DateTime timestamp) {
    if (sourceId != null && sourceId.isNotEmpty) {
      return sourceId;
    }

    if (chat.no != null) {
      return 'ndgr-chat-${chat.no}';
    }

    _fallbackSequence += 1;
    return 'ndgr-${timestamp.microsecondsSinceEpoch}-$_fallbackSequence';
  }

  String? _resolveUserId(NdgrChat chat) {
    if (chat.rawUserId != null) {
      return chat.rawUserId.toString();
    }

    if (chat.hashedUserId != null && chat.hashedUserId!.isNotEmpty) {
      return chat.hashedUserId;
    }

    return null;
  }
}
