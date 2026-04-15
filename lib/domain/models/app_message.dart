const String kSystemBroadcastEndedMessageIdPrefix = 'system:broadcast_ended:';

/// Builds a unique system notification ID for broadcast-ended events.
///
/// `sequence` is appended to avoid ID collisions when multiple notifications
/// are created in the same millisecond.
String buildBroadcastEndedNotificationId({
  required int epochMilliseconds,
  required int sequence,
}) {
  return '$kSystemBroadcastEndedMessageIdPrefix$epochMilliseconds:$sequence';
}

enum AppMessageType {
  chat,
  operator,
  notification,
  system,
  emotion,
  gift,
  nicoad,
}

class AppMessage {
  const AppMessage({
    required this.id,
    required this.timestamp,
    this.userId,
    this.userName,
    required this.content,
    required this.type,
    this.raw,
  });

  final String id;
  final DateTime timestamp;
  final String? userId;

  /// User nickname from the NDGR protobuf (chat.name field).
  final String? userName;
  final String content;
  final AppMessageType type;
  final Object? raw;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AppMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
