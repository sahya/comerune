import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/ndgr_timeshift_client.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('NdgrTimeshiftClient', () {
    test('fetches past comments from previous and backward segments', () async {
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
      final Uri previousUri = base.replace(path: '/previous');
      final Uri backwardUri = base.replace(path: '/backward');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          final List<int> body = <int>[
            ..._delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backwardUri.toString(),
              ),
            ),
            ..._delimit(
              _encodeChunkedEntryPrevious(previousUri: previousUri.toString()),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/previous') {
          final List<int> body = <int>[
            ..._delimit(
              _encodeChunkedMessage(id: 'prev-1', content: 'previous-1'),
            ),
            ..._delimit(
              _encodeChunkedMessage(id: 'prev-2', content: 'previous-2'),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'back-1', content: 'backward-1'),
            _encodeChunkedMessage(id: 'back-2', content: 'backward-2'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<NdgrTimeshiftEvent> events = <NdgrTimeshiftEvent>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen(events.add);
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri);

      final List<AppMessage> allMessages = events
          .where(
            (NdgrTimeshiftEvent e) => e.type == NdgrTimeshiftEventType.progress,
          )
          .expand((NdgrTimeshiftEvent e) => e.messages!)
          .toList();

      expect(allMessages.length, 4);
      expect(
        allMessages.map((AppMessage m) => m.content).toList(),
        containsAll(<String>[
          'previous-1',
          'previous-2',
          'backward-1',
          'backward-2',
        ]),
      );

      expect(events.first.type, NdgrTimeshiftEventType.started);
      expect(events.last.type, NdgrTimeshiftEventType.completed);
      expect(events.last.fetchedCount, 4);
      expect(client.totalFetched, 4);
      expect(client.hasMore, isFalse);
      expect(client.isSessionOpen, isTrue);
    });

    test('deduplicates messages across segments', () async {
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
      final Uri previousUri = base.replace(path: '/previous');
      final Uri backwardUri = base.replace(path: '/backward');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          final List<int> body = <int>[
            ..._delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backwardUri.toString(),
              ),
            ),
            ..._delimit(
              _encodeChunkedEntryPrevious(previousUri: previousUri.toString()),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/previous') {
          final List<int> body = <int>[
            ..._delimit(_encodeChunkedMessage(id: 'dup-1', content: 'first')),
            ..._delimit(
              _encodeChunkedMessage(id: 'unique-1', content: 'unique'),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'dup-1', content: 'duplicate'),
            _encodeChunkedMessage(id: 'unique-2', content: 'another'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<AppMessage> allMessages = <AppMessage>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              allMessages.addAll(event.messages!);
            }
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri);

      expect(allMessages.length, 3);
      expect(allMessages.map((AppMessage m) => m.id).toSet().length, 3);
    });

    test('fetchMore resumes from cursor position', () async {
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
      final Uri backward1Uri = base.replace(path: '/backward1');
      final Uri backward2Uri = base.replace(path: '/backward2');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          request.response.add(
            _delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backward1Uri.toString(),
              ),
            ),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward1') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'b1-1', content: 'batch1-msg1'),
            _encodeChunkedMessage(id: 'b1-2', content: 'batch1-msg2'),
          ], nextUri: backward2Uri.toString());
          request.response.add(packed);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward2') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'b2-1', content: 'batch2-msg1'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<AppMessage> allMessages = <AppMessage>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              allMessages.addAll(event.messages!);
            }
          });
      addTearDown(subscription.cancel);

      // First fetch: only 2 messages (backward1 segment).
      await client.fetchPastComments(viewUri, maxMessages: 2);

      expect(allMessages.length, 2);
      expect(client.totalFetched, 2);
      expect(client.hasMore, isTrue);

      // Second fetch: get the remaining 1 message from backward2.
      await client.fetchMore(count: 500);

      expect(allMessages.length, 3);
      expect(client.totalFetched, 3);
      expect(client.hasMore, isFalse);
    });

    test('fetchMore throws when no session is open', () {
      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      expect(() => client.fetchMore(count: 500), throwsA(isA<StateError>()));
    });

    test('fetchMore does nothing when hasMore is false', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      server.listen((HttpRequest request) async {
        if (request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      await client.fetchPastComments(viewUri);
      expect(client.hasMore, isFalse);

      // Should return immediately without emitting events.
      final List<NdgrTimeshiftEventType> extraEvents =
          <NdgrTimeshiftEventType>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent e) {
            extraEvents.add(e.type);
          });
      addTearDown(subscription.cancel);

      await client.fetchMore(count: 500);
      expect(extraEvents, isEmpty);
    });

    test('backward segments emit immediately (not buffered)', () async {
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
      final Uri backward1Uri = base.replace(path: '/backward1');
      final Uri backward2Uri = base.replace(path: '/backward2');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          request.response.add(
            _delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backward1Uri.toString(),
              ),
            ),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward1') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'seg1-1', content: 'seg1'),
          ], nextUri: backward2Uri.toString());
          request.response.add(packed);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward2') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'seg2-1', content: 'seg2'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      // Track how many progress events are emitted.
      // Each backward segment should produce its own progress event.
      int progressCount = 0;
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              progressCount += 1;
            }
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri);

      // Two backward segments = two separate progress events.
      expect(progressCount, 2);
    });

    test('maxMessages stops backward walk across segments', () async {
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
      final Uri previousUri = base.replace(path: '/previous');
      final Uri backward1Uri = base.replace(path: '/backward1');
      final Uri backward2Uri = base.replace(path: '/backward2');
      int backward2FetchCount = 0;

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          final List<int> body = <int>[
            ..._delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backward1Uri.toString(),
              ),
            ),
            ..._delimit(
              _encodeChunkedEntryPrevious(previousUri: previousUri.toString()),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/previous') {
          request.response.add(
            _delimit(_encodeChunkedMessage(id: 'prev-1', content: 'prev')),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward1') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'back-1', content: 'back1'),
            _encodeChunkedMessage(id: 'back-2', content: 'back2'),
          ], nextUri: backward2Uri.toString());
          request.response.add(packed);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward2') {
          backward2FetchCount += 1;
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'back-3', content: 'back3'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<AppMessage> allMessages = <AppMessage>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              allMessages.addAll(event.messages!);
            }
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri, maxMessages: 3);

      expect(allMessages.length, 3);
      expect(backward2FetchCount, 0);
      expect(client.hasMore, isTrue);
    });

    test('stop aborts fetch in progress', () async {
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

      final NdgrTimeshiftClient client = NdgrTimeshiftClient(
        httpClient: HttpClient(),
      );
      addTearDown(client.dispose);

      final Future<void> fetchFuture = client.fetchPastComments(viewUri);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await client.stop();
      if (!releaseView.isCompleted) {
        releaseView.complete();
      }

      await fetchFuture.timeout(const Duration(seconds: 2));
      expect(client.isRunning, isFalse);
    });

    test('throws StateError when called while running', () async {
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
        await releaseView.future;
        await request.response.close();
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final Future<void> firstFetch = client.fetchPastComments(viewUri);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await expectLater(
        () => client.fetchPastComments(viewUri),
        throwsA(isA<StateError>()),
      );

      await client.stop();
      if (!releaseView.isCompleted) {
        releaseView.complete();
      }
      await firstFetch.timeout(const Duration(seconds: 1));
    });

    test('rejects invalid maxMessages', () {
      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      expect(
        () => client.fetchPastComments(
          Uri.parse('http://localhost/view'),
          maxMessages: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('emits error event on HTTP failure', () async {
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

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<NdgrTimeshiftEventType> eventTypes =
          <NdgrTimeshiftEventType>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            eventTypes.add(event.type);
          });
      addTearDown(subscription.cancel);

      await expectLater(
        client.fetchPastComments(viewUri),
        throwsA(isA<HttpException>()),
      );

      expect(eventTypes, contains(NdgrTimeshiftEventType.started));
      expect(eventTypes, contains(NdgrTimeshiftEventType.error));
    });

    test('stops at live Segment entry when collecting entries', () async {
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
      final Uri previousUri = base.replace(path: '/previous');
      final Uri segmentUri = base.replace(path: '/segment');

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          final List<int> body = <int>[
            ..._delimit(
              _encodeChunkedEntryPrevious(previousUri: previousUri.toString()),
            ),
            ..._delimit(
              _encodeChunkedEntrySegment(segmentUri: segmentUri.toString()),
            ),
          ];
          request.response.add(body);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/previous') {
          request.response.add(
            _delimit(_encodeChunkedMessage(id: 'prev-1', content: 'previous')),
          );
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<AppMessage> allMessages = <AppMessage>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              allMessages.addAll(event.messages!);
            }
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri);

      expect(allMessages.length, 1);
      expect(allMessages[0].content, 'previous');
    });

    test('throws StateError when server returns no ReadyForNext', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      server.listen((HttpRequest request) async {
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<NdgrTimeshiftEventType> eventTypes =
          <NdgrTimeshiftEventType>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            eventTypes.add(event.type);
          });
      addTearDown(subscription.cancel);

      await expectLater(
        client.fetchPastComments(viewUri),
        throwsA(isA<StateError>()),
      );

      expect(eventTypes, contains(NdgrTimeshiftEventType.started));
      expect(eventTypes, contains(NdgrTimeshiftEventType.error));
    });

    test('handles empty response gracefully', () async {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() async {
        await server.close(force: true);
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      server.listen((HttpRequest request) async {
        if (request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final List<NdgrTimeshiftEventType> eventTypes =
          <NdgrTimeshiftEventType>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            eventTypes.add(event.type);
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri);

      expect(eventTypes, contains(NdgrTimeshiftEventType.started));
      expect(eventTypes, contains(NdgrTimeshiftEventType.completed));
      expect(client.hasMore, isFalse);
    });

    test('resetSession clears cursor state', () async {
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
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          request.response.add(
            _delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backwardUri.toString(),
              ),
            ),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'msg-1', content: 'message'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      await client.fetchPastComments(viewUri);
      expect(client.totalFetched, 1);
      expect(client.isSessionOpen, isTrue);

      client.resetSession();
      expect(client.totalFetched, 0);
      expect(client.isSessionOpen, isFalse);
      expect(client.hasMore, isFalse);
    });

    test('resetSession throws when fetch is in progress', () async {
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
        await releaseView.future;
        await request.response.close();
      });

      final Uri viewUri = Uri(
        scheme: 'http',
        host: server.address.host,
        port: server.port,
        path: '/view',
      );

      final NdgrTimeshiftClient client = NdgrTimeshiftClient();
      addTearDown(client.dispose);

      final Future<void> fetchFuture = client.fetchPastComments(viewUri);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(() => client.resetSession(), throwsA(isA<StateError>()));

      await client.stop();
      if (!releaseView.isCompleted) {
        releaseView.complete();
      }
      await fetchFuture.timeout(const Duration(seconds: 1));
    });

    test('hardLimit stops fetching and sets hasMore to false', () async {
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
      final Uri backward1Uri = base.replace(path: '/backward1');
      final Uri backward2Uri = base.replace(path: '/backward2');
      int backward2FetchCount = 0;

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == 'now') {
          request.response.add(
            _delimit(_encodeChunkedEntryNext(at: 1700000000)),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/view' &&
            request.uri.queryParameters['at'] == '1700000000') {
          request.response.add(
            _delimit(
              _encodeChunkedEntryBackward(
                backwardSegmentUri: backward1Uri.toString(),
              ),
            ),
          );
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward1') {
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'b1-1', content: 'msg1'),
            _encodeChunkedMessage(id: 'b1-2', content: 'msg2'),
          ], nextUri: backward2Uri.toString());
          request.response.add(packed);
          await request.response.close();
          return;
        }

        if (request.uri.path == '/backward2') {
          backward2FetchCount += 1;
          final List<int> packed = _encodePackedSegment(<List<int>>[
            _encodeChunkedMessage(id: 'b2-1', content: 'msg3'),
          ]);
          request.response.add(packed);
          await request.response.close();
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      // hardLimit=2: first backward segment has 2 messages, should stop there.
      final NdgrTimeshiftClient client = NdgrTimeshiftClient(hardLimit: 2);
      addTearDown(client.dispose);

      final List<AppMessage> allMessages = <AppMessage>[];
      final StreamSubscription<NdgrTimeshiftEvent> subscription = client.events
          .listen((NdgrTimeshiftEvent event) {
            if (event.type == NdgrTimeshiftEventType.progress) {
              allMessages.addAll(event.messages!);
            }
          });
      addTearDown(subscription.cancel);

      await client.fetchPastComments(viewUri, maxMessages: 5000);

      expect(allMessages.length, 2);
      expect(client.hasMore, isFalse);
      expect(client.totalFetched, 2);
      expect(backward2FetchCount, 0);

      // fetchMore should do nothing after hardLimit reached.
      await client.fetchMore(count: 500);
      expect(allMessages.length, 2);
    });
  });
}

// --- Protobuf encoding helpers ---

List<int> _encodeChunkedEntryNext({required int at}) {
  final List<int> readyForNext = _varintField(1, at);
  return _bytesField(4, readyForNext);
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
