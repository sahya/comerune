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
      expect(result.broadcasterUserId, isNull);
      expect(result.broadcasterName, isNull);
      expect(result.beginAt, isNull);

      expect(httpClient.requests, hasLength(1));
      final _CapturedRequest request = httpClient.requests[0];
      expect(
        request.uri.toString(),
        'https://live2.nicovideo.jp/watch/lv350186414/programinfo',
      );
      expect(request.headers['X-Niconico-Session'], 'user_session_abc123');
      expect(request.headers['User-Agent'], isNotNull);

      resolver.dispose();
    });

    test('extracts broadcaster user ID from broadcaster array', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Broadcaster Program',
          'broadcaster': <Object?>[
            <String, Object?>{'id': 67890, 'name': '配信者A'},
          ],
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/Broadcaster',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv1000',
        userSession: 'session',
      );

      expect(result.title, 'Broadcaster Program');
      expect(result.broadcasterUserId, '67890');
      expect(result.broadcasterName, '配信者A');

      resolver.dispose();
    });

    test(
      'falls back to supplier name and ID when broadcaster is absent',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Supplier Fallback',
            'supplier': <String, Object?>{
              'name': 'テスト配信者',
              'programProviderId': 12345,
            },
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/TestSupplier',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv999',
          userSession: 'session',
        );

        expect(result.title, 'Supplier Fallback');
        expect(result.broadcasterUserId, '12345');
        expect(result.broadcasterName, 'テスト配信者');

        resolver.dispose();
      },
    );

    test('prefers broadcaster over supplier when both exist', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Both Present',
          'broadcaster': <Object?>[
            <String, Object?>{'id': 11111, 'name': '配信者B'},
          ],
          'supplier': <String, Object?>{'programProviderId': 22222},
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BothPresent',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv1001',
        userSession: 'session',
      );

      expect(result.broadcasterUserId, '11111');
      expect(result.broadcasterName, '配信者B');

      resolver.dispose();
    });

    test(
      'returns null broadcasterUserId when neither broadcaster nor supplier has ID',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'No IDs',
            'broadcaster': <Object?>[
              <String, Object?>{'name': '名前だけ'},
            ],
            'supplier': <String, Object?>{'name': 'テスト配信者'},
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/NoIds',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(
          lv: 'lv888',
          userSession: 'session',
        );

        expect(result.title, 'No IDs');
        expect(result.broadcasterUserId, isNull);
        expect(result.broadcasterName, 'テスト配信者');

        resolver.dispose();
      },
    );

    test('extracts beginAt from ISO 8601 string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'BeginAt Program',
          'beginAt': '2025-07-01T12:00:00+09:00',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BeginAtTest',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2000',
        userSession: 'session',
      );

      expect(result.beginAt, isNotNull);
      expect(result.beginAt, isA<DateTime>());
      // 2025-07-01T12:00:00+09:00 == 2025-07-01T03:00:00Z
      expect(result.beginAt!.toUtc(), DateTime.utc(2025, 7, 1, 3, 0, 0));

      resolver.dispose();
    });

    test('returns null beginAt when field is absent', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'No BeginAt',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/NoBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2001',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('extracts beginAt from integer (seconds since epoch)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // 1719828000 == 2024-07-01T10:00:00Z
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'BeginAt Integer',
          'beginAt': 1719828000,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri': 'https://mpn.live.nicovideo.jp/api/view/v4/BeginAtInt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2002',
        userSession: 'session',
      );

      expect(result.beginAt, isNotNull);
      expect(result.beginAt!.toUtc(), DateTime.utc(2024, 7, 1, 10, 0, 0));

      resolver.dispose();
    });

    test('returns null beginAt for empty string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Empty BeginAt',
          'beginAt': '',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/EmptyBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2003',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for invalid date string', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Invalid BeginAt',
          'beginAt': 'not-a-date',
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/InvalidBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2004',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt when value is explicit null', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Null BeginAt',
          'beginAt': null,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/NullBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2005',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for unexpected type (bool)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Bool BeginAt',
          'beginAt': true,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/BoolBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2006',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test('returns null beginAt for float value', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
        'data': <String, Object?>{
          'title': 'Float BeginAt',
          'beginAt': 1719828000.5,
          'rooms': <Object?>[
            <String, Object?>{
              'viewUri':
                  'https://mpn.live.nicovideo.jp/api/view/v4/FloatBeginAt',
            },
          ],
        },
      });

      final ProgramInfoResolver resolver = ProgramInfoResolver(
        httpClient: httpClient,
      );

      final ProgramInfo result = await resolver.resolve(
        lv: 'lv2007',
        userSession: 'session',
      );

      expect(result.beginAt, isNull);

      resolver.dispose();
    });

    test(
      'sends request without auth headers when user_session is empty',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'title': 'Public Program',
            'rooms': <Object?>[
              <String, Object?>{
                'viewUri':
                    'https://mpn.live.nicovideo.jp/api/view/v4/PublicTest',
              },
            ],
          },
        });

        final ProgramInfoResolver resolver = ProgramInfoResolver(
          httpClient: httpClient,
        );

        final ProgramInfo result = await resolver.resolve(lv: 'lv123');
        expect(result.title, 'Public Program');

        expect(httpClient.requests, hasLength(1));
        final _CapturedRequest request = httpClient.requests[0];
        // No auth headers should be set.
        expect(request.headers['Cookie'], isNull);
        expect(request.headers['X-Niconico-Session'], isNull);
        expect(request.headers['User-Agent'], isNotNull);

        resolver.dispose();
      },
    );

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
        'data': <String, Object?>{'status': 'onAir', 'rooms': <Object?>[]},
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
          'rooms': <Object?>[<String, Object?>{}],
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
      final ProgramInfoResolveException exception = ProgramInfoResolveException(
        'test error',
      );
      expect(exception.toString(), 'ProgramInfoResolveException: test error');
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
