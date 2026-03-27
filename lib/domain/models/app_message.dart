enum AppMessageType {
  chat,
  operator,
  notification,
  gift,
  nicoad,
}

class AppMessage {
  const AppMessage({
    required this.id,
    required this.timestamp,
    this.userId,
    required this.content,
    required this.type,
    this.raw,
  });

  final String id;
  final DateTime timestamp;
  final String? userId;
  final String content;
  final AppMessageType type;
  final Object? raw;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is AppMessage &&
        other.id == id &&
        other.timestamp == timestamp &&
        other.userId == userId &&
        other.content == content &&
        other.type == type;
  }

  @override
  int get hashCode {
    return Object.hash(id, timestamp, userId, content, type);
  }
}
