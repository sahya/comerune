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

  // TODO(issue-2/O2): 現在は全 core フィールドで等価比較しているが、
  // TimelineStore の重複排除では id のみで十分な可能性がある。
  // 再接続時に同一メッセージの timestamp がサーバ時刻/受信時刻で異なると
  // 不一致になるリスクがあるため、TimelineStore 実装時に判断すること。
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
