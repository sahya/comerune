import 'dart:async';
import 'dart:convert';

import 'package:comerune/domain/connection/session_ws_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionWsMessageParser', () {
    test('extracts ndgr and legacy endpoints and prefers ndgr', () {
      final Map<String, Object?> payload = <String, Object?>{
        'type': 'seat',
        'data': <String, Object?>{
          'uri':
              'https://mpn.live.nicovideo.jp/api/view/v4/watch?audience_token=abc',
          'messageServer':
              'wss://msgd.live2.nicovideo.jp/websocket?thread=123&token=abc',
        },
      };

      final SessionEndpointResolution resolution =
          SessionWsMessageParser.extractEndpoints(payload);

      expect(
        resolution.ndgrViewUri,
        'https://mpn.live.nicovideo.jp/api/view/v4/watch?audience_token=abc',
      );
      expect(
        resolution.legacyWebSocketUrl,
        'wss://msgd.live2.nicovideo.jp/websocket?thread=123&token=abc',
      );
      expect(resolution.preferredEndpoint, resolution.ndgrViewUri);
    });

    test('falls back to legacy when ndgr endpoint is not found', () {
      final SessionEndpointResolution resolution =
          SessionWsMessageParser.extractEndpoints(<String, Object?>{
        'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
      });

      expect(resolution.ndgrViewUri, isNull);
      expect(
        resolution.legacyWebSocketUrl,
        'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
      );
      expect(
        resolution.preferredEndpoint,
        'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
      );
    });

    test('normalizes detected URL by trimming trailing brace', () {
      final SessionEndpointResolution resolution =
          SessionWsMessageParser.extractEndpoints(<String, Object?>{
        'messageServer': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123}',
      });

      expect(
        resolution.legacyWebSocketUrl,
        'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
      );
    });

    test('detects broadcast end event', () {
      expect(
        SessionWsMessageParser.detectBroadcastEnd(<String, Object?>{
          'type': 'disconnect',
          'data': <String, Object?>{'reason': 'END_PROGRAM'},
        }),
        BroadcastEndDetection.ended,
      );
    });

    test('uses unknown fallback for unexpected disconnect reason', () {
      expect(
        SessionWsMessageParser.detectBroadcastEnd(<String, Object?>{
          'type': 'disconnect',
          'data': <String, Object?>{'reason': 'MAINTENANCE'},
        }),
        BroadcastEndDetection.unknown,
      );
    });

    test('does not treat unrelated reason containing END as ended', () {
      expect(
        SessionWsMessageParser.detectBroadcastEnd(<String, Object?>{
          'type': 'disconnect',
          'data': <String, Object?>{'reason': 'SUSPEND'},
        }),
        BroadcastEndDetection.unknown,
      );
    });

    test('treats non-whitelisted END_* reasons as unknown', () {
      expect(
        SessionWsMessageParser.detectBroadcastEnd(<String, Object?>{
          'type': 'disconnect',
          'data': <String, Object?>{'reason': 'END_MAINTENANCE'},
        }),
        BroadcastEndDetection.unknown,
      );
    });
  });

  group('SessionWsLogSanitizer', () {
    test('masks sensitive keys recursively and strips query parameters', () {
      final String raw = jsonEncode(<String, Object?>{
        'token': 'abcdef',
        'nested': <String, Object?>{
          'AuthValue': 'very-secret',
          'url': 'https://example.com/path?token=visible',
        },
        'list': <Object?>[
          <String, Object?>{'Cookie': 'cookie-value'},
        ],
      });

      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;

      expect(decoded['token'], '***');
      expect((decoded['nested'] as Map<String, dynamic>)['AuthValue'], '***');
      expect(
        (decoded['nested'] as Map<String, dynamic>)['url'],
        'https://example.com/path',
      );
      expect(
        ((decoded['list'] as List<dynamic>).first
            as Map<String, dynamic>)['Cookie'],
        '***',
      );
    });

    test('truncates strings that are 40 chars or longer', () {
      final String raw = jsonEncode(<String, Object?>{
        'value': '1234567890123456789012345678901234567890XYZ',
      });

      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;
      final String value = decoded['value'] as String;

      expect(value.endsWith('…'), isTrue);
      expect(value.length, 41);
    });

    test('does not truncate URL values even when longer than 40 chars', () {
      const String longUrl =
          'https://mpn.live.nicovideo.jp/api/view/v4/watch?token=verylong';
      final String raw = jsonEncode(<String, Object?>{'url': longUrl});

      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;
      final String value = decoded['url'] as String;

      expect(value, 'https://mpn.live.nicovideo.jp/api/view/v4/watch');
      expect(value.endsWith('…'), isFalse);
    });

    test('sanitizes URLs to scheme host path only', () {
      final String raw = jsonEncode(<String, Object?>{
        'url': 'https://u:p@e.co:9/p?a=1#f',
        'socket': 'wss://u:p@e.co:9/ws?token=abc#x',
      });

      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;

      expect(decoded['url'], 'https://e.co:9/p');
      expect(decoded['socket'], 'wss://e.co:9/ws');
    });

    test('masks password-like keys as sensitive information', () {
      final String raw = jsonEncode(<String, Object?>{
        'password': 'visible-password',
      });
      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;

      expect(decoded['password'], '***');
    });
  });

  group('SessionWsClient', () {
    test('applies default Android User-Agent header', () {
      final SessionWsClient client = SessionWsClient(lv: 'lv123456789');

      expect(
        client.connectHeaders['User-Agent'],
        SessionWsClient.defaultAndroidUserAgent,
      );
    });

    test('keeps explicit User-Agent header when provided', () {
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        connectHeaders: const <String, String>{
          'User-Agent': 'comerune-test-agent',
        },
      );

      expect(client.connectHeaders['User-Agent'], 'comerune-test-agent');
    });

    test('sends startWatching on connect and pong on keepalive', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();

      expect(fakeChannel.sentMessages, hasLength(1));
      final Map<String, dynamic> startWatching =
          jsonDecode(fakeChannel.sentMessages.first as String)
              as Map<String, dynamic>;
      expect(startWatching['type'], 'startWatching');
      expect(
        (startWatching['data'] as Map<String, dynamic>)['room'],
        <String, dynamic>{'protocol': 'webSocket', 'commentable': false},
      );

      fakeChannel.pushIncoming(
        jsonEncode(<String, Object?>{
          'type': 'serverTime',
          'data': <String, Object?>{'serverTime': 1700000000},
        }),
      );

      await Future<void>.delayed(Duration.zero);

      expect(fakeChannel.sentMessages, hasLength(2));
      final Map<String, dynamic> pong =
          jsonDecode(fakeChannel.sentMessages.last as String)
              as Map<String, dynamic>;
      expect(pong['type'], 'pong');
      expect(pong.containsKey('body'), isFalse);
      expect(
        events.map((SessionWsEvent e) => e.type),
        contains(SessionWsEventType.connected),
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('sends minimal startWatching payload when configured', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
        startWatchingMode: SessionWsStartWatchingMode.minimal,
      );

      await client.connect();

      expect(fakeChannel.sentMessages, hasLength(1));
      final Map<String, dynamic> startWatching =
          jsonDecode(fakeChannel.sentMessages.first as String)
              as Map<String, dynamic>;
      expect(startWatching['type'], 'startWatching');
      expect(startWatching['data'], <String, dynamic>{});

      await client.dispose();
    });

    test(
      'emits keepalive failure and disconnects when pong send fails',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel(
          failOnPong: true,
        );
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();

        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{'type': 'serverTime'}),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));

        final Iterable<SessionWsEvent> errorEvents = events.where(
          (SessionWsEvent event) =>
              event.type == SessionWsEventType.error &&
              event.errorCode == SessionWsErrorCode.keepaliveResponseFailed,
        );

        expect(errorEvents, isNotEmpty);
        expect(
          events.map((SessionWsEvent e) => e.type),
          contains(SessionWsEventType.disconnected),
        );

        await client.dispose();
        await subscription.cancel();
      },
    );

    test('responds to ping keepalive when configured', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
      );

      await client.connect();
      fakeChannel.pushIncoming(jsonEncode(<String, Object?>{'type': 'ping'}));

      await Future<void>.delayed(Duration.zero);

      expect(fakeChannel.sentMessages, hasLength(2));
      final Map<String, dynamic> pong =
          jsonDecode(fakeChannel.sentMessages.last as String)
              as Map<String, dynamic>;
      expect(pong['type'], 'pong');
      expect(pong.containsKey('body'), isFalse);
      await client.dispose();
    });

    test(
      'sends keepSeat periodically after receiving seat keepIntervalSec',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
        );

        await client.connect();
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{'keepIntervalSec': 1},
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(fakeChannel.sentMessages.length, greaterThanOrEqualTo(2));
        final Map<String, dynamic> keepSeat =
            jsonDecode(fakeChannel.sentMessages.last as String)
                as Map<String, dynamic>;
        expect(keepSeat['type'], 'keepSeat');

        await client.dispose();
      },
    );

    test(
      'emits keepalive failure and disconnects when keepSeat send fails',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel(
          failOnKeepSeat: true,
        );
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{'keepIntervalSec': 1},
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(
          events.any(
            (SessionWsEvent e) =>
                e.type == SessionWsEventType.error &&
                e.errorCode == SessionWsErrorCode.keepaliveResponseFailed,
          ),
          isTrue,
        );
        expect(
          events.any(
            (SessionWsEvent e) => e.type == SessionWsEventType.disconnected,
          ),
          isTrue,
        );

        await client.dispose();
        await subscription.cancel();
      },
    );

    test(
      'emits ndgr endpoint event before legacy when both exist in message',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();

        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{
              'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
              'ndgr':
                  'https://mpn.live.nicovideo.jp/api/view/v4/watch?audience_token=abc',
            },
          }),
        );

        await Future<void>.delayed(Duration.zero);

        final SessionWsEvent endpointEvent = events.firstWhere(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.ndgrEndpointResolved ||
              e.type == SessionWsEventType.legacyEndpointResolved,
        );

        expect(endpointEvent.type, SessionWsEventType.ndgrEndpointResolved);
        expect(
          endpointEvent.ndgrViewUri,
          'https://mpn.live.nicovideo.jp/api/view/v4/watch?audience_token=abc',
        );

        await client.dispose();
        await subscription.cancel();
      },
    );

    test(
      'delays legacy fallback and prefers ndgr if ndgr arrives in grace window',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
          endpointFallbackDelay: const Duration(milliseconds: 50),
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{
              'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
            },
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{
              'ndgr':
                  'https://mpn.live.nicovideo.jp/api/view/v4/watch?audience_token=abc',
            },
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));

        final List<SessionWsEventType> endpointTypes = events
            .where(
              (SessionWsEvent e) =>
                  e.type == SessionWsEventType.ndgrEndpointResolved ||
                  e.type == SessionWsEventType.legacyEndpointResolved,
            )
            .map((SessionWsEvent e) => e.type)
            .toList();
        expect(endpointTypes, <SessionWsEventType>[
          SessionWsEventType.ndgrEndpointResolved,
        ]);

        await client.dispose();
        await subscription.cancel();
      },
    );

    test(
      'emits legacy endpoint when ndgr is not found after grace delay',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
          endpointFallbackDelay: const Duration(milliseconds: 10),
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{
              'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
            },
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));

        final SessionWsEvent legacyEvent = events.firstWhere(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.legacyEndpointResolved,
        );
        expect(
          legacyEvent.legacyWebSocketUrl,
          'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
        );

        await client.dispose();
        await subscription.cancel();
      },
    );

    test(
      'does not postpone legacy fallback timer on unrelated incoming messages',
      () async {
        final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
        final SessionWsClient client = SessionWsClient(
          lv: 'lv123456789',
          channelFactory: (_) async => fakeChannel,
          endpointFallbackDelay: const Duration(milliseconds: 50),
        );
        final List<SessionWsEvent> events = <SessionWsEvent>[];
        final StreamSubscription<SessionWsEvent> subscription =
            client.events.listen(events.add);

        await client.connect();
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'seat',
            'data': <String, Object?>{
              'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
            },
          }),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{'type': 'serverTime'}),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        fakeChannel.pushIncoming(
          jsonEncode(<String, Object?>{'type': 'serverTime'}),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          events.any(
            (SessionWsEvent e) =>
                e.type == SessionWsEventType.legacyEndpointResolved,
          ),
          isTrue,
        );

        await client.dispose();
        await subscription.cancel();
      },
    );

    test('emits failed on unknown disconnect event', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();
      fakeChannel.pushIncoming(
        jsonEncode(<String, Object?>{
          'type': 'disconnect',
          'data': <String, Object?>{'reason': 'MAINTENANCE'},
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        events.any(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.failed &&
              e.errorCode == SessionWsErrorCode.unknownBroadcastEndEvent,
        ),
        isTrue,
      );
      final SessionWsEvent failedEvent = events.firstWhere(
        (SessionWsEvent e) =>
            e.type == SessionWsEventType.failed &&
            e.errorCode == SessionWsErrorCode.unknownBroadcastEndEvent,
      );
      expect(failedEvent.errorDetail, isNotNull);
      expect(failedEvent.errorDetail!.phase,
          SessionWsFailurePhase.handlingIncoming);
      expect(failedEvent.error.toString(), contains('MAINTENANCE'));
      expect(
        events.any(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.error &&
              e.errorCode == SessionWsErrorCode.unknownBroadcastEndEvent,
        ),
        isFalse,
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('emits failed when endpoint resolution times out', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
        endpointResolveTimeout: const Duration(milliseconds: 20),
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        events.any(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.failed &&
              e.errorCode == SessionWsErrorCode.endpointResolveFailed,
        ),
        isTrue,
      );
      final SessionWsEvent failedEvent = events.firstWhere(
        (SessionWsEvent e) =>
            e.type == SessionWsEventType.failed &&
            e.errorCode == SessionWsErrorCode.endpointResolveFailed,
      );
      expect(failedEvent.errorDetail, isNotNull);
      expect(
        failedEvent.errorDetail!.phase,
        SessionWsFailurePhase.waitingEndpoint,
      );
      expect(
        events.any(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.error &&
              e.errorCode == SessionWsErrorCode.endpointResolveFailed,
        ),
        isFalse,
      );
      expect(
        events.any(
          (SessionWsEvent e) => e.type == SessionWsEventType.disconnected,
        ),
        isTrue,
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('can reconnect after startWatching send failure', () async {
      final _FakeSessionWsChannel firstChannel = _FakeSessionWsChannel(
        failOnStartWatching: true,
      );
      final _FakeSessionWsChannel secondChannel = _FakeSessionWsChannel();
      int factoryCallCount = 0;

      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async {
          factoryCallCount += 1;
          if (factoryCallCount == 1) {
            return firstChannel;
          }
          return secondChannel;
        },
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        events.any(
          (SessionWsEvent e) =>
              e.type == SessionWsEventType.error &&
              e.errorCode == SessionWsErrorCode.connectFailed,
        ),
        isTrue,
      );
      expect(
        events.any(
          (SessionWsEvent e) => e.type == SessionWsEventType.connected,
        ),
        isFalse,
      );
      expect(firstChannel.closeCount, 1);

      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(factoryCallCount, 2);
      expect(secondChannel.sentMessages, hasLength(1));
      final Map<String, dynamic> startWatching =
          jsonDecode(secondChannel.sentMessages.first as String)
              as Map<String, dynamic>;
      expect(startWatching['type'], 'startWatching');

      await client.dispose();
      await subscription.cancel();
    });

    test('ignores connect call while disconnect is in progress', () async {
      final _FakeSessionWsChannel firstChannel = _FakeSessionWsChannel(
        closeDelay: const Duration(milliseconds: 60),
      );
      final _FakeSessionWsChannel secondChannel = _FakeSessionWsChannel();
      int factoryCallCount = 0;
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async {
          factoryCallCount += 1;
          if (factoryCallCount == 1) {
            return firstChannel;
          }
          return secondChannel;
        },
      );

      await client.connect();
      final Future<void> disconnectFuture = client.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await client.connect();
      await disconnectFuture;

      expect(factoryCallCount, 1);

      await client.connect();
      expect(factoryCallCount, 2);

      await client.dispose();
    });

    test('emits connectFailed when channelFactory throws', () async {
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) => throw StateError('factory failed'),
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();
      await Future<void>.delayed(Duration.zero);

      expect(
        events.any(
          (SessionWsEvent event) =>
              event.type == SessionWsEventType.error &&
              event.errorCode == SessionWsErrorCode.connectFailed,
        ),
        isTrue,
      );
      final SessionWsEvent errorEvent = events.firstWhere(
        (SessionWsEvent event) =>
            event.type == SessionWsEventType.error &&
            event.errorCode == SessionWsErrorCode.connectFailed,
      );
      expect(errorEvent.errorDetail, isNotNull);
      expect(
        errorEvent.errorDetail!.phase,
        SessionWsFailurePhase.openingSocket,
      );
      expect(
        events.any(
          (SessionWsEvent event) => event.type == SessionWsEventType.connected,
        ),
        isFalse,
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('is safe to call disconnect twice concurrently', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel(
        closeDelay: const Duration(milliseconds: 50),
      );
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
      );
      final List<SessionWsEvent> events = <SessionWsEvent>[];
      final StreamSubscription<SessionWsEvent> subscription =
          client.events.listen(events.add);

      await client.connect();
      await Future.wait<void>(<Future<void>>[
        client.disconnect(),
        client.disconnect(),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(fakeChannel.closeCount, 1);
      expect(
        events
            .where(
                (SessionWsEvent e) => e.type == SessionWsEventType.disconnected)
            .length,
        1,
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('throws StateError when connect is called after dispose', () async {
      final _FakeSessionWsChannel fakeChannel = _FakeSessionWsChannel();
      final SessionWsClient client = SessionWsClient(
        lv: 'lv123456789',
        channelFactory: (_) async => fakeChannel,
      );

      await client.dispose();

      await expectLater(client.connect(), throwsA(isA<StateError>()));
      expect(fakeChannel.sentMessages, isEmpty);
    });
  });
}

class _FakeSessionWsChannel implements SessionWsChannel {
  _FakeSessionWsChannel({
    this.failOnPong = false,
    this.failOnKeepSeat = false,
    this.failOnStartWatching = false,
    this.closeDelay = Duration.zero,
  })  : _incoming = StreamController<dynamic>(),
        _sink = _FakeSink() {
    _sink.onAdd = (dynamic data) {
      sentMessages.add(data);

      if (!failOnPong && !failOnKeepSeat && !failOnStartWatching) {
        return;
      }

      final Map<String, dynamic> decoded =
          jsonDecode(data as String) as Map<String, dynamic>;
      if (failOnStartWatching && decoded['type'] == 'startWatching') {
        throw StateError('startWatching send failed');
      }
      if (failOnPong && decoded['type'] == 'pong') {
        throw StateError('pong send failed');
      }
      if (failOnKeepSeat && decoded['type'] == 'keepSeat') {
        throw StateError('keepSeat send failed');
      }
    };
  }

  final bool failOnPong;
  final bool failOnKeepSeat;
  final bool failOnStartWatching;
  final Duration closeDelay;
  final StreamController<dynamic> _incoming;
  final _FakeSink _sink;
  final List<dynamic> sentMessages = <dynamic>[];
  int closeCount = 0;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  StreamSink<dynamic> get sink => _sink;

  void pushIncoming(dynamic data) {
    _incoming.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount += 1;
    if (closeDelay > Duration.zero) {
      await Future<void>.delayed(closeDelay);
    }
    await _sink.close();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

class _FakeSink implements StreamSink<dynamic> {
  void Function(dynamic data)? onAdd;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {
    onAdd?.call(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    return stream.forEach(add);
  }

  @override
  Future<void> close() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
