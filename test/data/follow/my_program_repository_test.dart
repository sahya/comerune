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

    test('falls back to tool endpoint when front endpoint fails', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        _FakeResponseConfig(statusCode: 404, body: ''),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'nicoliveProgramId': 'lv777000111',
                'title': 'Tool Fallback Broadcast',
                'status': 'onAir',
                'onAirBeginAt': 1713000000,
              },
            ],
          }),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.programId, 'lv777000111');
      expect(result.title, 'Tool Fallback Broadcast');
      expect(httpClient.requests, hasLength(2));
      expect(
        httpClient.requests[0].uri.toString(),
        'https://live.nicovideo.jp/front/api/pages/my/v1/programs?status=onair',
      );
      expect(
        httpClient.requests[1].uri.toString(),
        'https://live2.nicovideo.jp/unama/tool/v1/program_schedules',
      );

      repository.dispose();
    });

    test(
      'uses tool endpoint when front endpoint returns empty programs',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
          _FakeResponseConfig(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'data': <String, Object?>{'programs': <Object?>[]},
            }),
          ),
          _FakeResponseConfig(
            statusCode: 200,
            body: jsonEncode(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'nicoliveProgramId': 'lv888000111',
                  'title': 'Recovered From Tool',
                  'status': 'onAir',
                },
              ],
            }),
          ),
        ]);

        final MyProgramRepository repository = MyProgramRepository(
          httpClient: httpClient,
        );

        final result = await repository.fetchOwnProgram(
          userSession: 'test_session',
        );

        expect(result, isNotNull);
        expect(result!.programId, 'lv888000111');
        expect(result.title, 'Recovered From Tool');
        expect(httpClient.requests, hasLength(2));

        repository.dispose();
      },
    );

    test(
      'extracts icon from front endpoint using provider ID fallback',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBody = jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200},
          'data': <String, Object?>{
            'programs': <Object?>[
              <String, Object?>{
                'id': 'lv123450001',
                'title': 'Front Fallback Icon',
                'supplier': <String, Object?>{
                  'name': 'Fallback Supplier',
                  'programProviderId': 18897569,
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
        expect(
          result!.providerIconUrl,
          'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/1889/18897569.jpg',
        );

        repository.dispose();
      },
    );

    test('returns null when tool endpoint has no on-air programs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        _FakeResponseConfig(statusCode: 500, body: ''),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'nicoliveProgramId': 'lv999000111',
                'title': 'Not On Air',
                'status': 'ended',
              },
            ],
          }),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);
      expect(httpClient.requests, hasLength(2));

      repository.dispose();
    });

    test('skips tool fallback on second call within cache duration', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // First call: front → empty, tool → empty (both queried).
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
        // Second call: front → empty (tool is skipped due to cache).
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result1 = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );
      expect(result1, isNull);
      expect(httpClient.requests, hasLength(2));

      final result2 = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );
      expect(result2, isNull);
      // Only front-api was called, tool was skipped (cache hit).
      expect(httpClient.requests, hasLength(3));

      repository.dispose();
    });

    test('clears tool fallback cache when front-api finds a program', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        // First call: front → empty, tool → empty.
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
        // Second call: front → found (cache cleared).
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'programs': <Object?>[
                <String, Object?>{
                  'id': 'lv999',
                  'title': 'Found',
                  'programProvider': <String, Object?>{'name': 'User'},
                },
              ],
            },
          }),
        ),
        // Third call: front → empty, tool should be queried (cache cleared).
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      await repository.fetchOwnProgram(userSession: 'test_session');
      expect(httpClient.requests, hasLength(2));

      final result2 = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );
      expect(result2, isNotNull);
      expect(result2!.programId, 'lv999');
      expect(httpClient.requests, hasLength(3));

      // After finding a program, cache is cleared, so tool should be tried.
      await repository.fetchOwnProgram(userSession: 'test_session');
      expect(httpClient.requests, hasLength(5));

      repository.dispose();
    });

    test('extracts icon from tool endpoint using provider ID fallback', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        _FakeResponseConfig(statusCode: 404, body: ''),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'nicoliveProgramId': 'lv777000222',
                'title': 'Tool Fallback Icon',
                'status': 'onAir',
                'supplier': <String, Object?>{
                  'name': 'Tool Supplier',
                  'programProviderId': 18897569,
                },
              },
            ],
          }),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchOwnProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(
        result!.providerIconUrl,
        'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/1889/18897569.jpg',
      );

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

    test('invalidates tool fallback cache when session changes', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        // First call (session A): front → empty, tool → empty.
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
        // Second call (session B): front → empty, tool → queried
        // because session changed and cache was invalidated.
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      // Call with session A — populates cache.
      final result1 = await repository.fetchOwnProgram(
        userSession: 'session_a',
      );
      expect(result1, isNull);
      expect(httpClient.requests, hasLength(2));

      // Call with session B — cache should be invalidated, tool queried again.
      final result2 = await repository.fetchOwnProgram(
        userSession: 'session_b',
      );
      expect(result2, isNull);
      // Both front and tool were called (cache invalidated on session change).
      expect(httpClient.requests, hasLength(4));

      repository.dispose();
    });

    test('retains tool fallback cache when same session calls again', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        // First call: front → empty, tool → empty.
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
        ),
        // Second call (same session): front → empty, tool skipped (cache hit).
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
        // Third call (same session again): front → empty, tool skipped.
        _FakeResponseConfig(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'data': <String, Object?>{'programs': <Object?>[]},
          }),
        ),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      await repository.fetchOwnProgram(userSession: 'session_x');
      expect(httpClient.requests, hasLength(2));

      await repository.fetchOwnProgram(userSession: 'session_x');
      // Tool skipped — only front queried.
      expect(httpClient.requests, hasLength(3));

      await repository.fetchOwnProgram(userSession: 'session_x');
      // Tool still skipped — only front queried.
      expect(httpClient.requests, hasLength(4));

      repository.dispose();
    });
  });

  group('fetchControllableProgram', () {
    _FakeResponseConfig onAirResponse(String id, String title) {
      return _FakeResponseConfig(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200},
          'data': <String, Object?>{
            'programs': <Object?>[
              <String, Object?>{
                'id': id,
                'title': title,
                'programProvider': <String, Object?>{'name': 'TestUser'},
              },
            ],
          },
        }),
      );
    }

    _FakeResponseConfig emptyResponse() {
      return _FakeResponseConfig(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200},
          'data': <String, Object?>{'programs': <Object?>[]},
        }),
      );
    }

    // Also need empty tool endpoint response for fallback path.
    _FakeResponseConfig emptyToolResponse() {
      return _FakeResponseConfig(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'data': <Object?>[]}),
      );
    }

    test('returns on-air program when available', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // front-api returns on-air program immediately.
      httpClient.queuedResponses.add(onAirResponse('lv111', 'On Air'));

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchControllableProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.programId, 'lv111');
      // Should only make one request (on-air found immediately).
      expect(httpClient.requests, hasLength(1));
      expect(httpClient.requests[0].uri.queryParameters['status'], 'onair');

      repository.dispose();
    });

    test('falls back to reserved when on-air is empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // 1: front-api onair → empty, 2: tool → empty, 3: front-api reserved → found
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        emptyResponse(),
        emptyToolResponse(),
        onAirResponse('lv222', 'Reserved'),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchControllableProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.programId, 'lv222');
      expect(httpClient.requests, hasLength(3));
      expect(httpClient.requests[2].uri.queryParameters['status'], 'reserved');

      repository.dispose();
    });

    test('falls back to test when on-air and reserved are empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // 1: front-api onair → empty, 2: tool → empty,
      // 3: front-api reserved → empty, 4: front-api test → found
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        emptyResponse(),
        emptyToolResponse(),
        emptyResponse(),
        onAirResponse('lv333', 'Test'),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchControllableProgram(
        userSession: 'test_session',
      );

      expect(result, isNotNull);
      expect(result!.programId, 'lv333');
      expect(httpClient.requests, hasLength(4));
      expect(httpClient.requests[3].uri.queryParameters['status'], 'test');

      repository.dispose();
    });

    test('returns null when all statuses are empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // 1: front-api onair → empty, 2: tool → empty,
      // 3: front-api reserved → empty, 4: front-api test → empty
      httpClient.queuedResponses.addAll(<_FakeResponseConfig>[
        emptyResponse(),
        emptyToolResponse(),
        emptyResponse(),
        emptyResponse(),
      ]);

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchControllableProgram(
        userSession: 'test_session',
      );

      expect(result, isNull);
      expect(httpClient.requests, hasLength(4));

      repository.dispose();
    });

    test('returns null when user session is empty', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();

      final MyProgramRepository repository = MyProgramRepository(
        httpClient: httpClient,
      );

      final result = await repository.fetchControllableProgram(userSession: '');

      expect(result, isNull);
      expect(httpClient.requests, isEmpty);

      repository.dispose();
    });
  });
}

class _FakeResponseConfig {
  _FakeResponseConfig({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
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
  final List<_FakeResponseConfig> queuedResponses = <_FakeResponseConfig>[];
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

    final _FakeResponseConfig config = client.queuedResponses.isNotEmpty
        ? client.queuedResponses.removeAt(0)
        : _FakeResponseConfig(
            statusCode: client.responseStatusCode,
            body: client.responseBody,
          );

    return _FakeHttpClientResponse(
      statusCode: config.statusCode,
      body: config.body,
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
