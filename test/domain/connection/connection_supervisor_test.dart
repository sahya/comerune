import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/connection/connection_clients.dart';
import '../../../lib/domain/connection/connection_supervisor.dart';

void main() {
  group('ConnectionSupervisor', () {
    test('backoffDelayForAttempt returns exponential seconds and jitter', () {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(
              ndgrViewApiUri: Uri.parse('https://example.com/api/view/v4/stream'),
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
        jitterProvider: (int attempt) => Duration(milliseconds: attempt * 10),
      );
      addTearDown(supervisor.dispose);

      expect(
        supervisor.backoffDelayForAttempt(1),
        const Duration(seconds: 1, milliseconds: 10),
      );
      expect(
        supervisor.backoffDelayForAttempt(2),
        const Duration(seconds: 2, milliseconds: 20),
      );
      expect(
        supervisor.backoffDelayForAttempt(6),
        const Duration(seconds: 30, milliseconds: 60),
      );
      expect(
        supervisor.backoffDelayForAttempt(7),
        const Duration(seconds: 30, milliseconds: 70),
      );
    });

    test('does not reconnect when stopped by user', () async {
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            ndgrViewApiUri: Uri.parse('https://example.com/api/view/v4/stream'),
          ),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool stopped = await supervisor.stopByUser();
      expect(stopped, isTrue);
      expect(supervisor.status, ConnectionStatus.stopped);

      final bool reconnectTriggered = await supervisor.onNdgrStreamStalled();
      expect(reconnectTriggered, isFalse);
      expect(supervisor.reconnectCount, 0);
      expect(ndgrClient.connectCalls, 1);
    });

    test('reconnects NDGR stall with same URI after disconnecting old stream', () async {
      final Uri ndgrUri = Uri.parse('https://example.com/api/view/v4/stream');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            ndgrViewApiUri: ndgrUri,
          ),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool reconnected = await supervisor.onNdgrStreamStalled();
      expect(reconnected, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 1);
      expect(ndgrClient.disconnectCalls, 1);
      expect(ndgrClient.connectCalls, 2);
      expect(ndgrClient.connectedUris, <Uri>[ndgrUri, ndgrUri]);
    });

    test('does not reconnect when broadcast ended', () async {
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            legacyWsUrl: Uri.parse('wss://example.com/legacy'),
          ),
        ],
      );
      final FakeLegacyCommentClient legacyClient = FakeLegacyCommentClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: legacyClient,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      final bool ended = await supervisor.endBroadcast();
      expect(ended, isTrue);
      expect(supervisor.status, ConnectionStatus.ended);

      final bool reconnectTriggered = await supervisor.onLegacyWsDisconnected();
      expect(reconnectTriggered, isFalse);
      expect(supervisor.reconnectCount, 0);
      expect(legacyClient.connectCalls, 1);
    });

    test('reconnects legacy WS with same URL after disconnecting old stream', () async {
      final Uri legacyUrl = Uri.parse('wss://example.com/legacy');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            legacyWsUrl: legacyUrl,
          ),
        ],
      );
      final FakeLegacyCommentClient legacyClient = FakeLegacyCommentClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: legacyClient,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      final bool reconnected = await supervisor.onLegacyWsDisconnected();
      expect(reconnected, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);
      expect(supervisor.reconnectCount, 1);
      expect(legacyClient.disconnectCalls, 1);
      expect(legacyClient.connectCalls, 2);
      expect(legacyClient.connectedUris, <Uri>[legacyUrl, legacyUrl]);
    });

    test('reconnects session WS path after disconnecting active clients', () async {
      final Uri firstNdgrUri = Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondNdgrUri = Uri.parse('https://example.com/api/view/v4/stream/2');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstNdgrUri),
          SessionEndpoints(ndgrViewApiUri: secondNdgrUri),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient();
      final FakeLegacyCommentClient legacyClient = FakeLegacyCommentClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: legacyClient,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(ndgrClient.connectedUris.last, firstNdgrUri);

      final bool reconnected = await supervisor.onSessionWsDisconnected();
      expect(reconnected, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 1);
      expect(sessionWsClient.connectCalls, 2);
      expect(sessionWsClient.disconnectCalls, 1);
      expect(ndgrClient.disconnectCalls, 1);
      expect(legacyClient.disconnectCalls, 1);
      expect(ndgrClient.connectedUris.last, secondNdgrUri);
    });

    test('legacy reconnect falls back to session after 3 consecutive failures', () async {
      final Uri originalLegacyUrl = Uri.parse('wss://example.com/legacy/1');
      final Uri refreshedLegacyUrl = Uri.parse('wss://example.com/legacy/2');

      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(legacyWsUrl: originalLegacyUrl),
          SessionEndpoints(legacyWsUrl: refreshedLegacyUrl),
        ],
      );
      final FakeLegacyCommentClient legacyClient = FakeLegacyCommentClient(
        connectResults: <bool>[true, false, false, false, true],
      );

      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: legacyClient,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      final bool reconnected = await supervisor.onLegacyWsDisconnected();
      expect(reconnected, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);
      expect(supervisor.reconnectCount, 4);
      expect(sessionWsClient.connectCalls, 2);
      expect(sessionWsClient.disconnectCalls, 1);
      expect(legacyClient.disconnectCalls, 4);
      expect(legacyClient.connectedUris.last, refreshedLegacyUrl);
    });

    test('moves to failed when max reconnect attempts are exceeded', () async {
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            ndgrViewApiUri: Uri.parse('https://example.com/api/view/v4/stream'),
          ),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient(
        connectResults: <bool>[true, false, false],
      );

      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        maxReconnectAttempts: 2,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool reconnected = await supervisor.onNdgrStreamStalled();
      expect(reconnected, isFalse);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.reconnectCount, 2);
      expect(supervisor.lastError, ConnectionErrorCode.ndgrStreamFailed);
    });

    test('auto reconnects when NDGR stall event is emitted', () async {
      final Uri ndgrUri = Uri.parse('https://example.com/api/view/v4/stream');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: ndgrUri),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      const NdgrResumeCursor cursor = NdgrResumeCursor(
        at: 'now',
        next: 'segment-1',
      );
      ndgrClient.emitStalled(resumeCursor: cursor);
      await _drainEventLoop();

      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 1);
      expect(ndgrClient.disconnectCalls, 1);
      expect(ndgrClient.connectCalls, 2);
      expect(ndgrClient.connectedResumeCursors.last?.at, 'now');
      expect(ndgrClient.connectedResumeCursors.last?.next, 'segment-1');
    });

    test('auto transitions to ENDED when session broadcast ended event is emitted', () async {
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            legacyWsUrl: Uri.parse('wss://example.com/legacy'),
          ),
        ],
      );
      final FakeLegacyCommentClient legacyClient = FakeLegacyCommentClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: legacyClient,
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await supervisor.startConnection();
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      sessionWsClient.emitBroadcastEnded();
      await _drainEventLoop();

      expect(supervisor.status, ConnectionStatus.ended);
      expect(supervisor.lastError, ConnectionErrorCode.broadcastEnded);

      legacyClient.emitDisconnected();
      await _drainEventLoop();
      expect(supervisor.reconnectCount, 0);
    });
  });
}

Future<void> _drainEventLoop() async {
  for (int i = 0; i < 6; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeSessionWsClient implements SessionWsClient {
  FakeSessionWsClient({
    required this.endpointsQueue,
  });

  final List<SessionEndpoints> endpointsQueue;
  final StreamController<SessionWsEvent> _eventsController =
      StreamController<SessionWsEvent>.broadcast();

  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<SessionWsEvent> get events => _eventsController.stream;

  @override
  Future<SessionEndpoints> connectAndResolveEndpoints() async {
    connectCalls += 1;
    if (endpointsQueue.isEmpty) {
      throw StateError('No endpoints configured');
    }
    return endpointsQueue.removeAt(0);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  void emitDisconnected() {
    _eventsController.add(const SessionWsEvent(SessionWsEventType.disconnected));
  }

  void emitBroadcastEnded() {
    _eventsController.add(const SessionWsEvent(SessionWsEventType.broadcastEnded));
  }
}

class FakeNdgrClient implements NdgrClient {
  FakeNdgrClient({
    List<bool>? connectResults,
  }) : _connectResults = connectResults ?? <bool>[];

  final List<bool> _connectResults;
  final StreamController<NdgrEvent> _eventsController =
      StreamController<NdgrEvent>.broadcast();
  final List<Uri> connectedUris = <Uri>[];
  final List<NdgrResumeCursor?> connectedResumeCursors = <NdgrResumeCursor?>[];
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<NdgrEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(
    Uri viewApiUri, {
    NdgrResumeCursor? resumeCursor,
  }) async {
    connectCalls += 1;
    connectedUris.add(viewApiUri);
    connectedResumeCursors.add(resumeCursor);

    if (_connectResults.isEmpty) {
      return;
    }

    final bool shouldSucceed = _connectResults.removeAt(0);
    if (!shouldSucceed) {
      throw StateError('NDGR connect failed');
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  void emitDisconnected() {
    _eventsController.add(const NdgrEvent(NdgrEventType.disconnected));
  }

  void emitStalled({
    NdgrResumeCursor? resumeCursor,
  }) {
    _eventsController.add(
      NdgrEvent(
        NdgrEventType.stalled,
        resumeCursor: resumeCursor,
      ),
    );
  }
}

class FakeLegacyCommentClient implements LegacyCommentClient {
  FakeLegacyCommentClient({
    List<bool>? connectResults,
  }) : _connectResults = connectResults ?? <bool>[];

  final List<bool> _connectResults;
  final StreamController<LegacyCommentEvent> _eventsController =
      StreamController<LegacyCommentEvent>.broadcast();
  final List<Uri> connectedUris = <Uri>[];
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<LegacyCommentEvent> get events => _eventsController.stream;

  @override
  Future<void> connect(Uri wsUrl) async {
    connectCalls += 1;
    connectedUris.add(wsUrl);

    if (_connectResults.isEmpty) {
      return;
    }

    final bool shouldSucceed = _connectResults.removeAt(0);
    if (!shouldSucceed) {
      throw StateError('legacy connect failed');
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  void emitDisconnected() {
    _eventsController.add(
      const LegacyCommentEvent(LegacyCommentEventType.disconnected),
    );
  }
}
