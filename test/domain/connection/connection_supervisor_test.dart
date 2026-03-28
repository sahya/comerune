import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/connection_clients.dart';
import 'package:comerune/domain/connection/connection_supervisor.dart';

void main() {
  group('ConnectionSupervisor', () {
    test('status code mapping remains stable', () {
      expect(
        ConnectionStatus.values.map((ConnectionStatus status) => status.code),
        <String>[
          'IDLE',
          'CONNECTING_SESSION_WS',
          'RESOLVING_ENDPOINTS',
          'STREAMING_NDGR',
          'STREAMING_LEGACY',
          'RECONNECTING',
          'STOPPED',
          'ENDED',
          'FAILED',
        ],
      );
    });

    test('error code mapping remains stable', () {
      expect(
        ConnectionErrorCode.values.map((ConnectionErrorCode code) => code.code),
        <String>[
          'LV_PARSE_FAILED',
          'SESSION_WS_CONNECT_FAILED',
          'SESSION_WS_TIMEOUT',
          'ENDPOINT_RESOLVE_FAILED',
          'NDGR_STREAM_FAILED',
          'LEGACY_WS_FAILED',
          'SPEECH_BOUYOMI_FAILED',
          'SPEECH_VOICEVOX_FAILED',
          'USER_STOPPED',
          'BROADCAST_ENDED',
        ],
      );
    });

    test('wifi indicator mapping remains stable for all statuses', () {
      expect(ConnectionStatus.idle.usesGreenWifiIcon, isFalse);
      expect(ConnectionStatus.connectingSessionWs.usesGreenWifiIcon, isTrue);
      expect(ConnectionStatus.resolvingEndpoints.usesGreenWifiIcon, isTrue);
      expect(ConnectionStatus.streamingNdgr.usesGreenWifiIcon, isTrue);
      expect(ConnectionStatus.streamingLegacy.usesGreenWifiIcon, isTrue);
      expect(ConnectionStatus.reconnecting.usesGreenWifiIcon, isTrue);
      expect(ConnectionStatus.stopped.usesGreenWifiIcon, isFalse);
      expect(ConnectionStatus.ended.usesGreenWifiIcon, isFalse);
      expect(ConnectionStatus.failed.usesGreenWifiIcon, isFalse);
    });

    test('backoffDelayForAttempt returns exponential seconds and jitter', () {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(
              ndgrViewApiUri:
                  Uri.parse('https://example.com/api/view/v4/stream'),
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

    test('rejects invalid transition methods from idle', () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(
              ndgrViewApiUri:
                  Uri.parse('https://example.com/api/view/v4/stream'),
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool reset = supervisor.resetToIdle();
      expect(reset, isFalse);
      expect(supervisor.status, ConnectionStatus.idle);

      final bool ended = supervisor.endBroadcast();
      expect(ended, isFalse);
      expect(supervisor.status, ConnectionStatus.idle);
    });

    test('resetToIdle succeeds from ended', () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(
              ndgrViewApiUri:
                  Uri.parse('https://example.com/api/view/v4/stream'),
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);

      final bool ended = supervisor.endBroadcast();
      expect(ended, isTrue);
      expect(supervisor.status, ConnectionStatus.ended);

      final bool reset = supervisor.resetToIdle();
      expect(reset, isTrue);
      expect(supervisor.status, ConnectionStatus.idle);
    });

    test('startConnection works from FAILED and resets diagnostics', () async {
      final Uri firstUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondUri =
          Uri.parse('https://example.com/api/view/v4/stream/2');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstUri),
          SessionEndpoints(ndgrViewApiUri: secondUri),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient(
        connectResults: <bool>[true, false, true],
      );
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);

      final bool stalledReconnected = await supervisor.onNdgrStreamStalled();
      expect(stalledReconnected, isTrue);
      expect(supervisor.reconnectCount, 2);

      supervisor.recordReceivedAt(DateTime(2026, 1, 1));
      final bool failed = supervisor.fail(ConnectionErrorCode.ndgrStreamFailed);
      expect(failed, isTrue);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.canStartConnection, isTrue);

      final bool restarted = await _startAndDrain(supervisor);
      expect(restarted, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 0);
      expect(supervisor.lastError, isNull);
      expect(supervisor.lastReceivedAt, isNull);
      expect(ndgrClient.connectedUris.last, secondUri);
    });

    test('retryConnectionFromTerminal resets diagnostics and reconnects',
        () async {
      final Uri firstUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondUri =
          Uri.parse('https://example.com/api/view/v4/stream/2');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstUri),
          SessionEndpoints(ndgrViewApiUri: secondUri),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient(
        connectResults: <bool>[true, false, true],
      );
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.canRetryFromTerminal, isFalse);

      final bool reconnected = await supervisor.onNdgrStreamStalled();
      expect(reconnected, isTrue);
      expect(supervisor.reconnectCount, 2);

      supervisor.recordReceivedAt(DateTime(2026, 1, 1));
      final bool failed = supervisor.fail(ConnectionErrorCode.ndgrStreamFailed);
      expect(failed, isTrue);
      expect(supervisor.canRetryFromTerminal, isTrue);

      final bool retried = supervisor.retryConnectionFromTerminal();
      await _drainEventLoop();
      expect(retried, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 0);
      expect(supervisor.lastError, isNull);
      expect(supervisor.lastReceivedAt, isNull);
      expect(ndgrClient.connectedUris.last, secondUri);
    });

    test('retryConnectionFromTerminal is rejected outside terminal states',
        () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(
              ndgrViewApiUri:
                  Uri.parse('https://example.com/api/view/v4/stream'),
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool retried = supervisor.retryConnectionFromTerminal();
      expect(retried, isFalse);
      expect(supervisor.status, ConnectionStatus.idle);
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool stopped = supervisor.stopByUser();
      expect(stopped, isTrue);
      expect(supervisor.status, ConnectionStatus.stopped);

      final bool reconnectTriggered = await supervisor.onNdgrStreamStalled();
      expect(reconnectTriggered, isFalse);
      expect(supervisor.reconnectCount, 0);
      expect(ndgrClient.connectCalls, 1);
    });

    test('startConnection restarts from STOPPED via IDLE path', () async {
      final Uri firstUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondUri =
          Uri.parse('https://example.com/api/view/v4/stream/2');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstUri),
          SessionEndpoints(ndgrViewApiUri: secondUri),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool firstStart = await _startAndDrain(supervisor);
      expect(firstStart, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool stopped = supervisor.stopByUser();
      expect(stopped, isTrue);
      expect(supervisor.status, ConnectionStatus.stopped);

      final bool secondStart = await _startAndDrain(supervisor);
      expect(secondStart, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(ndgrClient.connectedUris.last, secondUri);
    });

    test('maps session endpoint resolve timeout to SESSION_WS_TIMEOUT',
        () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[],
          connectExceptions: <Object>[
            const SessionWsConnectException(
              SessionWsConnectFailureKind.endpointResolveTimeout,
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.lastError, ConnectionErrorCode.sessionWsTimeout);
    });

    test('maps session endpoint parse failure to ENDPOINT_RESOLVE_FAILED',
        () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[],
          connectExceptions: <Object>[
            const SessionWsConnectException(
              SessionWsConnectFailureKind.endpointParseFailed,
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.lastError, ConnectionErrorCode.endpointResolveFailed);
    });

    test('treats session broadcastEnded as ENDED during endpoint resolution',
        () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[],
          connectExceptions: <Object>[
            const SessionWsConnectException(
              SessionWsConnectFailureKind.broadcastEnded,
              cause: 'END_PROGRAM',
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.ended);
      expect(supervisor.lastError, ConnectionErrorCode.broadcastEnded);
      expect(supervisor.lastErrorDetail, contains('END_PROGRAM'));
    });

    test('preserves connectFailed cause for diagnostics', () async {
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[],
          connectExceptions: <Object>[
            SessionWsConnectException(
              SessionWsConnectFailureKind.connectFailed,
              cause: StateError('HandshakeException: 401 Unauthorized'),
            ),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.lastError, ConnectionErrorCode.sessionWsConnectFailed);
      expect(supervisor.lastErrorDetail, contains('HandshakeException'));
    });

    test('reconnects NDGR stall with same URI after disconnecting old stream',
        () async {
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

      final bool started = await _startAndDrain(supervisor);
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      final bool ended = supervisor.endBroadcast();
      expect(ended, isTrue);
      expect(supervisor.status, ConnectionStatus.ended);

      final bool reconnectTriggered = await supervisor.onLegacyWsDisconnected();
      expect(reconnectTriggered, isFalse);
      expect(supervisor.reconnectCount, 0);
      expect(legacyClient.connectCalls, 1);
    });

    test('reconnects legacy WS with same URL after disconnecting old stream',
        () async {
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

      final bool started = await _startAndDrain(supervisor);
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

    test('reconnects session WS path after disconnecting active clients',
        () async {
      final Uri firstNdgrUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondNdgrUri =
          Uri.parse('https://example.com/api/view/v4/stream/2');
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

      final bool started = await _startAndDrain(supervisor);
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

    test('auto reconnects when session disconnect event is emitted', () async {
      final Uri firstNdgrUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final Uri secondNdgrUri =
          Uri.parse('https://example.com/api/view/v4/stream/2');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstNdgrUri),
          SessionEndpoints(ndgrViewApiUri: secondNdgrUri),
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      sessionWsClient.emitDisconnected();
      await _drainEventLoop();

      expect(supervisor.status, ConnectionStatus.streamingNdgr);
      expect(supervisor.reconnectCount, 1);
      expect(sessionWsClient.connectCalls, 2);
      expect(ndgrClient.connectedUris.last, secondNdgrUri);
    });

    test(
        'stops reconnect loop immediately when session reconnect ends broadcast',
        () async {
      final Uri firstNdgrUri =
          Uri.parse('https://example.com/api/view/v4/stream/1');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(ndgrViewApiUri: firstNdgrUri),
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      sessionWsClient.queueConnectException(
        const SessionWsConnectException(
          SessionWsConnectFailureKind.broadcastEnded,
          cause: 'END_PROGRAM',
        ),
      );
      final bool reconnected = await supervisor.onSessionWsDisconnected();
      expect(reconnected, isFalse);
      expect(supervisor.status, ConnectionStatus.ended);
      expect(supervisor.lastError, ConnectionErrorCode.broadcastEnded);
      expect(supervisor.lastErrorDetail, contains('END_PROGRAM'));
      expect(supervisor.reconnectCount, 1);
    });

    test('legacy reconnect falls back to session after 3 consecutive failures',
        () async {
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

      final bool started = await _startAndDrain(supervisor);
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

    test('auto reconnects when legacy disconnect event is emitted', () async {
      final Uri legacyUrl = Uri.parse('wss://example.com/legacy');
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(legacyWsUrl: legacyUrl),
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingLegacy);

      legacyClient.emitDisconnected();
      await _drainEventLoop();

      expect(supervisor.status, ConnectionStatus.streamingLegacy);
      expect(supervisor.reconnectCount, 1);
      expect(legacyClient.disconnectCalls, 1);
      expect(legacyClient.connectCalls, 2);
      expect(legacyClient.connectedUris, <Uri>[legacyUrl, legacyUrl]);
    });

    test('reconnect loop stops when user stops during backoff delay', () async {
      final Uri ndgrUri = Uri.parse('https://example.com/api/view/v4/stream');
      final Completer<void> delayCompleter = Completer<void>();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(ndgrViewApiUri: ndgrUri),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) => delayCompleter.future,
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);

      final Future<bool> reconnectFuture = supervisor.onNdgrStreamStalled();
      await _drainEventLoop();
      expect(supervisor.status, ConnectionStatus.reconnecting);

      final bool stopped = supervisor.stopByUser();
      expect(stopped, isTrue);
      expect(supervisor.status, ConnectionStatus.stopped);

      delayCompleter.complete();
      final bool reconnectResult = await reconnectFuture;
      expect(reconnectResult, isFalse);
      expect(supervisor.status, ConnectionStatus.stopped);
    });

    test('reconnect loop stops when broadcast ends during backoff delay',
        () async {
      final Uri ndgrUri = Uri.parse('https://example.com/api/view/v4/stream');
      final Completer<void> delayCompleter = Completer<void>();
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: FakeSessionWsClient(
          endpointsQueue: <SessionEndpoints>[
            SessionEndpoints(ndgrViewApiUri: ndgrUri),
          ],
        ),
        ndgrClient: FakeNdgrClient(),
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) => delayCompleter.future,
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);

      final Future<bool> reconnectFuture = supervisor.onNdgrStreamStalled();
      await _drainEventLoop();
      expect(supervisor.status, ConnectionStatus.reconnecting);

      final bool ended = supervisor.endBroadcast();
      expect(ended, isTrue);
      expect(supervisor.status, ConnectionStatus.ended);

      delayCompleter.complete();
      final bool reconnectResult = await reconnectFuture;
      expect(reconnectResult, isFalse);
      expect(supervisor.status, ConnectionStatus.ended);
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

      final bool started = await _startAndDrain(supervisor);
      expect(started, isTrue);
      expect(supervisor.status, ConnectionStatus.streamingNdgr);

      final bool reconnected = await supervisor.onNdgrStreamStalled();
      expect(reconnected, isFalse);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.reconnectCount, 2);
      expect(supervisor.lastError, ConnectionErrorCode.ndgrStreamFailed);
    });

    test('uses 6 as default max reconnect attempts', () async {
      final FakeSessionWsClient sessionWsClient = FakeSessionWsClient(
        endpointsQueue: <SessionEndpoints>[
          SessionEndpoints(
            ndgrViewApiUri: Uri.parse('https://example.com/api/view/v4/stream'),
          ),
        ],
      );
      final FakeNdgrClient ndgrClient = FakeNdgrClient(
        connectResults: <bool>[true, false, false, false, false, false, false],
      );
      final ConnectionSupervisor supervisor = ConnectionSupervisor(
        sessionWsClient: sessionWsClient,
        ndgrClient: ndgrClient,
        legacyCommentClient: FakeLegacyCommentClient(),
        delayExecutor: (_) async {},
        jitterProvider: (_) => Duration.zero,
      );
      addTearDown(supervisor.dispose);

      expect(await _startAndDrain(supervisor), isTrue);
      expect(await supervisor.onNdgrStreamStalled(), isFalse);
      expect(supervisor.status, ConnectionStatus.failed);
      expect(supervisor.reconnectCount, 6);
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

      final bool started = await _startAndDrain(supervisor);
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

    test(
        'auto transitions to ENDED when session broadcast ended event is emitted',
        () async {
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

      final bool started = await _startAndDrain(supervisor);
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

Future<bool> _startAndDrain(ConnectionSupervisor supervisor) async {
  final bool started = supervisor.startConnection();
  await _drainEventLoop();
  return started;
}

Future<void> _drainEventLoop() async {
  for (int i = 0; i < 6; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeSessionWsClient implements SessionWsClient {
  FakeSessionWsClient({
    required this.endpointsQueue,
    List<Object>? connectExceptions,
  }) : _connectExceptions = connectExceptions ?? <Object>[];

  final List<SessionEndpoints> endpointsQueue;
  final List<Object> _connectExceptions;
  final StreamController<SessionWsEvent> _eventsController =
      StreamController<SessionWsEvent>.broadcast();

  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<SessionWsEvent> get events => _eventsController.stream;

  @override
  Future<SessionEndpoints> connectAndResolveEndpoints() async {
    connectCalls += 1;
    if (_connectExceptions.isNotEmpty) {
      throw _connectExceptions.removeAt(0);
    }
    if (endpointsQueue.isEmpty) {
      throw StateError('No endpoints configured');
    }
    return endpointsQueue.removeAt(0);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }

  void queueConnectException(Object exception) {
    _connectExceptions.add(exception);
  }

  void emitDisconnected() {
    _eventsController
        .add(const SessionWsEvent(SessionWsEventType.disconnected));
  }

  void emitBroadcastEnded() {
    _eventsController
        .add(const SessionWsEvent(SessionWsEventType.broadcastEnded));
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
