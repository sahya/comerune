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
    required this.userId,
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
}
