// Shared in-memory fake of `dart:io`'s `HttpClient` family for tests
// that exercise data-layer code which talks HTTP via `HttpClient`
// directly (rather than the higher-level `package:http` Client).
//
// Issue #851 tracks the migration of nine call sites that used to
// declare bespoke `_FakeHttpClient` / `_FakeHttpClientRequest` /
// `_FakeHttpClientResponse` / `_FakeHttpHeaders` quartets inline.
// This helper consolidates the union of fields they relied on so a
// single configurable fake can replace the simple variants:
//
// - `responseBody` / `responseStatusCode`        (every variant)
// - `requests` capture with `method` + `body`    (most variants)
// - `responseDelay` and gated completers         (timeout coverage)
// - `shouldThrowOnRequest` SocketException       (network-error path)
// - `isAborted` per request                      (abort coverage)
//
// What this helper intentionally does NOT cover:
//
// - Per-URL routing tables / retry-after maps used by
//   `favorite_user_live_checker_test.dart` and
//   `broadcaster_embed_resolver_test.dart` — those need a different
//   shape (multi-endpoint dispatch) and stay bespoke until a separate
//   migration phase ports them.
// - Response header lookup beyond the simple value(name) read used by
//   the simple variants — Retry-After / chunked transfer / cookies
//   are not modelled here.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Snapshot of one outgoing request observed by [FakeHttpClient].
///
/// `method` defaults to `'GET'` because the simplest variants only
/// exercised `getUrl`; tests that drive POST/PUT can read it back
/// to assert dispatch. `body` is `null` when nothing was written
/// to the request body via `write` (typical for GET).
class CapturedHttpRequest {
  CapturedHttpRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.request,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;

  /// Reference to the underlying [FakeHttpClientRequest] so a test can
  /// later assert on `isAborted` or other per-request state without
  /// having to keep a separate handle.
  final FakeHttpClientRequest request;
}

/// Configurable in-memory `HttpClient` fake.
///
/// All fields are mutable so a single instance can be re-configured
/// across multiple `setUp` / `act` / `assert` cycles within one test
/// without re-instantiation.
class FakeHttpClient implements HttpClient {
  /// Body returned in the next [HttpClientResponse]. Mutate before
  /// each request to drive different scenarios.
  String responseBody = '';

  /// Status code of the next response.
  int responseStatusCode = 200;

  /// When set, every URL method (`getUrl` / `postUrl` / `putUrl`)
  /// throws a [SocketException] instead of returning a request — used
  /// to simulate network-level failures.
  bool shouldThrowOnRequest = false;

  /// When non-null, [HttpClientRequest.close] awaits this future before
  /// returning a response. Use a [Completer] to drive precise timing
  /// in tests (e.g. firing it after pumping a timer past a timeout).
  Future<void>? responseDelay;

  /// When set, [HttpClientRequest.close] awaits this completer before
  /// returning a response. Equivalent to [responseDelay] but lets the
  /// test control completion explicitly via [Completer.complete] rather
  /// than awaiting a fixed-duration future.
  Completer<void>? pendingCompleter;

  /// When set, the response body stream awaits this completer before
  /// emitting any bytes — used to simulate a stalled response body
  /// for body-read timeout coverage.
  Completer<void>? bodyStallCompleter;

  /// Append-only log of requests observed by this client. The order
  /// reflects the order in which [HttpClientRequest.close] resolved.
  final List<CapturedHttpRequest> requests = <CapturedHttpRequest>[];

  Future<HttpClientRequest> _open(Uri url, String method) async {
    if (shouldThrowOnRequest) {
      throw const SocketException('Simulated network error');
    }
    return FakeHttpClientRequest(uri: url, client: this, method: method);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _open(url, 'GET');

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _open(url, 'POST');

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _open(url, 'PUT');

  @override
  set connectionTimeout(Duration? timeout) {}

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// Captures headers + body written by the system-under-test and
/// produces a [FakeHttpClientResponse] when closed.
class FakeHttpClientRequest implements HttpClientRequest {
  FakeHttpClientRequest({
    required this.uri,
    required this.client,
    required this.method,
  });

  @override
  final Uri uri;

  final FakeHttpClient client;

  @override
  final String method;

  final FakeHttpHeaders _headers = FakeHttpHeaders();
  final StringBuffer _body = StringBuffer();

  bool isAborted = false;

  @override
  HttpHeaders get headers => _headers;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    isAborted = true;
  }

  @override
  void write(Object? obj) {
    _body.write(obj);
  }

  @override
  void writeln([Object? obj = '']) {
    _body.writeln(obj);
  }

  @override
  void add(List<int> data) {
    _body.write(utf8.decode(data));
  }

  @override
  Future<HttpClientResponse> close() async {
    final Map<String, String> headerSnapshot = <String, String>{};
    _headers._values.forEach((String key, List<String> values) {
      if (values.isNotEmpty) {
        headerSnapshot[key] = values.first;
      }
    });

    client.requests.add(
      CapturedHttpRequest(
        method: method,
        uri: uri,
        headers: headerSnapshot,
        request: this,
        body: _body.isNotEmpty ? _body.toString() : null,
      ),
    );

    final Future<void>? delay = client.responseDelay;
    if (delay != null) {
      await delay;
    }

    final Completer<void>? gate = client.pendingCompleter;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }

    return FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
      bodyStallCompleter: client.bodyStallCompleter,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// Minimal `HttpHeaders` for accumulating values via `set`/`add` and
/// reading them back via `[]`. Sufficient for asserting that a system-
/// under-test sent specific headers.
class FakeHttpHeaders implements HttpHeaders {
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
  String? value(String name) {
    final List<String>? values = _values[name];
    return (values == null || values.isEmpty) ? null : values.first;
  }

  @override
  List<String>? operator [](String name) => _values[name];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

/// Response stream emitting the configured body as a single UTF-8
/// chunk, optionally gated by [bodyStallCompleter] for body-read
/// timeout coverage.
class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse({
    required this.statusCode,
    required String body,
    this.bodyStallCompleter,
  }) : _body = body;

  @override
  final int statusCode;

  final String _body;
  final Completer<void>? bodyStallCompleter;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final Completer<void>? stall = bodyStallCompleter;
    if (stall != null && !stall.isCompleted) {
      final Stream<List<int>> delayed = stall.future
          .then<List<int>>((_) => utf8.encode(_body))
          .asStream();
      return delayed.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
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
