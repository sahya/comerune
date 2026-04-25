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
        final StreamSubscription<NdgrClientEvent> subscription = client.events
            .listen((NdgrClientEvent event) {
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
        final StreamSubscription<NdgrClientEvent> subscription = client.events
            .listen((NdgrClientEvent event) {
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
      final StreamSubscription<NdgrClientEvent> subscription = client.events
          .listen((NdgrClientEvent event) {
            if (event.type == NdgrClientEventType.stalled &&
                !stalled.isCompleted) {
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
      final StreamSubscription<NdgrClientEvent> subscription = client.events
          .listen((NdgrClientEvent event) {
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
      final StreamSubscription<NdgrClientEvent> subscription = client.events
          .listen((NdgrClientEvent event) {
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
        final StreamSubscription<NdgrClientEvent> subscription = client.events
            .listen((NdgrClientEvent event) {
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

    test(
      'returns partial result when backward pull ends without nextUri (#666)',
      () async {
        // Regression guard: when the server returns a packed segment with no
        // nextUri (history boundary) before the requested count is reached,
        // _pullBackwards must still return the partial result rather than
        // dropping the messages it did receive. The companion observability
        // change in #666 also emits a developer.log warn at that moment;
        // the log itself is not asserted here (capturing dart:developer.log
        // requires invasive infrastructure not used elsewhere in this test
        // file), but the behaviour-level invariant — partial result is
        // returned, no exception is thrown — is what callers depend on.
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

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/view') {
            final List<int> headBody = _delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backwardUri.toString(),
              ),
            );
            request.response.add(headBody);
            await request.response.close();
            return;
          }

          if (request.uri.path == '/backward') {
            // Single message, no nextUri — server signals "no more history".
            final List<int> packed = _encodePackedSegment(<List<int>>[
              _encodeChunkedMessage(id: 'backward-only', content: 'only-one'),
            ]);
            request.response.add(packed);
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
        final StreamSubscription<NdgrClientEvent> subscription = client.events
            .listen((NdgrClientEvent event) {
              if (event.type == NdgrClientEventType.message &&
                  event.message != null) {
                messages.add(event.message!);
              }
            });
        addTearDown(subscription.cancel);

        // Request 5 history messages but the server only returns 1.
        await client.connect(viewUri, historyCount: 5);

        // The single available history message must still be delivered
        // (silent truncation is acceptable; total loss is not).
        expect(messages, hasLength(1));
        expect(messages[0].content, 'only-one');
      },
    );

    test('returns full set when backward pull yields exactly `want` messages '
        '(boundary: warn log must NOT fire)', () async {
      // Boundary guard for the truncation-warn condition in
      // `_pullBackwards`: the warn log only fires when
      // `flattened.length < want`. When the server returns EXACTLY
      // `want` messages with `nextUri == null`, the pull must:
      //   - return all `want` messages unchanged (no drop, no extra)
      //   - NOT trigger the truncation warn log
      //
      // We cannot intercept `dart:developer.log` cheaply from this test
      // file, so the non-fire of the warn is documented rather than
      // asserted directly. The behavioural invariant that IS asserted
      // (length matches the requested count) is the user-visible
      // contract callers depend on.
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

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view') {
          final List<int> headBody = _delimit(
            _encodeChunkedEntryBackward(
              backwardSegmentUri: backwardUri.toString(),
            ),
          );
          request.response.add(headBody);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward') {
          // Exactly `want` (=2) messages, no nextUri.
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'backward-1', content: 'one'),
            _encodeChunkedMessage(id: 'backward-2', content: 'two'),
          ]);
          request.response.add(packed);
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
      final StreamSubscription<NdgrClientEvent> subscription = client.events
          .listen((NdgrClientEvent event) {
            if (event.type == NdgrClientEventType.message &&
                event.message != null) {
              messages.add(event.message!);
            }
          });
      addTearDown(subscription.cancel);

      // Request exactly 2 history messages; the server returns 2.
      await client.connect(viewUri, historyCount: 2);

      // All requested messages delivered, in order.
      expect(messages, hasLength(2));
      expect(messages[0].content, 'one');
      expect(messages[1].content, 'two');
    });

    test(
      'emits broadcastEnded and stops when ProgramStatus.Ended is received',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() async {
          await server.close(force: true);
        });

        server.listen((HttpRequest request) async {
          if (request.uri.path == '/view') {
            final List<int> segment = _encodeChunkedEntrySegment(
              segmentUri:
                  'http://${server.address.host}:${server.port}/segment',
            );
            final List<int> nextAt = _varintField(4, 9999999999);
            request.response.add(_delimit(<int>[...segment]));
            request.response.add(_delimit(<int>[...nextAt]));
            await request.response.close();
            return;
          }

          if (request.uri.path == '/segment') {
            // /segment endpoint delivers a stream of length-delimited
            // ChunkedMessage frames (NdgrLengthDelimitedDecoder), not a
            // packed segment. One normal chat message, then ProgramStatus.Ended.
            final List<int> chatMessage = _encodeChunkedMessage(
              id: 'msg-1',
              content: 'last-comment',
            );
            final List<int> endedMessage =
                _encodeChunkedMessageWithProgramEnd();
            request.response.add(_delimit(chatMessage));
            request.response.add(_delimit(endedMessage));
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

        final NdgrClient client = NdgrClient(
          stallThreshold: const Duration(minutes: 1),
        );
        addTearDown(client.dispose);

        final List<AppMessage> messages = <AppMessage>[];
        bool broadcastEnded = false;
        final StreamSubscription<NdgrClientEvent> subscription = client.events
            .listen((NdgrClientEvent event) {
              if (event.type == NdgrClientEventType.message &&
                  event.message != null) {
                messages.add(event.message!);
              }
              if (event.type == NdgrClientEventType.broadcastEnded) {
                broadcastEnded = true;
              }
            });
        addTearDown(subscription.cancel);

        await client.connect(viewUri, historyCount: 0);

        expect(messages, hasLength(1));
        expect(messages[0].content, 'last-comment');
        expect(broadcastEnded, isTrue);
        expect(client.isRunning, isFalse);
      },
    );
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

List<int> _encodeChunkedMessageWithProgramEnd() {
  // ProgramStatus: state(1) = Ended (1)
  final List<int> programStatus = _varintField(1, 1);
  // NicoliveState: program_status(9)
  final List<int> state = _bytesField(9, programStatus);
  // ChunkedMessage: state(4)
  return _bytesField(4, state);
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
