import 'dart:async';

import 'package:meta/meta.dart';

import '../../app_logging.dart';
import '../../domain/connection/session_ws_client.dart';
import 'watch_page_web_socket_url_resolver.dart';

/// Why [TimeshiftViewUriResolver.resolve] could not return a view URI.
enum TimeshiftViewUriFailure {
  /// No `user_session` is stored, so the watch page cannot be read as the
  /// user.
  notLoggedIn,

  /// The watch page exposed no WebSocket URL: the user has no right to
  /// watch this timeshift right now (no reservation, no ticket, or the
  /// viewing period expired).
  notWatchable,

  /// The watch page could not be fetched or parsed.
  watchPageUnavailable,

  /// The watch WebSocket closed, failed, or reported the end of the
  /// program before sending a comment server (`messageServer`) message;
  /// sent only a legacy endpoint; or sent an unusable view URI.
  sessionFailed,

  /// The WebSocket did not connect, or no comment server message arrived,
  /// within the timeout.
  timedOut,
}

/// Result of [TimeshiftViewUriResolver.resolve]: either [viewUri] or
/// [failure] is non-null.
@immutable
class TimeshiftViewUriResult {
  const TimeshiftViewUriResult.resolved(Uri this.viewUri) : failure = null;

  const TimeshiftViewUriResult.failed(TimeshiftViewUriFailure this.failure)
    : viewUri = null;

  final Uri? viewUri;
  final TimeshiftViewUriFailure? failure;
}

/// Resolves the NDGR view URI of an ended program (timeshift).
///
/// `programinfo` returns `rooms=[]` for ended programs (Issue #654), so the
/// view URI is taken from the watch WebSocket instead:
///
/// 1. Read `site.relive.webSocketUrl` from the watch page with the user's
///    session cookie.
/// 2. Connect to that WebSocket, send `startWatching`, and wait for the
///    `messageServer` message that carries the view URI.
/// 3. Close the WebSocket; the NDGR HTTP fetch does not need it.
///
/// This never makes a timeshift reservation or starts the viewing period:
/// those actions consume the user's viewing right, so they are left to the
/// user (reported as [TimeshiftViewUriFailure.notWatchable]).
class TimeshiftViewUriResolver {
  TimeshiftViewUriResolver({
    WatchPageWebSocketUrlResolver? watchPageResolver,
    SessionWsChannelFactory? channelFactory,
    Duration endpointTimeout = const Duration(seconds: 15),
  }) : _watchPageResolver =
           watchPageResolver ?? WatchPageWebSocketUrlResolver(),
       _channelFactory =
           channelFactory ?? SessionWsClient.defaultChannelFactory,
       _endpointTimeout = endpointTimeout;

  final WatchPageWebSocketUrlResolver _watchPageResolver;

  /// Test seam for the WebSocket channel; defaults to a real WebSocket.
  final SessionWsChannelFactory _channelFactory;
  final Duration _endpointTimeout;

  Future<TimeshiftViewUriResult> resolve({
    required String lv,
    required String userSession,
  }) async {
    if (userSession.isEmpty) {
      return const TimeshiftViewUriResult.failed(
        TimeshiftViewUriFailure.notLoggedIn,
      );
    }

    final WatchPageWebSocketUrlResult page = await _watchPageResolver.resolve(
      lv: lv,
      userSession: userSession,
    );
    switch (page.status) {
      case WatchPageWebSocketUrlStatus.notWatchable:
        return const TimeshiftViewUriResult.failed(
          TimeshiftViewUriFailure.notWatchable,
        );
      case WatchPageWebSocketUrlStatus.unavailable:
        return const TimeshiftViewUriResult.failed(
          TimeshiftViewUriFailure.watchPageUnavailable,
        );
      case WatchPageWebSocketUrlStatus.resolved:
        break;
    }

    final SessionWsClient client = SessionWsClient(
      lv: lv,
      webSocketUri: page.url,
      channelFactory: _connectWithTimeout,
      // `startWatching` with empty data, as public NDGR clients do for ended
      // programs (not yet verified on a real device): no video stream is
      // requested.
      startWatchingMode: SessionWsStartWatchingMode.minimal,
      connectHeaders: <String, String>{
        'Cookie': 'user_session=$userSession',
        'X-Niconico-Session': userSession,
      },
      endpointResolveTimeout: _endpointTimeout,
    );
    final Completer<TimeshiftViewUriResult> completer =
        Completer<TimeshiftViewUriResult>();
    void complete(TimeshiftViewUriResult result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    final StreamSubscription<SessionWsEvent> subscription = client.events
        .listen((SessionWsEvent event) {
          switch (event.type) {
            case SessionWsEventType.ndgrEndpointResolved:
              final Uri? viewUri = Uri.tryParse(event.ndgrViewUri ?? '');
              complete(
                viewUri == null || viewUri.host.isEmpty
                    ? const TimeshiftViewUriResult.failed(
                        TimeshiftViewUriFailure.sessionFailed,
                      )
                    : TimeshiftViewUriResult.resolved(viewUri),
              );
            case SessionWsEventType.failed:
              complete(
                TimeshiftViewUriResult.failed(
                  event.errorCode == SessionWsErrorCode.endpointResolveFailed
                      ? TimeshiftViewUriFailure.timedOut
                      : TimeshiftViewUriFailure.sessionFailed,
                ),
              );
            case SessionWsEventType.error:
              if (event.errorCode == SessionWsErrorCode.connectFailed) {
                complete(
                  TimeshiftViewUriResult.failed(
                    event.error is TimeoutException
                        ? TimeshiftViewUriFailure.timedOut
                        : TimeshiftViewUriFailure.sessionFailed,
                  ),
                );
              }
            case SessionWsEventType.legacyEndpointResolved:
            case SessionWsEventType.broadcastEnded:
            case SessionWsEventType.disconnected:
              complete(
                const TimeshiftViewUriResult.failed(
                  TimeshiftViewUriFailure.sessionFailed,
                ),
              );
            case SessionWsEventType.connected:
            case SessionWsEventType.debugLog:
              break;
          }
        });

    try {
      await client.connect();
      // Safety net in case the client never reports a terminal event.
      return await completer.future.timeout(
        _endpointTimeout + const Duration(seconds: 1),
        onTimeout: () => const TimeshiftViewUriResult.failed(
          TimeshiftViewUriFailure.timedOut,
        ),
      );
    } on Object catch (error) {
      appDebugLog(
        '[TimeshiftViewUriResolver] session failed: ${error.runtimeType}',
      );
      return const TimeshiftViewUriResult.failed(
        TimeshiftViewUriFailure.sessionFailed,
      );
    } finally {
      await subscription.cancel();
      try {
        await client.dispose().timeout(const Duration(seconds: 2));
      } on Object {
        // Closing is best effort; the socket is dropped either way.
      }
    }
  }

  /// Opens the WebSocket, giving up after [_endpointTimeout] so a stalled
  /// TCP / TLS handshake cannot keep the lookup open. A connection that
  /// completes after the timeout is closed right away.
  Future<SessionWsChannel> _connectWithTimeout(
    Uri uri,
    Map<String, String> headers,
  ) {
    final Future<SessionWsChannel> connecting = Future<SessionWsChannel>.sync(
      () => _channelFactory(uri, headers),
    );
    return connecting.timeout(
      _endpointTimeout,
      onTimeout: () {
        unawaited(
          connecting.then<void>(
            (SessionWsChannel lateChannel) => lateChannel.close(),
            onError: (Object _) {},
          ),
        );
        throw TimeoutException('WebSocket connect timed out', _endpointTimeout);
      },
    );
  }
}
