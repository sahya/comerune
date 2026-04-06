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
          'meta': <String, Object?>{
            'status': 403,
            'errorCode': 'FORBIDDEN',
          },
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
          'data': <String, Object?>{
            'end_time': 1711900000,
          },
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
          'meta': <String, Object?>{
            'status': 409,
            'errorCode': 'CONFLICT',
          },
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
          'data': <String, Object?>{
            'end_time': 1711903600,
          },
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
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  bool shouldThrowOnRequest = false;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

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
        body: _body.isNotEmpty ? _body.toString() : null,
      ),
    );

    return _FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
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
  _FakeHttpClientResponse({required this.statusCode, required String body})
      : _body = body;

  @override
  final int statusCode;
  final String _body;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
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
