import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/niconico/broadcaster_embed_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractBroadcasterEmbedInfoFromHtml', () {
    test('extracts numeric provider user ID and name from supplier', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': '1390632',
              'name': 'テスト放送者',
            },
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.userId, '1390632');
      expect(info.name, 'テスト放送者');
    });

    test('accepts integer programProviderId', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': 42,
              'name': '配信者',
            },
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.userId, '42');
      expect(info.name, '配信者');
    });

    test('falls back to programProvider when supplier is absent', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'programProvider': <String, Object?>{
              'programProviderId': '777',
              'name': 'プロバイダー',
            },
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.userId, '777');
      expect(info.name, 'プロバイダー');
    });

    test('rejects channel ID (non-numeric supplier ID)', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': 'ch2648853',
              'name': 'ニコニコ実況',
            },
          },
        }),
      );
      expect(info, isNull);
    });

    test('rejects community ID (co0)', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{'programProviderId': 'co0'},
          },
        }),
      );
      expect(info, isNull);
    });

    test('rejects zero / negative IDs', () {
      expect(
        extractBroadcasterEmbedInfoFromHtml(
          _wrapEmbedded(<String, Object?>{
            'program': <String, Object?>{
              'supplier': <String, Object?>{'programProviderId': 0},
            },
          }),
        ),
        isNull,
      );
      expect(
        extractBroadcasterEmbedInfoFromHtml(
          _wrapEmbedded(<String, Object?>{
            'program': <String, Object?>{
              'supplier': <String, Object?>{'programProviderId': -5},
            },
          }),
        ),
        isNull,
      );
    });

    test('returns userId only when name field is missing', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{'programProviderId': '999'},
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.userId, '999');
      expect(info.name, isNull);
    });

    test('treats empty name as null', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': '999',
              'name': '',
            },
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.name, isNull);
    });

    test('returns null when embedded-data tag is missing', () {
      const String html = '<html><body><h1>Live</h1></body></html>';
      expect(extractBroadcasterEmbedInfoFromHtml(html), isNull);
    });

    test('returns null when embedded-data is empty', () {
      const String html = '<script id="embedded-data" data-props=""></script>';
      expect(extractBroadcasterEmbedInfoFromHtml(html), isNull);
    });

    test('returns null when JSON is malformed', () {
      const String html =
          '<script id="embedded-data" data-props="{not json}"></script>';
      expect(extractBroadcasterEmbedInfoFromHtml(html), isNull);
    });

    test('returns null when program key is missing', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{'site': 'live'}),
      );
      expect(info, isNull);
    });

    test('handles ampersand in display name (HTML entity round-trip)', () {
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': '1',
              'name': 'A & B',
            },
          },
        }),
      );
      expect(info, isNotNull);
      expect(info!.name, 'A & B');
    });

    test('survives extra whitespace and attribute order in script tag', () {
      const String json =
          '{"program":{"supplier":{"programProviderId":'
          '"123","name":"X"}}}';
      final String escaped = _attributeEscape(json);
      final String html =
          '<script   class="x"   id="embedded-data"  data-props="$escaped" '
          'type="application/json"></script>';
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        html,
      );
      expect(info, isNotNull);
      expect(info!.userId, '123');
    });

    test('handles numeric character reference quotes (&#34;)', () {
      // Some renderers emit numeric refs instead of named ones. Verify we
      // still decode correctly.
      const String html =
          '<script id="embedded-data" data-props="{&#34;program&#34;:'
          '{&#34;supplier&#34;:{&#34;programProviderId&#34;:&#34;55&#34;,'
          '&#34;name&#34;:&#34;n55&#34;}}}"></script>';
      final BroadcasterEmbedInfo? info = extractBroadcasterEmbedInfoFromHtml(
        html,
      );
      expect(info, isNotNull);
      expect(info!.userId, '55');
      expect(info.name, 'n55');
    });
  });

  group('BroadcasterEmbedResolver.resolve', () {
    test('rejects malformed lv without making an HTTP request', () async {
      final _FakeHttpClient client = _FakeHttpClient();
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      expect(await resolver.resolve(''), isNull);
      expect(await resolver.resolve('lv'), isNull);
      expect(await resolver.resolve('lv12abc'), isNull);
      expect(await resolver.resolve('lv-1'), isNull);
      expect(await resolver.resolve('co12345'), isNull);
      expect(client.requests, isEmpty);
      resolver.dispose();
    });

    test('returns parsed info for valid lv with valid embedded-data', () async {
      final _FakeHttpClient client = _FakeHttpClient();
      client.responseBody = _wrapEmbedded(<String, Object?>{
        'program': <String, Object?>{
          'supplier': <String, Object?>{
            'programProviderId': '12345',
            'name': '配信者X',
          },
        },
      });
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      final BroadcasterEmbedInfo? info = await resolver.resolve('lv999');
      expect(info, isNotNull);
      expect(info!.userId, '12345');
      expect(info.name, '配信者X');
      // User-Agent header should be set so niconico does not block us.
      expect(client.requests.single.headers['User-Agent'], isNotNull);
      // URL must point at the watch endpoint with the lv appended.
      expect(
        client.requests.single.uri.toString(),
        'https://live.nicovideo.jp/watch/lv999',
      );
      resolver.dispose();
    });

    test('returns null for HTTP non-200 responses', () async {
      final _FakeHttpClient client = _FakeHttpClient();
      client.responseStatusCode = 404;
      client.responseBody = '<html>not found</html>';
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      expect(await resolver.resolve('lv1'), isNull);
      resolver.dispose();
    });

    test('returns null when the response has no embedded-data tag', () async {
      final _FakeHttpClient client = _FakeHttpClient();
      client.responseBody = '<html><body>no script here</body></html>';
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      expect(await resolver.resolve('lv2'), isNull);
      resolver.dispose();
    });

    test('returns null on network exception', () async {
      final _FakeHttpClient client = _FakeHttpClient()
        ..throwOnGetUrl = const SocketException('host unreachable');
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      expect(await resolver.resolve('lv3'), isNull);
      resolver.dispose();
    });

    test('returns null after dispose without crashing', () async {
      final _FakeHttpClient client = _FakeHttpClient();
      client.responseBody = _wrapEmbedded(<String, Object?>{
        'program': <String, Object?>{
          'supplier': <String, Object?>{'programProviderId': '1'},
        },
      });
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
      );
      resolver.dispose();
      expect(await resolver.resolve('lv4'), isNull);
    });

    test(
      'returns null when the request body trickles past the request timeout',
      () async {
        // Server starts responding (so getUrl/close succeed) but never
        // emits the document tail. Without a body-read timeout the resolve
        // would hang indefinitely; with one it returns null.
        final _FakeHttpClient client = _FakeHttpClient();
        client.responseStreamMode = _StreamMode.hangAfterFirstChunk;
        client.responseBody = '<html><head>';
        final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
          httpClient: client,
          requestTimeout: const Duration(milliseconds: 100),
        );
        expect(await resolver.resolve('lv5'), isNull);
        // The timeout must have triggered abort on the in-flight request.
        expect(client.requests.single.aborted, isTrue);
        resolver.dispose();
      },
    );

    test('returns null when disposed mid-resolve', () async {
      // Server starts streaming but never finishes; we dispose during
      // the body read and confirm resolve() unwinds to null without
      // throwing or returning a partially-parsed BroadcasterEmbedInfo.
      final _FakeHttpClient client = _FakeHttpClient();
      client.responseStreamMode = _StreamMode.hangAfterFirstChunk;
      client.responseBody = '<html><head>';
      final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
        httpClient: client,
        // Long enough that the timeout never fires — only dispose ends it.
        requestTimeout: const Duration(seconds: 30),
      );
      final Future<BroadcasterEmbedInfo?> pending = resolver.resolve('lv7');
      // Allow the stream to emit its first (incomplete) chunk.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      resolver.dispose();
      // dispose closes the HttpClient with force: true, which wakes the
      // body-read stream subscription with an error; resolve catches the
      // error in its outer try/catch and returns null.
      expect(await pending, isNull);
    });

    test(
      'truncates the body at the size cap but still parses prefix matches',
      () async {
        final _FakeHttpClient client = _FakeHttpClient();
        // Place a valid embedded-data tag near the start of the response,
        // followed by a payload large enough to trip the 2 MiB cap.
        final String prefix = _wrapEmbedded(<String, Object?>{
          'program': <String, Object?>{
            'supplier': <String, Object?>{
              'programProviderId': '88888',
              'name': 'cap-prefix',
            },
          },
        });
        client.responseBody = prefix + ('A' * (2 * 1024 * 1024 + 16));
        final BroadcasterEmbedResolver resolver = BroadcasterEmbedResolver(
          httpClient: client,
        );
        final BroadcasterEmbedInfo? info = await resolver.resolve('lv6');
        expect(info, isNotNull);
        expect(info!.userId, '88888');
        resolver.dispose();
      },
    );
  });
}

String _wrapEmbedded(Map<String, Object?> data) {
  final String escaped = _attributeEscape(jsonEncode(data));
  return '<!DOCTYPE html><html><head>'
      '<script id="embedded-data" data-props="$escaped"></script>'
      '</head><body></body></html>';
}

String _attributeEscape(String json) {
  // Mirror what niconico's renderer produces in the data-props attribute.
  return json
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

enum _StreamMode {
  /// Emit the entire body as a single chunk, then close the stream.
  immediate,

  /// Emit one chunk, then never emit `done` so the consumer waits forever.
  hangAfterFirstChunk,
}

class _FakeHttpClient implements HttpClient {
  String responseBody = '';
  int responseStatusCode = 200;
  Object? throwOnGetUrl;
  _StreamMode responseStreamMode = _StreamMode.immediate;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];
  final List<_FakeHttpClientRequest> _liveRequests = <_FakeHttpClientRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (throwOnGetUrl != null) {
      throw throwOnGetUrl!;
    }
    final _FakeHttpClientRequest req = _FakeHttpClientRequest(
      uri: url,
      client: this,
    );
    _liveRequests.add(req);
    return req;
  }

  @override
  set connectionTimeout(Duration? timeout) {}

  @override
  void close({bool force = false}) {
    if (!force) {
      return;
    }
    // Mirror HttpClient.close(force: true): sever every in-flight request
    // so the resolver's outer try/catch can unwind to null.
    for (final _FakeHttpClientRequest req in _liveRequests) {
      req.abort();
    }
    _liveRequests.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
  bool aborted = false;
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.uri, required this.client});

  @override
  final Uri uri;
  final _FakeHttpClient client;
  final _FakeHttpHeaders _headers = _FakeHttpHeaders();
  _CapturedRequest? _captured;
  _FakeHttpClientResponse? _response;

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
    final _CapturedRequest captured = _CapturedRequest(
      uri: uri,
      headers: headerMap,
    );
    _captured = captured;
    client.requests.add(captured);
    final _FakeHttpClientResponse response = _FakeHttpClientResponse(
      statusCode: client.responseStatusCode,
      body: client.responseBody,
      streamMode: client.responseStreamMode,
    );
    _response = response;
    return response;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _captured?.aborted = true;
    _response?.abort(exception, stackTrace);
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
    required String body,
    required _StreamMode streamMode,
  }) : _body = body,
       _streamMode = streamMode;

  @override
  final int statusCode;
  final String _body;
  final _StreamMode _streamMode;
  final StreamController<List<int>> _abortController =
      StreamController<List<int>>();

  void abort(Object? exception, StackTrace? stackTrace) {
    if (!_abortController.isClosed) {
      _abortController.addError(
        exception ?? const HttpException('aborted'),
        stackTrace,
      );
      unawaited(_abortController.close());
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final List<int> bytes = utf8.encode(_body);
    switch (_streamMode) {
      case _StreamMode.immediate:
        return Stream<List<int>>.value(bytes).listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
      case _StreamMode.hangAfterFirstChunk:
        // Emit one chunk, then never close — but propagate abort errors
        // so the resolver wakes up when its outer timeout fires.
        final StreamController<List<int>> ctrl = StreamController<List<int>>();
        ctrl.add(bytes);
        _abortController.stream.listen(
          (_) {},
          onError: ctrl.addError,
          onDone: ctrl.close,
        );
        return ctrl.stream.listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
    }
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
