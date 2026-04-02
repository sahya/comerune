import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/follow/my_program_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MyProgramRepository', () {
    test('returns own program when user is broadcasting', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv345678901',
              'title': 'My Broadcast',
              'programProvider': <String, Object?>{
                'name': 'TestUser',
                'iconSmall': 'https://example.com/icon.jpg',
              },
              'beginAt': '2026-03-30T10:00:00+09:00',
            },
          ],
        },
      });

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.programId, 'lv345678901');
      expect(result.title, 'My Broadcast');
      expect(result.providerName, 'TestUser');
      expect(result.providerIconUrl, 'https://example.com/icon.jpg');
      expect(result.isOwnBroadcast, isTrue);

      expect(httpClient.requests, hasLength(1));
      final _CapturedRequest request = httpClient.requests[0];
      expect(
        request.uri.toString(),
        'https://live.nicovideo.jp/front/api/pages/my/v1/programs?status=onair',
      );
      expect(request.headers['X-Niconico-Session'], 'test_session');

      repository.dispose();
    });

    test('returns null when user is not broadcasting', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{'programs': <Object?>[]},
      });

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('returns null when user session is empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(userSession: '');

      expect(result, isNull);
      expect(httpClient.requests, isEmpty);

      repository.dispose();
    });

    test('returns null on HTTP error', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseStatusCode = 500;
      httpClient.responseBody = '';

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('returns null when response has no data field', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
      });

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('extracts provider name from supplier fallback', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200},
        'data': <String, Object?>{
          'programs': <Object?>[
            <String, Object?>{
              'id': 'lv345678901',
              'title': 'My Broadcast',
              'supplier': <String, Object?>{
                'name': 'SupplierUser',
                'icons': <String, Object?>{
                  'uri50x50': 'https://example.com/icon50.jpg',
                },
              },
            },
          ],
        },
      });

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.providerName, 'SupplierUser');
      expect(result.providerIconUrl, 'https://example.com/icon50.jpg');

      repository.dispose();
    });

    test('returns null on network exception', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.shouldThrowOnRequest = true;

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('returns null when response is not a JSON object', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = '"just a string"';

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('returns null when first program item is not a map', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{
          'programs': <Object?>['not-a-map'],
        },
      });

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);

      repository.dispose();
    });

    test('returns null when user session is whitespace only', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(userSession: '   ');

      expect(result, isNull);
      expect(httpClient.requests, isEmpty);

      repository.dispose();
    });

    test(
      'returns program with empty provider name when name is missing',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200},
          'data': <String, Object?>{
            'programs': <Object?>[
              <String, Object?>{'id': 'lv345678901', 'title': 'My Broadcast'},
            ],
          },
        });

        final MyProgramRepository repository = MyProgramRepository(
          httpClient: httpClient,
        );

        final result = await repository.fetchOwnProgram(
          userSession: 'test_session',
        );

        expect(result, isNotNull);
        expect(result!.providerName, '');

        repository.dispose();
      },
    );
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
  bool shouldThrowOnRequest = false;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return _FakeHttpClientRequest(uri: url, client: this);
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

    client.requests.add(_CapturedRequest(uri: uri, headers: headerMap));

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
