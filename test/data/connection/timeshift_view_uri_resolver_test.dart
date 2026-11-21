import 'dart:async';
import 'dart:convert';

import 'package:comerune/data/connection/timeshift_view_uri_resolver.dart';
import 'package:comerune/data/connection/watch_page_web_socket_url_resolver.dart';
import 'package:comerune/domain/connection/session_ws_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_session_ws_channel.dart';

class _StubWatchPageResolver extends WatchPageWebSocketUrlResolver {
  _StubWatchPageResolver(this.result);

  final WatchPageWebSocketUrlResult result;
  int calls = 0;

  @override
  Future<WatchPageWebSocketUrlResult> resolve({
    required String lv,
    required String userSession,
  }) async {
    calls += 1;
    return result;
  }
}

final Uri _wsUrl = Uri.parse(
  'wss://a.live2.nicovideo.jp/wsapi/v2/watch/lv1?audience_token=t',
);
const String _viewUri = 'https://mpn.live.nicovideo.jp/api/view/v4/BBzJ?_=1';
// Real time: the resolver closes the WebSocket through
// `SessionWsClient.disconnect()`, whose `StreamSubscription.cancel` does
// not advance under fake_async (the same known incompatibility noted in
// session_ws_client_test.dart). Only the timeout cases use a short timeout;
// the others get a generous one so a busy CI cannot turn them into
// timeouts.
const Duration _timeout = Duration(seconds: 5);
const Duration _shortTimeout = Duration(milliseconds: 100);

String _messageServer(String viewUri) => jsonEncode(<String, Object?>{
  'type': 'messageServer',
  'data': <String, Object?>{
    'viewUri': viewUri,
    'vposBaseTime': '2025-01-01T00:00:00+09:00',
  },
});

void main() {
  group('TimeshiftViewUriResolver', () {
    late FakeSessionWsChannel channel;
    Uri? connectedUri;
    Map<String, String>? connectedHeaders;

    setUp(() {
      channel = FakeSessionWsChannel();
      connectedUri = null;
      connectedHeaders = null;
    });

    TimeshiftViewUriResolver buildResolver(
      WatchPageWebSocketUrlResult page, {
      SessionWsChannelFactory? channelFactory,
      Duration endpointTimeout = _timeout,
    }) {
      return TimeshiftViewUriResolver(
        watchPageResolver: _StubWatchPageResolver(page),
        channelFactory:
            channelFactory ??
            (Uri uri, Map<String, String> headers) async {
              connectedUri = uri;
              connectedHeaders = headers;
              return channel;
            },
        endpointTimeout: endpointTimeout,
      );
    }

    Future<TimeshiftViewUriResult> start(TimeshiftViewUriResolver resolver) {
      return resolver.resolve(lv: 'lv1', userSession: 'session-value');
    }

    test('returns the view URI from messageServer and closes the WebSocket '
        '(#654)', () async {
      final Future<TimeshiftViewUriResult> pending = start(
        buildResolver(WatchPageWebSocketUrlResult.resolved(_wsUrl)),
      );
      await Future<void>.delayed(Duration.zero);

      // startWatching is sent with empty data (no video stream requested).
      final Map<String, dynamic> startWatching =
          jsonDecode(channel.sentMessages.first as String)
              as Map<String, dynamic>;
      expect(startWatching['type'], 'startWatching');
      expect(startWatching['data'], <String, dynamic>{});

      channel.pushIncoming(_messageServer(_viewUri));
      final TimeshiftViewUriResult result = await pending;

      expect(result.failure, isNull);
      expect(result.viewUri, Uri.parse(_viewUri));
      expect(connectedUri, _wsUrl);
      expect(connectedHeaders!['Cookie'], 'user_session=session-value');
      expect(channel.closeCount, greaterThanOrEqualTo(1));
    });

    test('fails with notLoggedIn without fetching the watch page', () async {
      final _StubWatchPageResolver page = _StubWatchPageResolver(
        WatchPageWebSocketUrlResult.resolved(_wsUrl),
      );

      final TimeshiftViewUriResult result = await TimeshiftViewUriResolver(
        watchPageResolver: page,
      ).resolve(lv: 'lv1', userSession: '');

      expect(result.failure, TimeshiftViewUriFailure.notLoggedIn);
      expect(page.calls, 0);
    });

    test('fails with notWatchable when the watch page has no WebSocket URL '
        'and never connects', () async {
      final TimeshiftViewUriResult result = await start(
        buildResolver(const WatchPageWebSocketUrlResult.notWatchable()),
      );

      expect(result.failure, TimeshiftViewUriFailure.notWatchable);
      expect(connectedUri, isNull);
    });

    test('fails with watchPageUnavailable when the watch page cannot be '
        'read', () async {
      final TimeshiftViewUriResult result = await start(
        buildResolver(const WatchPageWebSocketUrlResult.unavailable()),
      );

      expect(result.failure, TimeshiftViewUriFailure.watchPageUnavailable);
      expect(connectedUri, isNull);
    });

    test('fails with sessionFailed when the WebSocket closes before '
        'messageServer', () async {
      final Future<TimeshiftViewUriResult> pending = start(
        buildResolver(WatchPageWebSocketUrlResult.resolved(_wsUrl)),
      );
      await Future<void>.delayed(Duration.zero);

      await channel.close();

      expect((await pending).failure, TimeshiftViewUriFailure.sessionFailed);
    });

    test(
      'fails with sessionFailed when only a legacy endpoint arrives',
      () async {
        final Future<TimeshiftViewUriResult> pending = start(
          buildResolver(
            WatchPageWebSocketUrlResult.resolved(_wsUrl),
            endpointTimeout: _timeout,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        channel.pushIncoming(
          jsonEncode(<String, Object?>{
            'type': 'room',
            'data': <String, Object?>{
              'messageServer': <String, Object?>{
                'uri': 'wss://msgd.live2.nicovideo.jp/websocket?thread=1',
              },
            },
          }),
        );

        expect((await pending).failure, TimeshiftViewUriFailure.sessionFailed);
      },
    );

    test('fails with timedOut when no endpoint arrives in time', () async {
      final TimeshiftViewUriResult result = await start(
        buildResolver(
          WatchPageWebSocketUrlResult.resolved(_wsUrl),
          endpointTimeout: _shortTimeout,
        ),
      );

      expect(result.failure, TimeshiftViewUriFailure.timedOut);
      expect(channel.closeCount, greaterThanOrEqualTo(1));
    });

    test('fails with timedOut when the WebSocket handshake stalls, and closes '
        'a connection that completes later', () async {
      final Completer<SessionWsChannel> handshake =
          Completer<SessionWsChannel>();

      final TimeshiftViewUriResult result = await start(
        buildResolver(
          WatchPageWebSocketUrlResult.resolved(_wsUrl),
          channelFactory: (Uri uri, Map<String, String> headers) =>
              handshake.future,
          endpointTimeout: _shortTimeout,
        ),
      );
      expect(result.failure, TimeshiftViewUriFailure.timedOut);

      handshake.complete(channel);
      await Future<void>.delayed(Duration.zero);
      expect(channel.closeCount, 1);
    });

    test('ignores a non-https view URI and times out', () async {
      final Future<TimeshiftViewUriResult> pending = start(
        buildResolver(
          WatchPageWebSocketUrlResult.resolved(_wsUrl),
          endpointTimeout: _shortTimeout,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      channel.pushIncoming(
        _messageServer('http://mpn.live.nicovideo.jp/api/view/v4/BBzJ'),
      );
      final TimeshiftViewUriResult result = await pending;

      expect(result.viewUri, isNull);
      expect(result.failure, TimeshiftViewUriFailure.timedOut);
    });

    test(
      'fails with sessionFailed when the WebSocket cannot be opened',
      () async {
        final TimeshiftViewUriResult result = await start(
          buildResolver(
            WatchPageWebSocketUrlResult.resolved(_wsUrl),
            channelFactory: (Uri uri, Map<String, String> headers) async {
              throw StateError('cannot connect');
            },
          ),
        );

        expect(result.failure, TimeshiftViewUriFailure.sessionFailed);
      },
    );
  });
}
