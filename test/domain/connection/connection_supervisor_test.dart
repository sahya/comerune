import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/connection/connection_supervisor.dart';

void main() {
  group('ConnectionStatus', () {
    test('has all 9 states', () {
      expect(ConnectionStatus.values.length, 9);
      expect(
        ConnectionStatus.values,
        <ConnectionStatus>[
          ConnectionStatus.idle,
          ConnectionStatus.connectingSessionWs,
          ConnectionStatus.resolvingEndpoints,
          ConnectionStatus.streamingNdgr,
          ConnectionStatus.streamingLegacy,
          ConnectionStatus.reconnecting,
          ConnectionStatus.stopped,
          ConnectionStatus.ended,
          ConnectionStatus.failed,
        ],
      );
    });
  });

  group('ConnectionErrorCode', () {
    test('has all 9 error codes', () {
      expect(ConnectionErrorCode.values.length, 9);
      expect(
        ConnectionErrorCode.values,
        <ConnectionErrorCode>[
          ConnectionErrorCode.lvParseFailed,
          ConnectionErrorCode.sessionWsConnectFailed,
          ConnectionErrorCode.endpointResolveFailed,
          ConnectionErrorCode.ndgrStreamFailed,
          ConnectionErrorCode.legacyWsFailed,
          ConnectionErrorCode.speechBouyomiFailed,
          ConnectionErrorCode.speechVoicevoxFailed,
          ConnectionErrorCode.userStopped,
          ConnectionErrorCode.broadcastEnded,
        ],
      );
    });
  });

  test('supports IDLE -> CONNECTING -> RESOLVING -> STREAMING_NDGR flow', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.status, ConnectionStatus.connectingSessionWs);

    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.status, ConnectionStatus.resolvingEndpoints);

    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(supervisor.status, ConnectionStatus.streamingNdgr);
    expect(supervisor.wifiIndicatorColor, WifiIndicatorColor.green);
  });

  test('supports IDLE -> CONNECTING -> RESOLVING -> STREAMING_LEGACY flow', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onLegacyEndpointResolved(), isTrue);
    expect(supervisor.status, ConnectionStatus.streamingLegacy);
    expect(supervisor.wifiIndicatorColor, WifiIndicatorColor.green);
  });

  test('supports STREAMING_* -> RECONNECTING -> CONNECTING_SESSION_WS flow', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);

    expect(
      supervisor.onStreamDisconnected(ConnectionErrorCode.ndgrStreamFailed),
      isTrue,
    );
    expect(supervisor.status, ConnectionStatus.reconnecting);
    expect(supervisor.reconnectCount, 1);
    expect(supervisor.lastError, ConnectionErrorCode.ndgrStreamFailed);

    expect(supervisor.reconnectViaSessionWs(), isTrue);
    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
  });

  test('transitions to STOPPED when stopped by user', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onLegacyEndpointResolved(), isTrue);

    expect(supervisor.stopByUser(), isTrue);
    expect(supervisor.status, ConnectionStatus.stopped);
    expect(supervisor.lastError, ConnectionErrorCode.userStopped);
    expect(supervisor.wifiIndicatorColor, WifiIndicatorColor.red);
  });

  test('transitions to ENDED when broadcast has ended', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);

    expect(supervisor.endBroadcast(), isTrue);
    expect(supervisor.status, ConnectionStatus.ended);
    expect(supervisor.lastError, ConnectionErrorCode.broadcastEnded);
    expect(supervisor.wifiIndicatorColor, WifiIndicatorColor.red);
  });

  test('supports user action to return from ENDED/FAILED to IDLE', () {
    final ConnectionSupervisor endedSupervisor = ConnectionSupervisor();
    expect(endedSupervisor.startConnection(), isTrue);
    expect(endedSupervisor.onSessionWsConnected(), isTrue);
    expect(endedSupervisor.onNdgrEndpointResolved(), isTrue);
    expect(endedSupervisor.endBroadcast(), isTrue);

    expect(endedSupervisor.resetToIdle(), isTrue);
    expect(endedSupervisor.status, ConnectionStatus.idle);

    final ConnectionSupervisor failedSupervisor = ConnectionSupervisor();
    expect(failedSupervisor.startConnection(), isTrue);
    expect(failedSupervisor.onSessionWsConnected(), isTrue);
    expect(
      failedSupervisor.fail(ConnectionErrorCode.endpointResolveFailed),
      isTrue,
    );

    expect(failedSupervisor.resetToIdle(), isTrue);
    expect(failedSupervisor.status, ConnectionStatus.idle);
  });

  test('supports start from ENDED/FAILED and resets diagnostics', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onNdgrEndpointResolved(), isTrue);
    expect(
      supervisor.onStreamDisconnected(ConnectionErrorCode.ndgrStreamFailed),
      isTrue,
    );
    supervisor.recordReceivedAt(DateTime.parse('2026-03-22T01:23:45Z'));
    expect(supervisor.fail(ConnectionErrorCode.endpointResolveFailed), isTrue);

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(supervisor.reconnectCount, 0);
    expect(supervisor.lastReceivedAt, isNull);
    expect(supervisor.lastError, isNull);
  });

  test('supports start from STOPPED via IDLE and resets diagnostics', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onLegacyEndpointResolved(), isTrue);
    expect(
      supervisor.onStreamDisconnected(ConnectionErrorCode.legacyWsFailed),
      isTrue,
    );
    supervisor.recordReceivedAt(DateTime.parse('2026-03-22T02:00:00Z'));
    expect(supervisor.stopByUser(), isTrue);

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.status, ConnectionStatus.connectingSessionWs);
    expect(supervisor.reconnectCount, 0);
    expect(supervisor.lastReceivedAt, isNull);
    expect(supervisor.lastError, isNull);
  });

  test('prevents invalid transition such as IDLE -> STREAMING_NDGR', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();

    expect(supervisor.onNdgrEndpointResolved(), isFalse);
    expect(supervisor.status, ConnectionStatus.idle);
  });

  test('wifi indicator color follows specification for each state', () {
    final Map<ConnectionStatus, WifiIndicatorColor> expectedColors =
        <ConnectionStatus, WifiIndicatorColor>{
          ConnectionStatus.idle: WifiIndicatorColor.red,
          ConnectionStatus.connectingSessionWs: WifiIndicatorColor.green,
          ConnectionStatus.resolvingEndpoints: WifiIndicatorColor.green,
          ConnectionStatus.streamingNdgr: WifiIndicatorColor.green,
          ConnectionStatus.streamingLegacy: WifiIndicatorColor.green,
          ConnectionStatus.reconnecting: WifiIndicatorColor.green,
          ConnectionStatus.stopped: WifiIndicatorColor.red,
          ConnectionStatus.ended: WifiIndicatorColor.red,
          ConnectionStatus.failed: WifiIndicatorColor.red,
        };

    for (final ConnectionStatus status in ConnectionStatus.values) {
      final WifiIndicatorColor color =
          status.usesGreenWifiIcon ? WifiIndicatorColor.green : WifiIndicatorColor.red;
      expect(color, expectedColors[status]);
    }
  });

  test('updates reconnect count, last received time, and recent error', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    final DateTime timestamp = DateTime.parse('2026-03-22T00:00:00Z');

    expect(supervisor.startConnection(), isTrue);
    expect(supervisor.onSessionWsConnected(), isTrue);
    expect(supervisor.onLegacyEndpointResolved(), isTrue);
    expect(
      supervisor.onStreamDisconnected(ConnectionErrorCode.legacyWsFailed),
      isTrue,
    );

    expect(supervisor.reconnectCount, 1);
    expect(supervisor.lastError, ConnectionErrorCode.legacyWsFailed);

    supervisor.recordReceivedAt(timestamp);
    expect(supervisor.lastReceivedAt, timestamp);

    supervisor.recordError(ConnectionErrorCode.speechVoicevoxFailed);
    expect(supervisor.lastError, ConnectionErrorCode.speechVoicevoxFailed);
  });

  test('notifies listeners when state or diagnostic fields are updated', () {
    final ConnectionSupervisor supervisor = ConnectionSupervisor();
    int notifyCount = 0;

    supervisor.addListener(() {
      notifyCount += 1;
    });

    expect(supervisor.startConnection(), isTrue);
    supervisor.recordReceivedAt(DateTime.parse('2026-03-22T00:00:00Z'));
    supervisor.recordError(ConnectionErrorCode.lvParseFailed);

    expect(notifyCount, 3);
  });
}
