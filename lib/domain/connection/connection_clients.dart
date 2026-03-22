abstract class SessionWsClient {
  Future<SessionEndpoints> connectAndResolveEndpoints();

  Future<void> disconnect();
}

abstract class NdgrClient {
  Future<void> connect(Uri viewApiUri);

  Future<void> disconnect();
}

abstract class LegacyCommentClient {
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
