import 'dart:convert';
import 'dart:io';

import 'package:comerune/data/connection/watch_page_web_socket_url_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a watch-page HTML snippet whose embedded-data carries [wsUrl].
String _watchPageHtml(String wsUrl) {
  final String props = jsonEncode(<String, Object?>{
    'site': <String, Object?>{
      'relive': <String, Object?>{'webSocketUrl': wsUrl},
    },
  });
  final String escaped = props.replaceAll('"', '&quot;');
  return '<html><script id="embedded-data" data-props="$escaped"></script>'
      '</html>';
}

void main() {
  group('WatchPageWebSocketUrlResolver', () {
    late HttpServer server;
    late Future<void> Function(HttpRequest request) handler;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) => handler(request));
    });

    tearDown(() async {
      await server.close(force: true);
    });

    WatchPageWebSocketUrlResolver buildResolver({
      Duration fetchTimeout = WatchPageWebSocketUrlResolver.defaultFetchTimeout,
    }) {
      return WatchPageWebSocketUrlResolver(
        watchPageBaseUri: Uri.parse('http://127.0.0.1:${server.port}/watch/'),
        fetchTimeout: fetchTimeout,
      );
    }

    test('extracts webSocketUrl and adds frontend_id', () async {
      String? requestedPath;
      String? sentCookie;
      handler = (HttpRequest request) async {
        requestedPath = request.uri.path;
        sentCookie = request.headers.value('cookie');
        request.response
          ..statusCode = 200
          ..write(
            _watchPageHtml(
              'wss://a.live2.nicovideo.jp/wsapi/v2/watch/lv1?audience_token=t',
            ),
          );
        await request.response.close();
      };

      final Uri? result = await buildResolver().resolve('lv1', 'session-1');

      expect(requestedPath, '/watch/lv1');
      expect(sentCookie, 'user_session=session-1');
      expect(result, isNotNull);
      expect(result!.host, 'a.live2.nicovideo.jp');
      expect(result.queryParameters['audience_token'], 't');
      expect(result.queryParameters['frontend_id'], '9');
    });

    test('returns null when redirected to the sp. mobile site', () async {
      handler = (HttpRequest request) async {
        request.response
          ..statusCode = 302
          ..headers.set('location', 'http://sp.example.invalid/watch/lv1');
        await request.response.close();
      };

      expect(await buildResolver().resolve('lv1', 'session-1'), isNull);
    });

    test('returns null for a non-200 response', () async {
      handler = (HttpRequest request) async {
        request.response.statusCode = 500;
        await request.response.close();
      };

      expect(await buildResolver().resolve('lv1', 'session-1'), isNull);
    });

    test(
      'returns null when the body stalls (Issue #1029)',
      () async {
        handler = (HttpRequest request) async {
          request.response
            ..statusCode = 200
            ..bufferOutput = false
            ..write('<html>');
          await request.response.flush();
          // Never close: the body read would wait forever.
        };

        final Stopwatch stopwatch = Stopwatch()..start();
        final Uri? result = await buildResolver(
          fetchTimeout: const Duration(milliseconds: 300),
        ).resolve('lv1', 'session-1');

        expect(result, isNull);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );
  });
}
