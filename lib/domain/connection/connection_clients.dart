enum SessionWsEventType {
  disconnected,
  broadcastEnded,
}

class SessionWsEvent {
  const SessionWsEvent(this.type);

  final SessionWsEventType type;
}

abstract class SessionWsClient {
  Stream<SessionWsEvent> get events;

  Future<SessionEndpoints> connectAndResolveEndpoints();

  Future<void> disconnect();
}

enum NdgrEventType {
  disconnected,
  stalled,
}

class NdgrEvent {
  const NdgrEvent(this.type);

  final NdgrEventType type;
}

abstract class NdgrClient {
  Stream<NdgrEvent> get events;

  Future<void> connect(Uri viewApiUri);

  Future<void> disconnect();
}

enum LegacyCommentEventType {
  disconnected,
}

class LegacyCommentEvent {
  const LegacyCommentEvent(this.type);

  final LegacyCommentEventType type;
}

abstract class LegacyCommentClient {
  Stream<LegacyCommentEvent> get events;

  Future<void> connect(Uri wsUrl);

  Future<void> disconnect();
}

class SessionEndpoints {
  const SessionEndpoints({
    this.ndgrViewApiUri,
    this.legacyWsUrl,
  });

  final Uri? ndgrViewApiUri;
  final Uri? legacyWsUrl;
}
