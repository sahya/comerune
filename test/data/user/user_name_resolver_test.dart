import 'dart:async';
import 'dart:convert';

import 'package:comerune/data/user/user_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_http_client.dart';

void main() {
  group('UserNameResolver', () {
    test('resolves numeric user ID to nickname', () async {
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
      final FakeHttpClient httpClient = FakeHttpClient();
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
