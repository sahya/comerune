import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/domain/connection/ws_endpoint_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsEndpointResolver', () {
    test('resolves WebSocket URL via userinfo and wsendpoint APIs', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responses[_userinfoUrl] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'sub': '12345',
          'nickname': 'testuser',
        }),
      );
      httpClient.responses[_wsEndpointUrlPattern] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200, 'errorCode': 'OK'},
          'data': <String, Object?>{
            'url':
                'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/11111?audience_token=abc',
          },
        }),
      );

      final WsEndpointResolver resolver = WsEndpointResolver(
        httpClient: httpClient,
      );

      final Uri result = await resolver.resolve(
        lv: 'lv350186414',
        accessToken: 'test-token',
      );

      expect(
        result.toString(),
        'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/11111?audience_token=abc',
      );

      expect(httpClient.requests, hasLength(2));

      final _CapturedRequest userinfoRequest = httpClient.requests[0];
      expect(
        userinfoRequest.uri.toString(),
        'https://oauth.nicovideo.jp/open_id/userinfo',
      );
      expect(userinfoRequest.headers['Authorization'], 'Bearer test-token');
      expect(userinfoRequest.headers['User-Agent'], isNotNull);

      final _CapturedRequest wsEndpointRequest = httpClient.requests[1];
      expect(
        wsEndpointRequest.uri.queryParameters['nicoliveProgramId'],
        'lv350186414',
      );
      expect(wsEndpointRequest.uri.queryParameters['userId'], '12345');
      expect(
        wsEndpointRequest.headers['Authorization'],
        'Bearer test-token',
      );

      resolver.dispose();
    });

    test('throws when userinfo API returns non-200', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responses[_userinfoUrl] = _FakeHttpResponse(
        statusCode: 401,
        body: 'Unauthorized',
      );

      final WsEndpointResolver resolver = WsEndpointResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', accessToken: 'bad-token'),
        throwsA(isA<WsEndpointResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when userinfo response is missing sub field', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responses[_userinfoUrl] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'nickname': 'testuser'}),
      );

      final WsEndpointResolver resolver = WsEndpointResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', accessToken: 'token'),
        throwsA(isA<WsEndpointResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when wsendpoint API returns non-200', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responses[_userinfoUrl] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'sub': '12345'}),
      );
      httpClient.responses[_wsEndpointUrlPattern] = _FakeHttpResponse(
        statusCode: 403,
        body: 'Forbidden',
      );

      final WsEndpointResolver resolver = WsEndpointResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', accessToken: 'token'),
        throwsA(isA<WsEndpointResolveException>()),
      );

      resolver.dispose();
    });

    test('throws when wsendpoint response has no data.url', () async {
      final _FakeHttpClient httpClient = _FakeHttpClient();
      httpClient.responses[_userinfoUrl] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{'sub': '12345'}),
      );
      httpClient.responses[_wsEndpointUrlPattern] = _FakeHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object?>{
          'meta': <String, Object?>{'status': 200},
          'data': <String, Object?>{},
        }),
      );

      final WsEndpointResolver resolver = WsEndpointResolver(
        httpClient: httpClient,
      );

      await expectLater(
        resolver.resolve(lv: 'lv123', accessToken: 'token'),
        throwsA(isA<WsEndpointResolveException>()),
      );

      resolver.dispose();
    });
  });

  group('WsEndpointResolveException', () {
    test('toString includes message', () {
      final WsEndpointResolveException exception =
          WsEndpointResolveException('test error');
      expect(exception.toString(), 'WsEndpointResolveException: test error');
    });
  });
}

const String _userinfoUrl = 'https://oauth.nicovideo.jp/open_id/userinfo';
const String _wsEndpointUrlPattern =
    'https://api.live2.nicovideo.jp/api/v1/wsendpoint';

class _CapturedRequest {
  _CapturedRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class _FakeHttpResponse {
  _FakeHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class _FakeHttpClient implements HttpClient {
  final Map<String, _FakeHttpResponse> responses =
      <String, _FakeHttpResponse>{};
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(
      uri: url,
      client: this,
    );
  }

  _FakeHttpResponse? findResponse(Uri uri) {
    final String urlStr = uri.toString();
    for (final MapEntry<String, _FakeHttpResponse> entry
        in responses.entries) {
      if (urlStr.startsWith(entry.key) || urlStr.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  set connectionTimeout(Duration? timeout) {}

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

    client.requests.add(
      _CapturedRequest(uri: uri, headers: headerMap),
    );

    final _FakeHttpResponse? fakeResponse = client.findResponse(uri);
    if (fakeResponse == null) {
      return _FakeHttpClientResponse(statusCode: 404, body: 'Not Found');
    }
    return _FakeHttpClientResponse(
      statusCode: fakeResponse.statusCode,
      body: fakeResponse.body,
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

  String? operator [](String name) {
    final List<String>? values = _values[name];
    return values != null && values.isNotEmpty ? values.first : null;
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
