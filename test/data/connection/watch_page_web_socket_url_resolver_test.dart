@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/connection/watch_page_web_socket_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a watch page whose embedded data carries [props], HTML-escaped the
/// same way the real page escapes `data-props`.
String _watchPage(Map<String, Object?> props) {
  final String escaped = const HtmlEscape(
    HtmlEscapeMode.attribute,
  ).convert(jsonEncode(props));
  return '<html><head></head><body>'
      '<script id="embedded-data" data-props="$escaped"></script>'
      '</body></html>';
}

Map<String, Object?> _props({Object? webSocketUrl = _absent}) {
  final Map<String, Object?> relive = <String, Object?>{};
  if (!identical(webSocketUrl, _absent)) {
    relive['webSocketUrl'] = webSocketUrl;
  }
  return <String, Object?>{
    'site': <String, Object?>{'relive': relive},
  };
}

const Object _absent = Object();

void main() {
  group('parseWatchPageWebSocketUrl', () {
    test('returns the URL and adds frontend_id=9 when missing', () {
      final WatchPageWebSocketUrlResult result = parseWatchPageWebSocketUrl(
        _watchPage(
          _props(
            webSocketUrl:
                'wss://a.live2.nicovideo.jp/wsapi/v2/watch/lv1?audience_token=t',
          ),
        ),
      );

      expect(result.status, WatchPageWebSocketUrlStatus.resolved);
      expect(result.url!.host, 'a.live2.nicovideo.jp');
      expect(result.url!.queryParameters['audience_token'], 't');
      expect(result.url!.queryParameters['frontend_id'], '9');
    });

    test('decodes numeric HTML entities in data-props', () {
      final String page =
          '<script id="embedded-data" data-props="'
          '{&#34;site&#34;:{&#34;relive&#34;:{&#34;webSocketUrl&#34;:'
          '&#34;wss:&#x2F;&#x2F;a.live2.nicovideo.jp&#x2F;wsapi&#34;}}}'
          '"></script>';

      final WatchPageWebSocketUrlResult result = parseWatchPageWebSocketUrl(
        page,
      );

      expect(result.url!.host, 'a.live2.nicovideo.jp');
      expect(result.url!.path, '/wsapi');
    });

    test('keeps an existing frontend_id', () {
      final WatchPageWebSocketUrlResult result = parseWatchPageWebSocketUrl(
        _watchPage(
          _props(
            webSocketUrl:
                'wss://a.live2.nicovideo.jp/wsapi/v2/watch/lv1?frontend_id=12',
          ),
        ),
      );

      expect(result.url!.queryParameters['frontend_id'], '12');
    });

    test('reports notWatchable when webSocketUrl is empty or null (#654)', () {
      for (final Object? value in <Object?>['', null]) {
        expect(
          parseWatchPageWebSocketUrl(
            _watchPage(_props(webSocketUrl: value)),
          ).status,
          WatchPageWebSocketUrlStatus.notWatchable,
          reason: 'webSocketUrl: $value',
        );
      }
      expect(
        parseWatchPageWebSocketUrl(_watchPage(_props())).status,
        WatchPageWebSocketUrlStatus.notWatchable,
        reason: 'webSocketUrl key missing',
      );
    });

    final Map<String, String> unavailablePages = <String, String>{
      'no embedded-data tag': '<html><body>no data</body></html>',
      'empty data-props': '<script id="embedded-data" data-props=""></script>',
      'malformed JSON': '<script id="embedded-data" data-props="{"></script>',
      'site missing': _watchPage(<String, Object?>{}),
      'relive missing': _watchPage(<String, Object?>{
        'site': <String, Object?>{},
      }),
      'non-string webSocketUrl': _watchPage(_props(webSocketUrl: 42)),
      'URL without host': _watchPage(_props(webSocketUrl: 'not a url')),
      // The session cookie is sent to this URL, so it must be a secure
      // WebSocket on a niconico host.
      'non-wss scheme': _watchPage(
        _props(webSocketUrl: 'ws://a.live2.nicovideo.jp/wsapi/v2/watch/lv1'),
      ),
      'non-niconico host': _watchPage(
        _props(webSocketUrl: 'wss://example.com/wsapi/v2/watch/lv1'),
      ),
      'host that only ends with nicovideo.jp': _watchPage(
        _props(webSocketUrl: 'wss://evilnicovideo.jp/wsapi/v2/watch/lv1'),
      ),
    };
    for (final MapEntry<String, String> page in unavailablePages.entries) {
      test('reports unavailable when ${page.key}', () {
        expect(
          parseWatchPageWebSocketUrl(page.value).status,
          WatchPageWebSocketUrlStatus.unavailable,
        );
      });
    }
  });

  group('WatchPageWebSocketUrlResolver', () {
    late HttpServer server;
    late Uri baseUri;
    late FutureOr<void> Function(HttpRequest request) handler;
    final List<HttpHeaders> receivedHeaders = <HttpHeaders>[];
    final List<String> receivedPaths = <String>[];

    setUp(() async {
      receivedHeaders.clear();
      receivedPaths.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}/watch/');
      server.listen((HttpRequest request) async {
        receivedHeaders.add(request.headers);
        receivedPaths.add(request.uri.path);
        await handler(request);
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    WatchPageWebSocketUrlResolver buildResolver() {
      return WatchPageWebSocketUrlResolver(watchPageBaseUri: baseUri);
    }

    test('fetches the watch page with the session cookie and a desktop UA '
        'and returns the URL', () async {
      handler = (HttpRequest request) async {
        request.response
          ..headers.contentType = ContentType.html
          ..write(
            _watchPage(
              _props(webSocketUrl: 'wss://a.live2.nicovideo.jp/wsapi/v2/x'),
            ),
          );
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 'session-value',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.resolved);
      expect(receivedPaths, <String>['/watch/lv1']);
      expect(
        receivedHeaders.single.value('cookie'),
        'user_session=session-value',
      );
      expect(
        receivedHeaders.single.value('user-agent'),
        WatchPageWebSocketUrlResolver.desktopUserAgent,
      );
    });

    test('follows a redirect on the same host', () async {
      handler = (HttpRequest request) async {
        if (request.uri.path == '/watch/lv1') {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set('location', '/watch/moved/lv1');
        } else {
          request.response.write(
            _watchPage(
              _props(webSocketUrl: 'wss://a.live2.nicovideo.jp/wsapi/v2/x'),
            ),
          );
        }
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.resolved);
      expect(receivedHeaders, hasLength(2));
    });

    test('stops at a redirect to the mobile site', () async {
      handler = (HttpRequest request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', 'https://sp.live.nicovideo.jp/watch/lv1');
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
      expect(receivedHeaders, hasLength(1));
    });

    test('does not follow a redirect to another host, so the cookie stays '
        'on the watch page host', () async {
      handler = (HttpRequest request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', 'https://example.com/watch/lv1');
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
      expect(receivedHeaders, hasLength(1));
    });

    test(
      'does not follow a redirect to another host on the same scheme',
      () async {
        handler = (HttpRequest request) async {
          request.response
            ..statusCode = HttpStatus.found
            ..headers.set(
              'location',
              'http://localhost:${server.port}/watch/lv1',
            );
          await request.response.close();
        };

        final WatchPageWebSocketUrlResult result = await buildResolver()
            .resolve(lv: 'lv1', userSession: 's');

        expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
        expect(receivedHeaders, hasLength(1));
      },
    );

    test('gives up after too many redirects', () async {
      handler = (HttpRequest request) async {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('location', '/watch/loop/${receivedPaths.length}');
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
      expect(receivedHeaders, hasLength(6));
    });

    test('reports unavailable for a redirect without a location', () async {
      handler = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.found;
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
    });

    test('reports unavailable for a non-200 response', () async {
      handler = (HttpRequest request) async {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
    });

    test('reports notWatchable when the page has no WebSocket URL', () async {
      handler = (HttpRequest request) async {
        request.response.write(_watchPage(_props(webSocketUrl: '')));
        await request.response.close();
      };

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.notWatchable);
    });

    test('reports unavailable instead of throwing when the connection '
        'fails', () async {
      await server.close(force: true);

      final WatchPageWebSocketUrlResult result = await buildResolver().resolve(
        lv: 'lv1',
        userSession: 's',
      );

      expect(result.status, WatchPageWebSocketUrlStatus.unavailable);
    });
  });
}
