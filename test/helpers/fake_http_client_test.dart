// Smoke tests for the shared `FakeHttpClient` helper introduced in
// PR #898 (Issue #851 Phase 1).
//
// Purpose: catch regressions in the helper itself so a failure during
// later phase migrations can be diagnosed as "fake bug vs SUT bug"
// without bisecting nine call sites. Coverage focuses on the four
// non-trivial behaviours that callers actually rely on:
//
// - `responseDelay` blocks the response future until the delay fires.
// - `pendingCompleter` blocks the response future until completed.
// - `shouldThrowOnRequest` rejects every URL method with a
//   [SocketException].
// - `bodyStallCompleter` blocks the response body stream.
//
// Trivial pass-throughs (`responseBody` / `responseStatusCode` /
// `requests` capture / per-request `isAborted`) are exercised by the
// migrated suites and not duplicated here.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_client.dart';

void main() {
  group('FakeHttpClient', () {
    test('responseDelay blocks the response future until the delay fires', () {
      fakeAsync((FakeAsync async) {
        final FakeHttpClient client = FakeHttpClient()
          ..responseBody = '{"ok":true}'
          ..responseDelay = Future<void>.delayed(const Duration(seconds: 1));

        bool resolved = false;
        client.getUrl(Uri.parse('https://example/test')).then((
          HttpClientRequest req,
        ) async {
          await req.close();
          resolved = true;
        });

        async.elapse(const Duration(milliseconds: 500));
        expect(
          resolved,
          isFalse,
          reason: 'response should still be blocked while delay is pending',
        );

        async.elapse(const Duration(seconds: 1));
        expect(resolved, isTrue, reason: 'response should resolve after delay');
        expect(client.requests, hasLength(1));
        expect(client.requests.single.method, 'GET');
      });
    });

    test('pendingCompleter blocks the response until completed', () async {
      final FakeHttpClient client = FakeHttpClient()
        ..responseBody = '{"ok":true}'
        ..pendingCompleter = Completer<void>();

      final Future<HttpClientResponse> pending = client
          .postUrl(Uri.parse('https://example/post'))
          .then((HttpClientRequest req) => req.close());

      // Yield once so close() has a chance to register on the gate.
      await Future<void>.delayed(Duration.zero);
      expect(
        client.requests,
        hasLength(1),
        reason: 'request should be captured even while gated',
      );

      bool done = false;
      // ignore: unawaited_futures
      pending.then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'gate should still hold the response');

      client.pendingCompleter!.complete();
      final HttpClientResponse response = await pending;
      expect(response.statusCode, 200);
    });

    test(
      'shouldThrowOnRequest rejects all URL methods with SocketException',
      () async {
        final FakeHttpClient client = FakeHttpClient()
          ..shouldThrowOnRequest = true;

        await expectLater(
          client.getUrl(Uri.parse('https://example/g')),
          throwsA(isA<SocketException>()),
        );
        await expectLater(
          client.postUrl(Uri.parse('https://example/p')),
          throwsA(isA<SocketException>()),
        );
        await expectLater(
          client.putUrl(Uri.parse('https://example/u')),
          throwsA(isA<SocketException>()),
        );
        expect(
          client.requests,
          isEmpty,
          reason: 'failed dispatches must not be captured',
        );
      },
    );

    test(
      'bodyStallCompleter holds the response body stream until completed',
      () async {
        final FakeHttpClient client = FakeHttpClient()
          ..responseBody = '{"data":42}'
          ..bodyStallCompleter = Completer<void>();

        final HttpClientRequest req = await client.getUrl(
          Uri.parse('https://example/stall'),
        );
        final HttpClientResponse response = await req.close();

        bool gotBody = false;
        // ignore: unawaited_futures
        response
            .transform(utf8.decoder)
            .join()
            .then((String _) => gotBody = true);

        // The response itself resolved synchronously, but the body
        // stream is still parked behind the stall completer.
        await Future<void>.delayed(Duration.zero);
        expect(gotBody, isFalse);

        client.bodyStallCompleter!.complete();
        final String body = await response.transform(utf8.decoder).join();
        expect(body, '{"data":42}');
      },
    );

    test('responseDelay and pendingCompleter compose serially '
        '(delay first, then completer)', () async {
      final Completer<void> delay = Completer<void>();
      final Completer<void> gate = Completer<void>();
      final FakeHttpClient client = FakeHttpClient()
        ..responseBody = 'ok'
        ..responseDelay = delay.future
        ..pendingCompleter = gate;

      final Future<HttpClientResponse> pending = client
          .getUrl(Uri.parse('https://example/serial'))
          .then((HttpClientRequest req) => req.close());

      // Completing the gate first should NOT release the response —
      // delay must fire first.
      gate.complete();
      bool done = false;
      // ignore: unawaited_futures
      pending.then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'delay still pending');

      delay.complete();
      await pending;
      // Reaching here without timeout is the assertion.
    });
  });
}
