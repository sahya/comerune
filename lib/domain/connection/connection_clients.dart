enum SessionWsEventType {
  disconnected,
  broadcastEnded,
}

class SessionWsEvent {
  const SessionWsEvent(this.type);

  final SessionWsEventType type;
}

enum SessionWsConnectFailureKind {
  connectFailed,
  endpointResolveTimeout,
  endpointParseFailed,
  broadcastEnded,
}

class SessionWsConnectException implements Exception {
  const SessionWsConnectException(
    this.kind, {
    this.cause,
  });

  final SessionWsConnectFailureKind kind;
  final Object? cause;
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

class NdgrResumeCursor {
  const NdgrResumeCursor({
    this.at,
    this.next,
  });

  final String? at;
  final String? next;
}

class NdgrEvent {
  const NdgrEvent(
    this.type, {
    this.resumeCursor,
  });

  final NdgrEventType type;
  final NdgrResumeCursor? resumeCursor;
}

abstract class NdgrClient {
  Stream<NdgrEvent> get events;

  Future<void> connect(
    Uri viewApiUri, {
    NdgrResumeCursor? resumeCursor,
  });

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
