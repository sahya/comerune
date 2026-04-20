import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/timeshift_fetch/timeshift_fetch_controller.dart';
import 'package:comerune/domain/connection/ndgr_timeshift_client.dart';
import 'package:comerune/domain/models/app_message.dart';

void main() {
  group('TimeshiftFetchController', () {
    test('starts in idle status', () {
      final FakeTimeshiftClient client = FakeTimeshiftClient();
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      expect(controller.status, TimeshiftFetchStatus.idle);
      expect(controller.totalFetched, 0);
      expect(controller.hasMore, isFalse);
      expect(controller.isFetchingAll, isFalse);
    });

    group('TimeshiftFetchError.classify', () {
      test('HTTP 403 is classified as non-retryable (premium-only case)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift session request failed with status 403',
          ),
        );
        expect(error.retryable, isFalse);
      });

      test('HTTP 401 is classified as non-retryable (auth)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift session request failed with status 401',
          ),
        );
        expect(error.retryable, isFalse);
      });

      test('HTTP 404 is classified as non-retryable (removed)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift session request failed with status 404',
          ),
        );
        expect(error.retryable, isFalse);
      });

      test('HTTP 408 Request Timeout is retryable (transient)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift backward request failed with status 408',
          ),
        );
        expect(error.retryable, isTrue);
      });

      test('HTTP 429 Too Many Requests is retryable (transient)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift backward request failed with status 429',
          ),
        );
        expect(error.retryable, isTrue);
      });

      test('HTTP 503 is classified as retryable (server side)', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException(
            'NDGR timeshift backward request failed with status 503',
          ),
        );
        expect(error.retryable, isTrue);
      });

      test('SocketException is retryable', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const SocketException('reset'),
        );
        expect(error.retryable, isTrue);
      });

      test('TimeoutException is retryable', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          TimeoutException('timed out'),
        );
        expect(error.retryable, isTrue);
      });

      test('Unknown exception falls back to retryable=true', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          StateError('unexpected'),
        );
        expect(error.retryable, isTrue);
      });

      test('HttpException with no status digits is retryable', () {
        final TimeshiftFetchError error = TimeshiftFetchError.classify(
          const HttpException('some message without status code'),
        );
        expect(error.retryable, isTrue);
      });

      test(
        'stray 3-digit numbers before "status <N>" do not shadow the code',
        () {
          // `_extractHttpStatus` anchors the match to end-of-string, so a
          // numeric value earlier in the message (e.g. a response body with
          // `"errorCode": 200`) must not be picked as the status.
          final TimeshiftFetchError error = TimeshiftFetchError.classify(
            const HttpException(
              'NDGR timeshift session request failed with status 403',
            ),
          );
          expect(error.retryable, isFalse);
        },
      );

      test(
        'message format matches NdgrTimeshiftClient — lock-step parser guard',
        () {
          // NdgrTimeshiftClient._fetch throws HttpException with the literal
          // format:
          //   'NDGR timeshift <phase> request failed with status <N>'
          // (see lib/domain/connection/ndgr_timeshift_client.dart).
          // `TimeshiftFetchError.classify` depends on this shape. If either
          // side changes the format, 4xx responses would silently fall back
          // to retryable=true.
          for (final String phase in <String>[
            'session',
            'backward',
            'previous',
            'view',
          ]) {
            final TimeshiftFetchError error = TimeshiftFetchError.classify(
              HttpException(
                'NDGR timeshift $phase request failed with status 403',
              ),
            );
            expect(
              error.retryable,
              isFalse,
              reason: 'phase=$phase must be parsed as 4xx',
            );
          }
          for (final int status in <int>[500, 502, 503, 504]) {
            final TimeshiftFetchError error = TimeshiftFetchError.classify(
              HttpException(
                'NDGR timeshift session request failed with status $status',
              ),
            );
            expect(
              error.retryable,
              isTrue,
              reason: 'status=$status must be parsed as 5xx (retryable)',
            );
          }
        },
      );
    });

    test('fetchInitial transitions to paused when hasMore', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: true, totalFetched: 5000),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));

      expect(controller.status, TimeshiftFetchStatus.paused);
      expect(controller.totalFetched, 5000);
      expect(controller.hasMore, isTrue);
    });

    test('fetchInitial transitions to completed when no more', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: false, totalFetched: 100),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));

      expect(controller.status, TimeshiftFetchStatus.completed);
      expect(controller.hasMore, isFalse);
    });

    test('fetchInitial transitions to error on failure', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(error: StateError('test error')),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));

      expect(controller.status, TimeshiftFetchStatus.error);
      expect(controller.lastError, isA<TimeshiftFetchError>());
      expect(controller.lastError!.cause, isA<StateError>());
      // Unknown exceptions fall back to retryable=true (legacy behaviour).
      expect(controller.lastError!.retryable, isTrue);
    });

    test('fetchMore transitions to paused when hasMore', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: true, totalFetched: 5000),
        fetchMoreResult: FakeFetchResult(hasMore: true, totalFetched: 5500),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));
      await controller.fetchMore(500);

      expect(controller.status, TimeshiftFetchStatus.paused);
      expect(controller.totalFetched, 5500);
    });

    test('fetchAll fetches in batches until no more', () async {
      int fetchMoreCallCount = 0;
      late final FakeTimeshiftClient client;
      client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: true, totalFetched: 5000),
        fetchMoreHandler: (int count) async {
          fetchMoreCallCount += 1;
          if (fetchMoreCallCount >= 3) {
            client.setHasMore(false);
            client.setTotalFetched(6500);
          } else {
            client.setTotalFetched(5000 + fetchMoreCallCount * 500);
          }
        },
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
        fetchAllBatchSize: 500,
        fetchAllBatchDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));
      await controller.fetchAll();

      expect(controller.status, TimeshiftFetchStatus.completed);
      expect(controller.isFetchingAll, isFalse);
      expect(fetchMoreCallCount, 3);
    });

    test('cancel stops fetchAll', () async {
      int fetchMoreCallCount = 0;
      final Completer<void> secondBatchStarted = Completer<void>();
      late final FakeTimeshiftClient client;
      client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: true, totalFetched: 5000),
        fetchMoreHandler: (int count) async {
          fetchMoreCallCount += 1;
          if (fetchMoreCallCount == 2) {
            secondBatchStarted.complete();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          client.setTotalFetched(5000 + fetchMoreCallCount * 500);
        },
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
        fetchAllBatchSize: 500,
        fetchAllBatchDelay: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));
      final Future<void> fetchAllFuture = controller.fetchAll();

      await secondBatchStarted.future;
      await controller.cancel();
      await fetchAllFuture;

      expect(controller.isFetchingAll, isFalse);
      expect(
        controller.status,
        anyOf(TimeshiftFetchStatus.paused, TimeshiftFetchStatus.completed),
      );
    });

    test('progress events deliver messages via onMessages callback', () async {
      final List<AppMessage> receivedMessages = <AppMessage>[];
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: false, totalFetched: 2),
        progressMessages: <AppMessage>[
          AppMessage(
            id: 'msg-1',
            timestamp: DateTime.utc(2026),
            content: 'hello',
            type: AppMessageType.chat,
          ),
          AppMessage(
            id: 'msg-2',
            timestamp: DateTime.utc(2026),
            content: 'world',
            type: AppMessageType.chat,
          ),
        ],
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: receivedMessages.addAll,
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));

      expect(receivedMessages.length, 2);
    });

    test('reset returns to idle status', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: false, totalFetched: 100),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));
      expect(controller.status, TimeshiftFetchStatus.completed);

      controller.reset();
      expect(controller.status, TimeshiftFetchStatus.idle);
    });

    test('notifies listeners on status change', () async {
      final FakeTimeshiftClient client = FakeTimeshiftClient(
        fetchPastResult: FakeFetchResult(hasMore: false, totalFetched: 10),
      );
      final TimeshiftFetchController controller = TimeshiftFetchController(
        client: client,
        onMessages: (_) {},
      );
      addTearDown(controller.dispose);

      int notifyCount = 0;
      controller.addListener(() => notifyCount += 1);

      await controller.fetchInitial(Uri.parse('http://example.com/view'));

      // At minimum: fetching + completed = 2 notifications
      expect(notifyCount, greaterThanOrEqualTo(2));
    });
  });
}

class FakeFetchResult {
  const FakeFetchResult({
    this.hasMore = false,
    this.totalFetched = 0,
    this.error,
  });

  final bool hasMore;
  final int totalFetched;
  final Object? error;
}

class FakeTimeshiftClient implements NdgrTimeshiftClient {
  FakeTimeshiftClient({
    this.fetchPastResult = const FakeFetchResult(),
    this.fetchMoreResult,
    this.fetchMoreHandler,
    this.progressMessages = const <AppMessage>[],
  });

  FakeFetchResult fetchPastResult;
  FakeFetchResult? fetchMoreResult;
  Future<void> Function(int count)? fetchMoreHandler;
  List<AppMessage> progressMessages;

  bool _hasMore = false;
  int _totalFetched = 0;
  bool _isSessionOpen = false;
  bool _isRunning = false;
  final StreamController<NdgrTimeshiftEvent> _eventsController =
      StreamController<NdgrTimeshiftEvent>.broadcast(sync: true);

  void setHasMore(bool value) => _hasMore = value;
  void setTotalFetched(int value) => _totalFetched = value;

  @override
  Stream<NdgrTimeshiftEvent> get events => _eventsController.stream;

  @override
  bool get hasMore => _hasMore;

  @override
  bool get isRunning => _isRunning;

  @override
  bool get isSessionOpen => _isSessionOpen;

  @override
  int get totalFetched => _totalFetched;

  @override
  Future<void> fetchPastComments(
    Uri viewApiUri, {
    int maxMessages = NdgrTimeshiftClient.defaultInitialLimit,
  }) async {
    _isRunning = true;
    _isSessionOpen = true;

    if (fetchPastResult.error != null) {
      _isRunning = false;
      throw fetchPastResult.error!;
    }

    if (progressMessages.isNotEmpty) {
      _eventsController.add(
        NdgrTimeshiftEvent.progress(
          messages: progressMessages,
          fetchedCount: progressMessages.length,
        ),
      );
    }

    _hasMore = fetchPastResult.hasMore;
    _totalFetched = fetchPastResult.totalFetched;
    _isRunning = false;
  }

  @override
  Future<void> fetchMore({required int count}) async {
    _isRunning = true;

    if (fetchMoreHandler != null) {
      await fetchMoreHandler!(count);
      _isRunning = false;
      return;
    }

    final FakeFetchResult result = fetchMoreResult ?? fetchPastResult;
    if (result.error != null) {
      _isRunning = false;
      throw result.error!;
    }

    _hasMore = result.hasMore;
    _totalFetched = result.totalFetched;
    _isRunning = false;
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
  }

  @override
  void resetSession() {
    _isSessionOpen = false;
    _hasMore = false;
    _totalFetched = 0;
  }

  @override
  void dispose() {
    _eventsController.close();
  }
}
