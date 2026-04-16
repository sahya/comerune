import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/broadcast/broadcast_control_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BroadcastControlRepository', () {
    group('startBroadcast', () {
      test('sends PUT with on_air state and returns success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'start_time': 1711896400,
            'end_time': 1711900000,
          },
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isTrue);
        expect(result.startTime, 1711896400);
        expect(result.endTime, 1711900000);

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        expect(request.method, 'PUT');
        expect(
          request.uri.toString(),
          'https://live2.nicovideo.jp/watch/lv345678901/segment',
        );
        expect(request.headers['X-Niconico-Session'], 'test_session');
        expect(request.body, jsonEncode(<String, String>{'state': 'on_air'}));

        repository.dispose();
      });

      test('returns error on HTTP 403', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 403;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 403, 'errorCode': 'FORBIDDEN'},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'FORBIDDEN');

        repository.dispose();
      });

      test('returns error when programId is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: '',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns error when userSession is empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: '',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');
        expect(httpClient.requests, isEmpty);

        repository.dispose();
      });

      test('returns NETWORK_ERROR on exception', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.shouldThrowOnRequest = true;

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');

        repository.dispose();
      });
    });

    group('endBroadcast', () {
      test('sends PUT with end state and returns success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{'end_time': 1711900000},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.endBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isTrue);
        expect(result.endTime, 1711900000);

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        expect(request.method, 'PUT');
        expect(request.body, jsonEncode(<String, String>{'state': 'end'}));

        repository.dispose();
      });

      test('returns isAlreadyEnded on HTTP 409', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 409;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 409, 'errorCode': 'CONFLICT'},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.endBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.isAlreadyEnded, isTrue);

        repository.dispose();
      });
    });

    group('extendBroadcast', () {
      test('sends POST with minutes and returns success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{'end_time': 1711903600},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.extendBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
          minutes: 30,
        );

        expect(result.success, isTrue);
        expect(result.endTime, 1711903600);

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        expect(request.method, 'POST');
        expect(
          request.uri.toString(),
          'https://live2.nicovideo.jp/watch/lv345678901/extension',
        );
        expect(request.body, jsonEncode(<String, int>{'minutes': 30}));

        repository.dispose();
      });

      test('returns error when params are empty', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.extendBroadcast(
          programId: '',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'INVALID_PARAMS');

        repository.dispose();
      });
    });

    group('request timeout (#485)', () {
      test('returns NETWORK_ERROR and aborts the request when startBroadcast '
          'stalls beyond timeout', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.pendingCompleter = Completer<void>();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(
              httpClient: httpClient,
              requestTimeout: const Duration(milliseconds: 50),
            );

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');
        expect(httpClient.requests.single.request.isAborted, isTrue);

        httpClient.pendingCompleter!.complete();
        repository.dispose();
      });

      // Billing-critical: endBroadcast controls when a paid slot is released.
      // A leaked connection here could leave a programme running (and billing)
      // indefinitely.
      test('aborts the request on timeout for endBroadcast as well', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.pendingCompleter = Completer<void>();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(
              httpClient: httpClient,
              requestTimeout: const Duration(milliseconds: 50),
            );

        final BroadcastControlResult result = await repository.endBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');
        expect(httpClient.requests.single.request.isAborted, isTrue);

        httpClient.pendingCompleter!.complete();
        repository.dispose();
      });

      test(
        'aborts the request on timeout for extendBroadcast as well',
        () async {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          httpClient.pendingCompleter = Completer<void>();
          httpClient.responseStatusCode = 200;
          httpClient.responseBody = '';

          final BroadcastControlRepository repository =
              BroadcastControlRepository(
                httpClient: httpClient,
                requestTimeout: const Duration(milliseconds: 50),
              );

          final BroadcastControlResult result = await repository
              .extendBroadcast(
                programId: 'lv345678901',
                userSession: 'test_session',
                minutes: 30,
              );

          expect(result.success, isFalse);
          expect(result.errorCode, 'NETWORK_ERROR');
          expect(result.errorMessage, contains('TimeoutException'));
          expect(result.errorMessage, contains('0:00:00.050'));
          expect(httpClient.requests.single.request.isAborted, isTrue);

          httpClient.pendingCompleter!.complete();
          repository.dispose();
        },
      );

      test('does NOT abort the request for non-timeout failures', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 500;
        httpClient.responseBody = 'boom';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(
              httpClient: httpClient,
              requestTimeout: const Duration(milliseconds: 50),
            );

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(
          httpClient.requests.single.request.isAborted,
          isFalse,
          reason: 'abort() should only be called on timeout, not HTTP errors',
        );

        repository.dispose();
      });

      test('aborts the request when the response body stalls beyond timeout '
          '(Issue #466 follow-up)', () async {
        // Regression lock for the body-read timeout consistency fix:
        // [LiveCommentRepository._parseResponse] already wraps its
        // `response.transform(utf8.decoder).join()` with
        // `.timeout(_requestTimeout)`, but [BroadcastControlRepository]
        // was missing the same guard. A stalled body would otherwise
        // hang the broadcast Start/End/Extend call indefinitely even
        // though `request.close()` itself returned. With the fix in
        // place, the [TimeoutException] thrown from the body-read
        // propagates back to the catch block which aborts the
        // underlying request.
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.bodyStallCompleter = Completer<void>();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = '';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(
              httpClient: httpClient,
              requestTimeout: const Duration(milliseconds: 50),
            );

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'NETWORK_ERROR');
        expect(result.errorMessage, contains('TimeoutException'));
        // Mirror LiveCommentRepository's body-stall assertion pattern:
        // the configured duration (50ms) is preserved in the error
        // message via `_handleTimeout`'s `e.toString()` so incident
        // triage can see how long we waited. Using a partial match
        // tolerates both the ms (`0:00:00.050`) and microseconds
        // (`0:00:00.050000`) formatting variants.
        expect(result.errorMessage, contains('0:00:00.050'));
        expect(httpClient.requests.single.request.isAborted, isTrue);

        httpClient.bodyStallCompleter!.complete();
        repository.dispose();
      });
    });

    group('defensive input validation', () {
      test(
        'rejects user_session containing CR / LF / NUL (header injection)',
        () async {
          for (final String poison in <String>[
            'valid\r\nX-Injected: 1',
            'valid\nfoo',
            'valid\r',
            'bad\u0000byte',
          ]) {
            final _FakeHttpClient httpClient = _FakeHttpClient();
            final BroadcastControlRepository repository =
                BroadcastControlRepository(httpClient: httpClient);

            final String caseLabel =
                'poisoned session: '
                '${poison.codeUnits.map((int c) => '0x${c.toRadixString(16)}').toList()}';

            final BroadcastControlResult startResult = await repository
                .startBroadcast(programId: 'lv123', userSession: poison);
            expect(startResult.success, isFalse, reason: caseLabel);
            expect(startResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

            final BroadcastControlResult endResult = await repository
                .endBroadcast(programId: 'lv123', userSession: poison);
            expect(endResult.success, isFalse, reason: caseLabel);
            expect(endResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

            final BroadcastControlResult extendResult = await repository
                .extendBroadcast(
                  programId: 'lv123',
                  userSession: poison,
                  minutes: 30,
                );
            expect(extendResult.success, isFalse, reason: caseLabel);
            expect(extendResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

            // No HTTP request should reach the fake client.
            expect(httpClient.requests, isEmpty, reason: caseLabel);

            repository.dispose();
          }
        },
      );

      test('rejects malformed programId values (path injection)', () async {
        for (final String malformed in <String>[
          'lv',
          'lv1a',
          'lv123/../admin',
          '123',
          'LV123',
          'lv 123',
          'lv-123',
          'lv123?foo=bar',
          'lv123#frag',
          'lv１２３',
        ]) {
          final _FakeHttpClient httpClient = _FakeHttpClient();
          final BroadcastControlRepository repository =
              BroadcastControlRepository(httpClient: httpClient);

          final String caseLabel = 'malformed lv: <$malformed>';

          final BroadcastControlResult startResult = await repository
              .startBroadcast(
                programId: malformed,
                userSession: 'valid_session',
              );
          expect(startResult.success, isFalse, reason: caseLabel);
          expect(startResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

          final BroadcastControlResult endResult = await repository
              .endBroadcast(programId: malformed, userSession: 'valid_session');
          expect(endResult.success, isFalse, reason: caseLabel);
          expect(endResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

          final BroadcastControlResult extendResult = await repository
              .extendBroadcast(
                programId: malformed,
                userSession: 'valid_session',
                minutes: 30,
              );
          expect(extendResult.success, isFalse, reason: caseLabel);
          expect(extendResult.errorCode, 'INVALID_PARAMS', reason: caseLabel);

          expect(httpClient.requests, isEmpty, reason: caseLabel);

          repository.dispose();
        }
      });

      test('accepts normal well-formed programId', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 200;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'session',
        );
        expect(result.success, isTrue);
        expect(httpClient.requests, hasLength(1));

        repository.dispose();
      });
    });

    group('response parsing', () {
      test('handles HTTP 204 as success', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 204;
        httpClient.responseBody = '';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isTrue);

        repository.dispose();
      });

      test('handles non-JSON error body', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 500;
        httpClient.responseBody = 'Internal Server Error';

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.endBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorCode, 'HTTP_500');

        repository.dispose();
      });

      test('extracts error message from data.message', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseStatusCode = 400;
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 400},
          'data': <String, Object?>{'message': 'Invalid state transition'},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isFalse);
        expect(result.errorMessage, 'Invalid state transition');

        repository.dispose();
      });

      test('handles success response without data field', () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        });

        final BroadcastControlRepository repository =
            BroadcastControlRepository(httpClient: httpClient);

        final BroadcastControlResult result = await repository.startBroadcast(
          programId: 'lv345678901',
          userSession: 'test_session',
        );

        expect(result.success, isTrue);
        expect(result.startTime, isNull);
        expect(result.endTime, isNull);

        repository.dispose();
      });
    });
  });

  group('BroadcastControlResult', () {
    test('isAlreadyEnded returns true for CONFLICT', () {
      const BroadcastControlResult result = BroadcastControlResult(
        success: false,
        errorCode: 'CONFLICT',
      );
      expect(result.isAlreadyEnded, isTrue);
    });

    test('isAlreadyEnded returns false for other errors', () {
      const BroadcastControlResult result = BroadcastControlResult(
        success: false,
        errorCode: 'FORBIDDEN',
      );
      expect(result.isAlreadyEnded, isFalse);
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.request,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final _FakeHttpClientRequest request;
  final String? body;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  bool shouldThrowOnRequest = false;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  /// When set, each request's `close()` awaits this completer before
  /// returning a response — used to simulate a stalled server for timeout
  /// coverage.
  Completer<void>? pendingCompleter;

  /// When set, the response body stream awaits this completer before
  /// emitting data — used to simulate a server that returns headers
  /// quickly but stalls while streaming the body. Drives the body-read
  /// `_requestTimeout` regression test added by Issue #466 sage review.
  Completer<void>? bodyStallCompleter;

  @override
  Future<HttpClientRequest> putUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this, method: 'PUT');
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this, method: 'POST');
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this, method: 'GET');
  }

  @override
  set connectionTimeout(Duration? timeout) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({
    required this.uri,
    required this.client,
    required this.method,
  });

  @override
  final Uri uri;
  final _FakeHttpClient client;
  @override
  final String method;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  final StringBuffer _body = StringBuffer();

  bool isAborted = false;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    isAborted = true;
  }

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? obj) {
    _body.write(obj);
  }

  @override
  Future<HttpClientResponse> close() async {
    final Map<String, String> headerMap = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        headerMap[key] = values.first;
      }
    });

    client.requests.add(
      _CapturedRequest(
        method: method,
        uri: uri,
        headers: headerMap,
        request: this,
        body: _body.isNotEmpty ? _body.toString() : null,
      ),
    );

    final Completer<void>? gate = client.pendingCompleter;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }

    return _FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
      bodyStallCompleter: client.bodyStallCompleter,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name] = <String>[value.toString()];
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name, () => <String>[]).add(value.toString());
  }

  @override
  List<String>? operator [](String name) {
    return _values[name];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({
    required this.statusCode,
    required String body,
    this.bodyStallCompleter,
  }) : _body = body;

  @override
  final int statusCode;
  final String _body;

  /// When set, the response body stream awaits this completer before
  /// emitting data — used to simulate a stalled response body for
  /// body-read timeout coverage. Mirrors the same hook already in
  /// place on [LiveCommentRepository]'s test fake.
  final Completer<void>? bodyStallCompleter;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final Completer<void>? stall = bodyStallCompleter;
    if (stall != null && !stall.isCompleted) {
      final Stream<List<int>> delayed = stall.future
          .then<List<int>>((_) => utf8.encode(_body))
          .asStream();
      return delayed.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    return Stream<List<int>>.value(utf8.encode(_body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<E> drain<E>([E? futureValue]) {
    return listen(null).asFuture<E>(futureValue as E);
  }

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
