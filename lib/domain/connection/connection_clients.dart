abstract class SessionWsClient {
  Stream<void> get disconnected;

  Future<SessionEndpoints> connectAndResolveEndpoints();

  Future<void> disconnect();
}

abstract class NdgrClient {
  Stream<void> get stalled;

  Stream<Object> get nextAt;

  Future<void> connect(Uri viewApiUri, {Object at = 'now'});

  Future<void> disconnect();
}

abstract class LegacyCommentClient {
  Stream<void> get disconnected;

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
