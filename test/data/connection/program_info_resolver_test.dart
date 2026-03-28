import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/connection/program_info_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProgramInfoResolver', () {
    test('resolves NDGR viewUri from programinfo API', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'status': 'onAir',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BBzh6D87sTyy',
            },
          ],
          'title': 'Test Program',
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv350186414',
        userSession: 'user_session_abc123',
      );

      expect(
        result.viewUri.toString(),
        'https://mpn.live.nicovideo.jp/api/view/v4/BBzh6D87sTyy',
      );
      expect(result.title, 'Test Program');

      expect(httpClient.requests, hasLength(1));
      final _CapturedRequest request = httpClient.requests[0];
      expect(
        request.uri.toString(),
        'https://live2.nicovideo.jp/watch/lv350186414/programinfo',
      );
      expect(
        request.headers['X-Niconico-Session'],
        'user_session_abc123',
      );
      expect(request.headers['User-Agent'], isNotNull);

      resolver.dispose();
    });

    test('throws when user_session is empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: ''),
        throwsA(isA<ProgramInfoResolveException>()),
      );
      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: '   '),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      expect(httpClient.requests, isEmpty);
      resolver.dispose();
    });

    test('throws when API returns non-200', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseStatusCode = 401;
      httpClient.responseBody = 'Unauthorized';

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when response has no rooms', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'status': 'onAir',
          'rooms': <Object?>[],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when room has no viewUri', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'rooms': <Object?>[
            <String, Object?>{},
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', userSession: 'session'),
        throwsA(isA<ProgramInfoResolveException>()),
      );

      resolver.dispose();
    });
  });

  group('ProgramInfoResolveException', () {
    test('toString includes message', () {
      final ProgramInfoResolveException exception =
          ProgramInfoResolveException('test error');
      expect(
        exception.toString(),
        'ProgramInfoResolveException: test error',
      );
    });
  });
}

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(
      uri: url,
      client: this,
    );
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
  _FakeHttpClientRequest({required this.uri, required this.client});

  @override
  final Uri uri;
  final _FakeHttpClient client;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    final Map<String, String> headerMap = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        headerMap[key] = values.first;
      }
    });

    client.requests.add(
      _CapturedRequest(uri: uri, headers: headerMap),
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
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
