import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/ndgr_client.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('NdgrClient', () {
    test(
      'limits initial history count across backward and previous streams',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await server.close(force: true);
        });

        final Uri base = Uri(
          scheme: 'http',
          host: server.address.host,
          port: server.port,
        );

        final Uri viewUri = base.replace(path: '/view');
        final Uri backwardUri = base.replace(path: '/backward');
        final Uri previousUri = base.replace(path: '/previous');

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/view') {
            final List<int> headBody = <int>[
              ..._delimit(
                _encodeChunkedEntryBackward(
                  backwardSegmentUri: backwardUri.toString(),
                ),
              ),
              ..._delimit(
                _encodeChunkedEntryPrevious(
                  previousUri: previousUri.toString(),
                ),
              ),
            ];
            request.response.add(headBody);
            await request.response.close();
            return;
          }

          if (request.uri.path == '/backward') {
            final List<int> packed = _encodePackedSegment(<List<int>>[
              _encodeChunkedMessage(id: 'backward-1', content: 'backward-1'),
            ]);
            request.response.add(packed);
            await request.response.close();
            return;
          }

          if (request.uri.path == '/previous') {
            final List<int> previousBody = <int>[
              ..._delimit(
                _encodeChunkedMessage(id: 'previous-1', content: 'previous-1'),
              ),
              ..._delimit(
                _encodeChunkedMessage(id: 'previous-2', content: 'previous-2'),
              ),
            ];
            request.response.add(previousBody);
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final NdgrClient client = NdgrClient(
          stallThreshold: const Duration(minutes: 1),
          stallCheckInterval: const Duration(seconds: 5),
        );
        addTearDown(client.dispose);

        final List<AppMessage> messages = <AppMessage>[];
        final StreamSubscription<NdgrClientEvent> subscription =
            client.events.listen((NdgrClientEvent event) {
          if (event.type == NdgrClientEventType.message &&
              event.message != null) {
            messages.add(event.message!);
          }
        });
        addTearDown(subscription.cancel);

        await client.connect(viewUri, historyCount: 2);

        expect(messages.length, 2);
        expect(messages[0].content, 'backward-1');
        expect(messages[1].content, 'previous-1');
      },
    );

    test(
      'does not notify stall before first frame and stop aborts provided client connection',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final Completer<void> releaseView = Completer<void>();
        addTearDown(() async {
          if (!releaseView.isCompleted) {
            releaseView.complete();
          }
          await server.close(force: true);
        });

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/view') {
            await releaseView.future;
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final Uri viewUri = Uri(
          scheme: 'http',
          host: server.address.host,
          port: server.port,
          path: '/view',
        );

        DateTime now = DateTime.parse('2026-03-22T00:00:00Z');
        final NdgrClient client = NdgrClient(
          httpClient: HttpClient(),
          now: () => now,
          stallThreshold: const Duration(seconds: 15),
          stallCheckInterval: const Duration(milliseconds: 5),
        );
        addTearDown(client.dispose);

        bool stalled = false;
        final StreamSubscription<NdgrClientEvent> subscription =
            client.events.listen((NdgrClientEvent event) {
          if (event.type == NdgrClientEventType.stalled) {
            stalled = true;
          }
        });
        addTearDown(subscription.cancel);

        final Future<void> connectFuture = client.connect(viewUri);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        now = now.add(const Duration(seconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(stalled, isFalse);

        await client.stop();
        if (!releaseView.isCompleted) {
          releaseView.complete();
        }

        await connectFuture.timeout(const Duration(seconds: 1));
        expect(client.isRunning, isFalse);
      },
    );

    test('notifies stall after first frame is received', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final Completer<void> releaseSegment = Completer<void>();
      addTearDown(() async {
        if (!releaseSegment.isCompleted) {
          releaseSegment.complete();
        }
        await server.close(force: true);
      });

      final Uri base = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
      );
      final Uri viewUri = base.replace(path: '/view');
      final Uri segmentUri = base.replace(path: '/segment');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view') {
          final List<int> headBody = <int>[
            ..._delimit(
              _encodeChunkedEntrySegment(segmentUri: segmentUri.toString()),
            ),
          ];
          request.response.add(headBody);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/segment') {
          final List<int> segmentBody = <int>[
            ..._delimit(
              _encodeChunkedMessage(
                id: 'segment-1',
                content: 'segment-message',
              ),
            ),
          ];
          request.response.add(segmentBody);
          await request.response.flush();
          await releaseSegment.future;
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      DateTime now = DateTime.parse('2026-03-22T00:00:00Z');
      final NdgrClient client = NdgrClient(
        now: () => now,
        stallThreshold: const Duration(seconds: 15),
        stallCheckInterval: const Duration(milliseconds: 5),
      );
      addTearDown(client.dispose);

      final Completer<Duration> stalled = Completer<Duration>();
      final StreamSubscription<NdgrClientEvent> subscription =
          client.events.listen((NdgrClientEvent event) {
        if (event.type == NdgrClientEventType.stalled && !stalled.isCompleted) {
          stalled.complete(event.stallDuration!);
        }
      });
      addTearDown(subscription.cancel);

      final Future<void> connectFuture = client.connect(viewUri);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      now = now.add(const Duration(seconds: 16));

      final Duration stallDuration = await stalled.future.timeout(
        const Duration(seconds: 1),
      );
      expect(stallDuration >= const Duration(seconds: 15), isTrue);

      await client.stop();
      if (!releaseSegment.isCompleted) {
        releaseSegment.complete();
      }
      await connectFuture.timeout(const Duration(seconds: 1));
    });

    test('emits connected once after first successful head response', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      final Uri base = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
      );
      final Uri viewUri = base.replace(path: '/view');
      final Uri segmentUri = base.replace(path: '/segment');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view') {
          request.response.add(
            _delimit(
              _encodeChunkedEntrySegment(segmentUri: segmentUri.toString()),
            ),
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/segment') {
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrClient client = NdgrClient();
      addTearDown(client.dispose);

      int connectedCount = 0;
      final StreamSubscription<NdgrClientEvent> subscription =
          client.events.listen((NdgrClientEvent event) {
        if (event.type == NdgrClientEventType.connected) {
          connectedCount += 1;
        }
      });
      addTearDown(subscription.cancel);

      await client.connect(viewUri);
      expect(connectedCount, 1);
    });

    test('reports connect failure only via Future exception', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      server.listen((HttpRequest request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      final NdgrClient client = NdgrClient(
        stallThreshold: const Duration(minutes: 1),
        stallCheckInterval: const Duration(seconds: 10),
      );
      addTearDown(client.dispose);

      final List<NdgrClientEventType> eventTypes = <NdgrClientEventType>[];
      final StreamSubscription<NdgrClientEvent> subscription =
          client.events.listen((NdgrClientEvent event) {
        eventTypes.add(event.type);
      });
      addTearDown(subscription.cancel);

      await expectLater(client.connect(viewUri), throwsA(isA<HttpException>()));
      expect(eventTypes, isEmpty);
    });

    test(
      'skips malformed protobuf frame and continues with next frame',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await server.close(force: true);
        });

        final Uri base = Uri(
          scheme: 'http',
          host: server.address.host,
          port: server.port,
        );
        final Uri viewUri = base.replace(path: '/view');
        final Uri segmentUri = base.replace(path: '/segment');

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/view') {
            request.response.add(
              _delimit(
                _encodeChunkedEntrySegment(segmentUri: segmentUri.toString()),
              ),
            );
            await request.response.close();
            return;
          }
          if (request.uri.path == '/segment') {
            request.response.add(_delimit(<int>[0x80]));
            request.response.add(
              _delimit(_encodeChunkedMessage(id: 'valid-1', content: 'valid')),
            );
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final NdgrClient client = NdgrClient();
        addTearDown(client.dispose);

        final List<AppMessage> messages = <AppMessage>[];
        final StreamSubscription<NdgrClientEvent> subscription =
            client.events.listen((NdgrClientEvent event) {
          if (event.type == NdgrClientEventType.message &&
              event.message != null) {
            messages.add(event.message!);
          }
        });
        addTearDown(subscription.cancel);

        await client.connect(viewUri);
        expect(messages.map((AppMessage m) => m.content).toList(), <String>[
          'valid',
        ]);
      },
    );

    test('throws StateError when connect is called while running', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final Completer<void> releaseView = Completer<void>();
      addTearDown(() async {
        if (!releaseView.isCompleted) {
          releaseView.complete();
        }
        await server.close(force: true);
      });

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view') {
          await releaseView.future;
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      final NdgrClient client = NdgrClient();
      addTearDown(client.dispose);

      final Future<void> firstConnect = client.connect(viewUri);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await expectLater(
        () => client.connect(viewUri),
        throwsA(isA<StateError>()),
      );

      await client.stop();
      if (!releaseView.isCompleted) {
        releaseView.complete();
      }
      await firstConnect.timeout(const Duration(seconds: 1));
    });

    test('uses typed at query cursor when requesting view endpoint', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      String? observedAt;
      server.listen((HttpRequest request) async {
        observedAt = request.uri.queryParameters['at'];
        await request.response.close();
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      final NdgrClient client = NdgrClient();
      addTearDown(client.dispose);

      await client.connect(
        viewUri,
        historyCount: 0,
        at: NdgrAt.timestamp(12345),
      );
      expect(observedAt, '12345');
    });
  });

  group('NdgrAt', () {
    test('rejects negative unix timestamp', () {
      expect(() => NdgrAt.timestamp(-1), throwsA(isA<ArgumentError>()));
    });
  });
}

List<int> _encodeChunkedEntryBackward({required String backwardSegmentUri}) {
  final List<int> next = _stringField(1, backwardSegmentUri);
  final List<int> backward = _bytesField(2, next);
  return _bytesField(2, backward);
}

List<int> _encodeChunkedEntrySegment({required String segmentUri}) {
  final List<int> segment = _stringField(3, segmentUri);
  return _bytesField(1, segment);
}

List<int> _encodeChunkedEntryPrevious({required String previousUri}) {
  final List<int> previous = _stringField(3, previousUri);
  return _bytesField(3, previous);
}

List<int> _encodeChunkedMessage({
  required String id,
  required String content,
  int seconds = 1700000000,
}) {
  final List<int> timestamp = <int>[
    ..._varintField(1, seconds),
    ..._varintField(2, 0),
  ];

  final List<int> meta = <int>[
    ..._stringField(1, id),
    ..._bytesField(2, timestamp),
  ];

  final List<int> chat = _stringField(1, content);
  final List<int> nicoliveMessage = _bytesField(1, chat);

  return <int>[..._bytesField(1, meta), ..._bytesField(2, nicoliveMessage)];
}

List<int> _encodePackedSegment(List<List<int>> messages, {String? nextUri}) {
  final List<int> bytes = <int>[];

  for (final List<int> message in messages) {
    bytes.addAll(_bytesField(1, message));
  }

  if (nextUri != null) {
    bytes.addAll(_bytesField(2, _stringField(1, nextUri)));
  }

  return bytes;
}

List<int> _delimit(List<int> bytes) {
  return <int>[..._encodeVarint(bytes.length), ...bytes];
}

List<int> _varintField(int fieldNumber, int value) {
  return <int>[
    ..._encodeVarint((fieldNumber << 3) | 0),
    ..._encodeVarint(value),
  ];
}

List<int> _bytesField(int fieldNumber, List<int> bytes) {
  return <int>[
    ..._encodeVarint((fieldNumber << 3) | 2),
    ..._encodeVarint(bytes.length),
    ...bytes,
  ];
}

List<int> _stringField(int fieldNumber, String value) {
  return _bytesField(fieldNumber, utf8.encode(value));
}

List<int> _encodeVarint(int value) {
  int next = value;
  final List<int> bytes = <int>[];

  while (next >= 0x80) {
    bytes.add((next & 0x7f) | 0x80);
    next >>= 7;
  }
  bytes.add(next);

  return bytes;
}
