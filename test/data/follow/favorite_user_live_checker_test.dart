import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/follow/favorite_user_live_checker.dart';
import 'package:comerune/domain/models/follow_program.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to build a broadcast-history API JSON response.
String _buildHistoryResponse({
  required String programId,
  required String status,
  String title = 'テスト放送',
  String providerName = 'テストユーザー',
  int beginTimeSeconds = 1700000000,
  int scheduledEndTimeSeconds = 1700001800,
}) {
  return jsonEncode(<String, dynamic>{
    'meta': <String, dynamic>{'status': 200},
    'data': <String, dynamic>{
      'programsList': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': <String, dynamic>{'value': programId},
          'program': <String, dynamic>{
            'title': title,
            'schedule': <String, dynamic>{
              'status': status,
              'beginTime': <String, dynamic>{
                'seconds': beginTimeSeconds,
                'nanos': 0,
              },
              'scheduledEndTime': <String, dynamic>{
                'seconds': scheduledEndTimeSeconds,
                'nanos': 0,
              },
            },
          },
          'programProvider': <String, dynamic>{
            'name': providerName,
            'programProviderId': <String, dynamic>{'value': '12345'},
            'icons': <String, dynamic>{
              'uri50x50':
                  'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/s/1234/12345.jpg',
              'uri150x150':
                  'https://secure-dcdn.cdn.nimg.jp/nicoaccount/usericon/1234/12345.jpg',
            },
          },
          'socialGroup': <String, dynamic>{
            'name': 'テストコミュニティ',
            'isDeleted': <String, dynamic>{'value': false},
          },
        },
      ],
      'hasNext': false,
    },
  });
}

String _buildEmptyHistoryResponse() {
  return jsonEncode(<String, dynamic>{
    'meta': <String, dynamic>{'status': 200},
    'data': <String, dynamic>{
      'programsList': <Map<String, dynamic>>[],
      'hasNext': false,
    },
  });
}

void main() {
  group('FavoriteUserLiveChecker (broadcast-history API)', () {
    test('returns FollowProgram when user is broadcasting (ON_AIR)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(
            programId: 'lv348712105',
            status: 'ON_AIR',
            title: 'テスト放送タイトル',
            providerName: '放送者名',
          );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, hasLength(1));
      expect(result['12345'], isNotNull);
      expect(result['12345']!.programId, 'lv348712105');
      expect(result['12345']!.title, 'テスト放送タイトル');
      expect(result['12345']!.providerName, '放送者名');
      expect(result['12345']!.status, ProgramStatus.onAir);

      checker.dispose();
    });

    test('returns empty map when user is not broadcasting (ENDED)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(programId: 'lv348712105', status: 'ENDED');

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test('returns empty map when user has no broadcast history', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildEmptyHistoryResponse();

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test('returns empty map for empty user IDs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{});

      expect(result, isEmpty);
      expect(httpClient.requestCount, 0);

      checker.dispose();
    });

    test('handles mixed results for multiple users', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=111'] =
          _buildHistoryResponse(
            programId: 'lv100001',
            status: 'ON_AIR',
            providerName: 'User111',
          );
      httpClient.responseBodyByUrlPrefix['providerId=222'] =
          _buildHistoryResponse(programId: 'lv100002', status: 'ENDED');
      httpClient.responseBodyByUrlPrefix['providerId=333'] =
          _buildHistoryResponse(
            programId: 'lv100003',
            status: 'ON_AIR',
            providerName: 'User333',
          );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        maxConcurrentRequests: 5,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'111', '222', '333'});

      expect(result, hasLength(2));
      expect(result['111']!.programId, 'lv100001');
      expect(result['333']!.programId, 'lv100003');

      checker.dispose();
    });

    test('handles network error gracefully', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.throwOnUrlPrefix['providerId=999'] = const SocketException(
        'Connection refused',
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'999'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test('handles timeout gracefully', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.throwOnUrlPrefix['providerId=12345'] = TimeoutException(
        'Connection timed out',
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test(
      'returns empty map when server responds with non-200 status (e.g. 500)',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.statusCodeByUrlPrefix['providerId=12345'] = 500;

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
          minInterval: Duration.zero,
        );

        final Map<String, FollowProgram> result = await checker
            .checkBroadcastStatus(<String>{'12345'});

        expect(result, isEmpty);

        checker.dispose();
      },
    );

    test(
      'retries once on 429 and succeeds if second attempt returns 200',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        // First call returns 429, subsequent calls return ON_AIR.
        httpClient.statusCodeByUrlPrefix['providerId=12345'] = 429;
        httpClient.retryAfterByUrlPrefix['providerId=12345'] = '1';
        httpClient.statusCodeByUrlPrefixOnRetry['providerId=12345'] =
            _buildHistoryResponse(
              programId: 'lv100001',
              status: 'ON_AIR',
              providerName: 'テスト',
            );

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
          minInterval: Duration.zero,
        );

        final Map<String, FollowProgram> result = await checker
            .checkBroadcastStatus(<String>{'12345'});

        expect(result, hasLength(1));
        expect(result['12345']!.programId, 'lv100001');
        // 2 requests: initial 429 + retry 200.
        expect(httpClient.requestCount, 2);

        checker.dispose();
      },
    );

    test('returns empty when 429 retry also fails', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // Both calls return 429 (no retry response override).
      httpClient.statusCodeByUrlPrefix['providerId=12345'] = 429;
      httpClient.retryAfterByUrlPrefix['providerId=12345'] = '1';

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);
      // 2 requests: initial 429 + retry 429.
      expect(httpClient.requestCount, 2);

      checker.dispose();
    });

    test('returns empty map when response is malformed JSON', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          'not valid json {{{';

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test('returns empty map when programId is missing from response', () async {
      final String body = jsonEncode(<String, dynamic>{
        'meta': <String, dynamic>{'status': 200},
        'data': <String, dynamic>{
          'programsList': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': <String, dynamic>{},
              'program': <String, dynamic>{
                'title': 'テスト',
                'schedule': <String, dynamic>{
                  'status': 'ON_AIR',
                  'beginTime': <String, dynamic>{'seconds': 1700000000},
                },
              },
              'programProvider': <String, dynamic>{'name': 'テスト'},
            },
          ],
        },
      });

      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] = body;

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result, isEmpty);

      checker.dispose();
    });

    test('returns cached result within minInterval', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(programId: 'lv100001', status: 'ON_AIR');

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: const Duration(seconds: 60),
      );

      // First call makes network request.
      final Map<String, FollowProgram> first = await checker
          .checkBroadcastStatus(<String>{'12345'});
      expect(first, hasLength(1));
      expect(httpClient.requestCount, 1);

      // Second call within minInterval returns cache.
      final Map<String, FollowProgram> second = await checker
          .checkBroadcastStatus(<String>{'12345'});
      expect(second, hasLength(1));
      expect(httpClient.requestCount, 1); // No new request.

      checker.dispose();
    });

    test('invalidateCache forces network request on next call', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(programId: 'lv100001', status: 'ON_AIR');

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: const Duration(seconds: 60),
      );

      await checker.checkBroadcastStatus(<String>{'12345'});
      expect(httpClient.requestCount, 1);

      checker.invalidateCache();

      await checker.checkBroadcastStatus(<String>{'12345'});
      expect(httpClient.requestCount, 2);

      checker.dispose();
    });

    test('throttles concurrent requests to maxConcurrentRequests', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      for (int i = 1; i <= 5; i++) {
        httpClient.responseBodyByUrlPrefix['providerId=$i'] =
            _buildHistoryResponse(programId: 'lv10000$i', status: 'ENDED');
      }

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        maxConcurrentRequests: 2,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'1', '2', '3', '4', '5'});

      expect(result, isEmpty);
      expect(httpClient.requestCount, 5);

      checker.dispose();
    });

    test(
      'on-air users are skipped on odd cycles and re-checked on even cycles',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient.responseBodyByUrlPrefix['providerId=111'] =
            _buildHistoryResponse(programId: 'lv100001', status: 'ON_AIR');
        httpClient.responseBodyByUrlPrefix['providerId=222'] =
            _buildHistoryResponse(programId: 'lv100002', status: 'ENDED');

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
          maxConcurrentRequests: 5,
          minInterval: Duration.zero,
        );

        // Cycle 1: both users checked.
        final Map<String, FollowProgram> first = await checker
            .checkBroadcastStatus(<String>{'111', '222'});
        expect(first, hasLength(1));
        expect(first['111']!.programId, 'lv100001');
        expect(httpClient.requestCount, 2);

        // Cycle 2 (even): user 111 is known on-air, re-checked.
        final Map<String, FollowProgram> second = await checker
            .checkBroadcastStatus(<String>{'111', '222'});
        expect(second, hasLength(1));
        expect(httpClient.requestCount, 4);

        // Cycle 3 (odd): user 111 is known on-air, skipped.
        httpClient.requestCount = 0;
        final Map<String, FollowProgram> third = await checker
            .checkBroadcastStatus(<String>{'111', '222'});
        expect(third, hasLength(1));
        expect(third['111']!.programId, 'lv100001');
        expect(httpClient.requestCount, 1); // Only user 222.

        checker.dispose();
      },
    );

    test('parses beginAt and endAt from schedule timestamps', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(
            programId: 'lv100001',
            status: 'ON_AIR',
            beginTimeSeconds: 1700000000,
            scheduledEndTimeSeconds: 1700001800,
          );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      final FollowProgram program = result['12345']!;
      expect(
        program.beginAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
      expect(
        program.endAt,
        DateTime.fromMillisecondsSinceEpoch(1700001800 * 1000, isUtc: true),
      );

      checker.dispose();
    });

    test('extracts provider icon URL from icons object', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] =
          _buildHistoryResponse(programId: 'lv100001', status: 'ON_AIR');

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result['12345']!.providerIconUrl, isNotNull);
      expect(result['12345']!.providerIconUrl, contains('https://'));

      checker.dispose();
    });

    test('excludes deleted community name', () async {
      final String body = jsonEncode(<String, dynamic>{
        'meta': <String, dynamic>{'status': 200},
        'data': <String, dynamic>{
          'programsList': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': <String, dynamic>{'value': 'lv100001'},
              'program': <String, dynamic>{
                'title': 'テスト',
                'schedule': <String, dynamic>{
                  'status': 'ON_AIR',
                  'beginTime': <String, dynamic>{'seconds': 1700000000},
                  'scheduledEndTime': <String, dynamic>{'seconds': 1700001800},
                },
              },
              'programProvider': <String, dynamic>{'name': 'テスト放送者'},
              'socialGroup': <String, dynamic>{
                'name': '削除されたコミュニティ',
                'isDeleted': <String, dynamic>{'value': true},
              },
            },
          ],
        },
      });

      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBodyByUrlPrefix['providerId=12345'] = body;

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: Duration.zero,
      );

      final Map<String, FollowProgram> result = await checker
          .checkBroadcastStatus(<String>{'12345'});

      expect(result['12345']!.communityName, isNull);

      checker.dispose();
    });
  });
}

// ---------------------------------------------------------------------------
// Fake HTTP infrastructure
// ---------------------------------------------------------------------------

class _FakeHttpClient implements HttpClient {
  /// Maps a URL substring (e.g. 'providerId=12345') to a JSON response body.
  final Map<String, String> responseBodyByUrlPrefix = <String, String>{};

  /// Maps a URL substring to a non-200 HTTP status code.
  final Map<String, int> statusCodeByUrlPrefix = <String, int>{};

  /// Maps a URL substring to the Retry-After header value for 429 responses.
  final Map<String, String> retryAfterByUrlPrefix = <String, String>{};

  /// Maps a URL substring to the response body to return on the retry attempt
  /// after a 429. If set, the second request for this prefix returns 200 with
  /// this body instead of the 429.
  final Map<String, String> statusCodeByUrlPrefixOnRetry = <String, String>{};

  /// Maps a URL substring to an exception to throw.
  final Map<String, Exception> throwOnUrlPrefix = <String, Exception>{};

  int requestCount = 0;

  /// Tracks how many times each URL prefix has been requested (for retry
  /// simulation).
  final Map<String, int> _hitCountByPrefix = <String, int>{};

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final String urlStr = url.toString();

    for (final MapEntry<String, Exception> entry in throwOnUrlPrefix.entries) {
      if (urlStr.contains(entry.key)) {
        throw entry.value;
      }
    }

    // Check for non-200 status code overrides.
    for (final MapEntry<String, int> entry in statusCodeByUrlPrefix.entries) {
      if (urlStr.contains(entry.key)) {
        final int hitCount = _hitCountByPrefix[entry.key] =
            (_hitCountByPrefix[entry.key] ?? 0) + 1;
        requestCount++;

        // On retry (second hit), return success body if configured.
        if (hitCount > 1 &&
            statusCodeByUrlPrefixOnRetry.containsKey(entry.key)) {
          return _FakeHttpClientRequest(
            uri: url,
            responseBody: statusCodeByUrlPrefixOnRetry[entry.key]!,
            statusCode: 200,
          );
        }

        final String? retryAfter = retryAfterByUrlPrefix[entry.key];
        return _FakeHttpClientRequest(
          uri: url,
          responseBody: '',
          statusCode: entry.value,
          retryAfterHeader: retryAfter,
        );
      }
    }

    String body = '{"meta":{"status":200},"data":{"programsList":[]}}';
    for (final MapEntry<String, String> entry
        in responseBodyByUrlPrefix.entries) {
      if (urlStr.contains(entry.key)) {
        body = entry.value;
        break;
      }
    }

    requestCount++;
    return _FakeHttpClientRequest(uri: url, responseBody: body);
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
    required this.responseBody,
    this.statusCode = 200,
    this.retryAfterHeader,
  });

  @override
  final Uri uri;
  final String responseBody;
  final int statusCode;
  final String? retryAfterHeader;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async {
    return _FakeHttpClientResponse(
      statusCode: statusCode,
      body: responseBody,
      retryAfterHeader: retryAfterHeader,
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
    required this.body,
    this.retryAfterHeader,
  });

  @override
  final int statusCode;
  final String body;
  final String? retryAfterHeader;

  @override
  late final HttpHeaders headers = _FakeResponseHeaders(
    retryAfter: retryAfterHeader,
  );

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
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

class _FakeResponseHeaders implements HttpHeaders {
  _FakeResponseHeaders({this.retryAfter});

  final String? retryAfter;

  @override
  String? value(String name) {
    if (name.toLowerCase() == 'retry-after') {
      return retryAfter;
    }
    return null;
  }

  @override
  List<String>? operator [](String name) {
    final String? v = value(name);
    return v != null ? <String>[v] : null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
