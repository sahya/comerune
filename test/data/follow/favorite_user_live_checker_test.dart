import 'dart:async';
import 'dart:io';

import 'package:comerune/data/follow/favorite_user_live_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FavoriteUserLiveChecker', () {
    test(
      'returns programId when user is broadcasting (302 redirect)',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient
                .responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
            _FakeResponseConfig(
          statusCode: 302,
          headers: <String, String>{
            'location': 'https://live.nicovideo.jp/watch/lv348712105',
          },
        );

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
        );

        final Map<String, String> result = await checker.checkBroadcastStatus(
          <String>{'12345'},
        );

        expect(result, <String, String>{'12345': 'lv348712105'});

        checker.dispose();
      },
    );

    test('returns empty map when user is not broadcasting (200)', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(statusCode: 200);

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'12345'},
      );

      expect(result, isEmpty);

      checker.dispose();
    });

    test('returns empty map for empty user IDs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{},
      );

      expect(result, isEmpty);
      expect(httpClient.requests, isEmpty);

      checker.dispose();
    });

    test('handles mixed results for multiple users', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/111'] =
          _FakeResponseConfig(
        statusCode: 302,
        headers: <String, String>{
          'location': 'https://live.nicovideo.jp/watch/lv100001',
        },
      );
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/222'] =
          _FakeResponseConfig(statusCode: 200);
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/333'] =
          _FakeResponseConfig(
        statusCode: 301,
        headers: <String, String>{
          'location': 'https://live.nicovideo.jp/watch/lv100003',
        },
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'111', '222', '333'},
      );

      expect(result, <String, String>{'111': 'lv100001', '333': 'lv100003'});

      checker.dispose();
    });

    test('handles network error gracefully', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.throwOnUrl['https://live.nicovideo.jp/watch/user/999'] =
          const SocketException('Connection refused');

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'999'},
      );

      expect(result, isEmpty);

      checker.dispose();
    });

    test('ignores redirect with no lv number in location', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(
        statusCode: 302,
        headers: <String, String>{
          'location': 'https://live.nicovideo.jp/watch/somethingelse',
        },
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'12345'},
      );

      expect(result, isEmpty);

      checker.dispose();
    });

    test(
      'parses uppercase lv with trailing slash in redirect location',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient
                .responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
            _FakeResponseConfig(
          statusCode: 302,
          headers: <String, String>{
            'location': 'https://live.nicovideo.jp/watch/LV348712105/',
          },
        );

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
        );

        final Map<String, String> result = await checker.checkBroadcastStatus(
          <String>{'12345'},
        );

        expect(result, <String, String>{'12345': 'lv348712105'});

        checker.dispose();
      },
    );

    test('handles redirect with no location header', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(statusCode: 302);

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'12345'},
      );

      expect(result, isEmpty);

      checker.dispose();
    });

    test('supports all redirect status codes', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      for (final MapEntry<String, int> entry in <String, int>{
        '401': 303,
        '402': 307,
        '403': 308,
      }.entries) {
        httpClient.responsesByUrl[
                'https://live.nicovideo.jp/watch/user/${entry.key}'] =
            _FakeResponseConfig(
          statusCode: entry.value,
          headers: <String, String>{
            'location': 'https://live.nicovideo.jp/watch/lv${entry.key}000',
          },
        );
      }

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'401', '402', '403'},
      );

      expect(result, <String, String>{
        '401': 'lv401000',
        '402': 'lv402000',
        '403': 'lv403000',
      });

      checker.dispose();
    });

    test('sets followRedirects to false on request', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(statusCode: 200);

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
      );

      await checker.checkBroadcastStatus(<String>{'12345'});

      expect(httpClient.requests, hasLength(1));
      expect(httpClient.requests[0].followRedirects, isFalse);

      checker.dispose();
    });

    test('returns cached result within minInterval', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(
        statusCode: 302,
        headers: <String, String>{
          'location': 'https://live.nicovideo.jp/watch/lv100001',
        },
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: const Duration(seconds: 60),
      );

      // First call makes network requests.
      final Map<String, String> first = await checker.checkBroadcastStatus(
        <String>{'12345'},
      );
      expect(first, <String, String>{'12345': 'lv100001'});
      expect(httpClient.requests, hasLength(1));

      // Second call within minInterval returns cache without new requests.
      final Map<String, String> second = await checker.checkBroadcastStatus(
        <String>{'12345'},
      );
      expect(second, <String, String>{'12345': 'lv100001'});
      expect(httpClient.requests, hasLength(1)); // No new request.

      checker.dispose();
    });

    test('invalidateCache forces network request on next call', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responsesByUrl['https://live.nicovideo.jp/watch/user/12345'] =
          _FakeResponseConfig(
        statusCode: 302,
        headers: <String, String>{
          'location': 'https://live.nicovideo.jp/watch/lv100001',
        },
      );

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        minInterval: const Duration(seconds: 60),
      );

      await checker.checkBroadcastStatus(<String>{'12345'});
      expect(httpClient.requests, hasLength(1));

      checker.invalidateCache();

      await checker.checkBroadcastStatus(<String>{'12345'});
      expect(httpClient.requests, hasLength(2)); // New request after invalidation.

      checker.dispose();
    });

    test('throttles concurrent requests to maxConcurrentRequests', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      // Set up 5 users, all not broadcasting (200).
      for (int i = 1; i <= 5; i++) {
        httpClient.responsesByUrl[
                'https://live.nicovideo.jp/watch/user/$i'] =
            _FakeResponseConfig(statusCode: 200);
      }

      final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
        httpClient: httpClient,
        maxConcurrentRequests: 2,
        minInterval: Duration.zero,
      );

      final Map<String, String> result = await checker.checkBroadcastStatus(
        <String>{'1', '2', '3', '4', '5'},
      );

      // All 5 users checked, none broadcasting.
      expect(result, isEmpty);
      expect(httpClient.requests, hasLength(5));

      checker.dispose();
    });

    test(
      'on-air users are skipped on odd cycles and re-checked on even cycles',
      () async {
        final _FakeHttpClient httpClient = _FakeHttpClient();
        httpClient
                .responsesByUrl['https://live.nicovideo.jp/watch/user/111'] =
            _FakeResponseConfig(
          statusCode: 302,
          headers: <String, String>{
            'location': 'https://live.nicovideo.jp/watch/lv100001',
          },
        );
        httpClient
                .responsesByUrl['https://live.nicovideo.jp/watch/user/222'] =
            _FakeResponseConfig(statusCode: 200);

        final FavoriteUserLiveChecker checker = FavoriteUserLiveChecker(
          httpClient: httpClient,
          maxConcurrentRequests: 5,
          minInterval: Duration.zero,
        );

        // Cycle 1: both users checked (2 requests).
        final Map<String, String> first = await checker.checkBroadcastStatus(
          <String>{'111', '222'},
        );
        expect(first, <String, String>{'111': 'lv100001'});
        expect(httpClient.requests, hasLength(2));

        // Cycle 2 (even): user 111 is known on-air, re-checked.
        final Map<String, String> second = await checker.checkBroadcastStatus(
          <String>{'111', '222'},
        );
        expect(second, <String, String>{'111': 'lv100001'});
        expect(httpClient.requests, hasLength(4)); // 2 more

        // Cycle 3 (odd): user 111 is known on-air, skipped.
        httpClient.requests.clear();
        final Map<String, String> third = await checker.checkBroadcastStatus(
          <String>{'111', '222'},
        );
        // user 111 retains cached status even though not checked.
        expect(third, <String, String>{'111': 'lv100001'});
        // Only user 222 was checked this cycle.
        expect(httpClient.requests, hasLength(1));

        checker.dispose();
      },
    );
  });
}

class _FakeResponseConfig {
  _FakeResponseConfig({
    required this.statusCode,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Map<String, String> headers;
}

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.followRedirects});

  final Uri uri;
  final bool followRedirects;
}

class _FakeHttpClient implements HttpClient {
  final Map<String, _FakeResponseConfig> responsesByUrl =
      <String, _FakeResponseConfig>{};
  final Map<String, Exception> throwOnUrl = <String, Exception>{};
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final String urlStr = url.toString();
    if (throwOnUrl.containsKey(urlStr)) {
      throw throwOnUrl[urlStr]!;
    }
    final _FakeResponseConfig config =
        responsesByUrl[urlStr] ?? _FakeResponseConfig(statusCode: 200);
    return _FakeHttpClientRequest(uri: url, client: this, config: config);
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
    required this.config,
  });

  @override
  final Uri uri;
  final _FakeHttpClient client;
  final _FakeResponseConfig config;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();

  bool _followRedirects = true;

  @override
  HttpHeaders get headers => _headers;

  @override
  set followRedirects(bool value) {
    _followRedirects = value;
  }

  @override
  bool get followRedirects => _followRedirects;

  @override
  Future<HttpClientResponse> close() async {
    client.requests.add(
      _CapturedRequest(uri: uri, followRedirects: _followRedirects),
    );

    return _FakeHttpClientResponse(
      statusCode: config.statusCode,
      responseHeaders: config.headers,
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
    required Map<String, String> responseHeaders,
  }) : headers = _FakeResponseHeaders(responseHeaders);

  @override
  final int statusCode;

  @override
  final HttpHeaders headers;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(<int>[]).listen(
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
  _FakeResponseHeaders(this._values);

  final Map<String, String> _values;

  @override
  String? value(String name) {
    return _values[name.toLowerCase()] ?? _values[name];
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
