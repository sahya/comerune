import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/connection/session_ws_client.dart';

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
          SessionWsMessageParser.extractEndpoints(
        <String, Object?>{
          'legacy': 'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
        },
      );

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
        ((decoded['list'] as List<dynamic>).first as Map<String, dynamic>)['Cookie'],
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

    test('sanitizes URLs to scheme host path only', () {
      final String raw = jsonEncode(<String, Object?>{
        'url': 'https://u:p@e.co:9/p?a=1#f',
        'socket': 'wss://u:p@e.co:9/ws?token=abc#x',
      });

      final String sanitized = SessionWsLogSanitizer.sanitizeRawJson(raw);
      final Map<String, dynamic> decoded =
          jsonDecode(sanitized) as Map<String, dynamic>;

      expect(decoded['url'], 'https://e.co/p');
      expect(decoded['socket'], 'wss://e.co/ws');
    });
  });

  group('SessionWsClient', () {
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
      expect(events.map((SessionWsEvent e) => e.type), contains(SessionWsEventType.connected));

      await client.dispose();
      await subscription.cancel();
    });

    test('emits keepalive failure and disconnects when pong send fails', () async {
      final _FakeSessionWsChannel fakeChannel =
          _FakeSessionWsChannel(failOnPong: true);
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
    });

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
      await client.dispose();
    });

    test('emits ndgr endpoint event before legacy when both exist in message',
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
    });

    test('delays legacy fallback and prefers ndgr if ndgr arrives in grace window',
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

      final List<SessionWsEventType> endpointTypes =
          events
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
    });

    test('emits legacy endpoint when ndgr is not found after grace delay',
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
        (SessionWsEvent e) => e.type == SessionWsEventType.legacyEndpointResolved,
      );
      expect(
        legacyEvent.legacyWebSocketUrl,
        'wss://msgd.live2.nicovideo.jp/websocket?thread=123',
      );

      await client.dispose();
      await subscription.cancel();
    });

    test('does not postpone legacy fallback timer on unrelated incoming messages',
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
      fakeChannel.pushIncoming(jsonEncode(<String, Object?>{'type': 'serverTime'}));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      fakeChannel.pushIncoming(jsonEncode(<String, Object?>{'type': 'serverTime'}));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        events.any(
          (SessionWsEvent e) => e.type == SessionWsEventType.legacyEndpointResolved,
        ),
        isTrue,
      );

      await client.dispose();
      await subscription.cancel();
    });

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
      expect(
        events.any((SessionWsEvent e) => e.type == SessionWsEventType.disconnected),
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
  });
}

class _FakeSessionWsChannel implements SessionWsChannel {
  _FakeSessionWsChannel({
    this.failOnPong = false,
    this.failOnStartWatching = false,
  })
      : _incoming = StreamController<dynamic>(),
        _sink = _FakeSink() {
    _sink.onAdd = (dynamic data) {
      sentMessages.add(data);

      if (!failOnPong && !failOnStartWatching) {
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
    };
  }

  final bool failOnPong;
  final bool failOnStartWatching;
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
