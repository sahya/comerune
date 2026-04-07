import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/user/user_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserNameResolver', () {
    test('resolves numeric user ID to nickname', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'テストユーザー'},
      });

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('12345');
      // Wait for the async HTTP call to complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolver.getCachedName('12345'), 'テストユーザー');

      resolver.dispose();
    });

    test('ignores non-numeric user IDs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('abc123');
      resolver.requestResolve('hashed_user_id');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolver.getCachedName('abc123'), isNull);
      expect(resolver.getCachedName('hashed_user_id'), isNull);
      expect(httpClient.requests, isEmpty);

      resolver.dispose();
    });

    test('does not re-request already cached IDs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'UserA'},
      });

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('111');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(httpClient.requests, hasLength(1));

      resolver.requestResolve('111');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(httpClient.requests, hasLength(1));

      resolver.dispose();
    });

    test('does not re-request pending IDs', () async {
      final Completer<void> responseCompleter = Completer<void>();
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'Delayed'},
      });
      httpClient.responseDelay = responseCompleter.future;

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('222');
      // Allow the async getUrl call to proceed so the request is captured.
      await Future<void>.delayed(Duration.zero);
      final int requestsAfterFirst = httpClient.requests.length;

      resolver.requestResolve('222');
      await Future<void>.delayed(Duration.zero);
      // Second call should not add another request.
      expect(httpClient.requests.length, requestsAfterFirst);

      responseCompleter.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resolver.getCachedName('222'), 'Delayed');

      resolver.dispose();
    });

    test('handles non-200 gracefully', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseStatusCode = 404;
      httpClient.responseBody = 'Not Found';

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('999');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolver.getCachedName('999'), isNull);

      resolver.dispose();
    });

    test('clearCache removes all cached and pending data', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'CachedUser'},
      });

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      resolver.requestResolve('333');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resolver.getCachedName('333'), 'CachedUser');

      resolver.clearCache();
      expect(resolver.getCachedName('333'), isNull);

      resolver.dispose();
    });

    test('does not notifyListeners after dispose', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'Late'},
      });
      httpClient.responseDelay = Future<void>.delayed(
        const Duration(milliseconds: 100),
      );

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      int notifyCount = 0;
      resolver.addListener(() {
        notifyCount++;
      });

      resolver.requestResolve('444');
      // Dispose before the response arrives.
      resolver.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(notifyCount, 0);
    });

    test('limits concurrent requests', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      final Completer<void> gate = Completer<void>();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'User'},
      });
      httpClient.responseDelay = gate.future;

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      // Request 5 user IDs; only 3 should be in-flight initially.
      for (int i = 1; i <= 5; i++) {
        resolver.requestResolve('$i');
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));
      // 3 concurrent requests should have been made.
      expect(httpClient.requests.length, 3);

      // Release the gate; remaining 2 should then be processed.
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(httpClient.requests.length, 5);

      resolver.dispose();
    });

    test('notifies listeners with debounce', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'User'},
      });

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: const Duration(milliseconds: 100),
      );

      int notifyCount = 0;
      resolver.addListener(() {
        notifyCount++;
      });

      // Request 3 users rapidly; should coalesce into fewer notifications.
      resolver.requestResolve('10');
      resolver.requestResolve('20');
      resolver.requestResolve('30');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // All resolved but debounce timer not yet fired.
      expect(notifyCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      // After debounce, exactly one notification expected.
      expect(notifyCount, 1);

      resolver.dispose();
    });

    test('seedCache pre-populates name without HTTP request', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      int notifyCount = 0;
      resolver.addListener(() {
        notifyCount++;
      });

      resolver.seedCache('99999', 'プリセット名');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolver.getCachedName('99999'), 'プリセット名');
      expect(notifyCount, 1);
      // No HTTP requests should have been made.
      expect(httpClient.requests, isEmpty);

      resolver.dispose();
    });

    test('seedCache prevents subsequent requestResolve HTTP call', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responseBody = jsonEncode(<String, Object?>{
        'data': <String, Object?>{'nickname': 'HTTP名前'},
      });

      final UserNameResolver resolver = UserNameResolver(
        httpClient: httpClient,
        debounceDuration: Duration.zero,
      );

      // Pre-populate cache first.
      resolver.seedCache('77777', 'API名前');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // requestResolve should be a no-op since the name is already cached.
      resolver.requestResolve('77777');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolver.getCachedName('77777'), 'API名前');
      expect(httpClient.requests, isEmpty);

      resolver.dispose();
    });
  });
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  Future<void>? responseDelay;
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

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
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

    if (client.responseDelay != null) {
      await client.responseDelay;
    }

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
