import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../../app_logging.dart';

/// Outcome of reading the watch WebSocket URL from a niconico live watch
/// page.
enum WatchPageWebSocketUrlStatus {
  /// The page exposed a non-empty `site.relive.webSocketUrl`.
  resolved,

  /// The page was read, but `site.relive.webSocketUrl` was empty. For an
  /// ended program this means the logged-in user cannot watch it right now
  /// (no timeshift reservation, no ticket, or the viewing period expired).
  notWatchable,

  /// The page could not be fetched or did not contain the expected data
  /// (network error, non-200 response, redirect to the mobile site,
  /// missing or malformed embedded data).
  unavailable,
}

/// Result of [WatchPageWebSocketUrlResolver.resolve] and
/// [parseWatchPageWebSocketUrl].
@immutable
class WatchPageWebSocketUrlResult {
  const WatchPageWebSocketUrlResult.resolved(Uri this.url)
    : status = WatchPageWebSocketUrlStatus.resolved;

  const WatchPageWebSocketUrlResult.notWatchable()
    : status = WatchPageWebSocketUrlStatus.notWatchable,
      url = null;

  const WatchPageWebSocketUrlResult.unavailable()
    : status = WatchPageWebSocketUrlStatus.unavailable,
      url = null;

  final WatchPageWebSocketUrlStatus status;

  /// The watch WebSocket URL; non-null only when [status] is
  /// [WatchPageWebSocketUrlStatus.resolved].
  final Uri? url;
}

final RegExp _embeddedDataPattern = RegExp(
  r'<script[^>]*\bid="embedded-data"[^>]*\bdata-props="([^"]*)"',
  caseSensitive: false,
);

/// Extracts `site.relive.webSocketUrl` from the HTML of a watch page.
///
/// A missing `frontend_id` query parameter is filled with `9`, which the
/// watch WebSocket expects from web clients. Only `wss://` URLs on a
/// `nicovideo.jp` host are accepted, because callers send the session
/// cookie to this URL.
WatchPageWebSocketUrlResult parseWatchPageWebSocketUrl(String html) {
  final RegExpMatch? match = _embeddedDataPattern.firstMatch(html);
  final String? escaped = match?.group(1);
  if (escaped == null || escaped.isEmpty) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(_unescapeHtmlAttribute(escaped));
  } on FormatException {
    return const WatchPageWebSocketUrlResult.unavailable();
  }
  if (decoded is! Map<String, dynamic>) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }
  final Object? site = decoded['site'];
  if (site is! Map<String, dynamic>) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }
  final Object? relive = site['relive'];
  if (relive is! Map<String, dynamic>) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }

  final Object? rawUrl = relive['webSocketUrl'];
  if (rawUrl != null && rawUrl is! String) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }
  if (rawUrl == null || (rawUrl as String).isEmpty) {
    return const WatchPageWebSocketUrlResult.notWatchable();
  }

  final Uri? parsed = Uri.tryParse(rawUrl);
  if (parsed == null ||
      parsed.scheme != 'wss' ||
      !_isNicovideoHost(parsed.host)) {
    return const WatchPageWebSocketUrlResult.unavailable();
  }
  final Map<String, String> queryParams = Map<String, String>.from(
    parsed.queryParameters,
  );
  queryParams.putIfAbsent('frontend_id', () => '9');
  return WatchPageWebSocketUrlResult.resolved(
    parsed.replace(queryParameters: queryParams),
  );
}

bool _isNicovideoHost(String host) {
  final String lower = host.toLowerCase();
  return lower == 'nicovideo.jp' || lower.endsWith('.nicovideo.jp');
}

String _unescapeHtmlAttribute(String input) {
  String s = input;
  s = s.replaceAll('&lt;', '<');
  s = s.replaceAll('&gt;', '>');
  s = s.replaceAll('&quot;', '"');
  s = s.replaceAll('&apos;', "'");
  s = s.replaceAll('&#34;', '"');
  s = s.replaceAll('&#39;', "'");
  s = s.replaceAll('&#x22;', '"');
  s = s.replaceAll('&#x27;', "'");
  s = s.replaceAll('&#x2F;', '/');
  s = s.replaceAll('&#47;', '/');
  s = s.replaceAll('&#60;', '<');
  s = s.replaceAll('&#62;', '>');
  s = s.replaceAll('&amp;', '&');
  return s;
}

/// Fetches a niconico live watch page with the user's session cookie and
/// reads the watch WebSocket URL from its embedded data.
///
/// Used by the comment-post path and by the timeshift path. Never throws:
/// every failure is reported as [WatchPageWebSocketUrlStatus.unavailable].
///
/// Redirects are followed only within the watch page's own scheme and
/// host, so the session cookie is never sent to another host.
class WatchPageWebSocketUrlResolver {
  WatchPageWebSocketUrlResolver({
    HttpClient Function()? httpClientFactory,
    Uri? watchPageBaseUri,
    Duration connectionTimeout = const Duration(seconds: 5),
    Duration responseTimeout = const Duration(seconds: 8),
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _watchPageBaseUri =
           watchPageBaseUri ?? Uri.parse('https://live.nicovideo.jp/watch/'),
       _connectionTimeout = connectionTimeout,
       _responseTimeout = responseTimeout;

  /// Desktop User-Agent for the watch page fetch.
  ///
  /// The mobile Android UA (`Chrome Mobile`) triggers a 302 redirect to
  /// `sp.live.nicovideo.jp`, which serves a mobile page WITHOUT the
  /// `<script id="embedded-data">` tag. A desktop Chrome UA returns the
  /// desktop page that contains the embedded data.
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const int _maxRedirects = 5;

  final HttpClient Function() _httpClientFactory;
  final Uri _watchPageBaseUri;
  final Duration _connectionTimeout;
  final Duration _responseTimeout;

  Future<WatchPageWebSocketUrlResult> resolve({
    required String lv,
    required String userSession,
  }) async {
    HttpClient? httpClient;
    try {
      httpClient = _httpClientFactory();
      httpClient.connectionTimeout = _connectionTimeout;

      Uri currentUri = _watchPageBaseUri.resolve(lv);
      HttpClientResponse? response;

      for (
        int redirectCount = 0;
        redirectCount <= _maxRedirects;
        redirectCount++
      ) {
        final HttpClientRequest request = await httpClient.getUrl(currentUri);
        request.followRedirects = false;
        request.headers.set('Cookie', 'user_session=$userSession');
        request.headers.set('X-Niconico-Session', userSession);
        request.headers.set('User-Agent', desktopUserAgent);
        request.headers.set('Accept', 'text/html');

        response = await request.close().timeout(_responseTimeout);
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final String? location = response.headers.value('location');
          await response.drain<void>().timeout(_responseTimeout);
          if (location == null || location.isEmpty) {
            return const WatchPageWebSocketUrlResult.unavailable();
          }
          currentUri = currentUri.resolve(location);
          // A redirect to the mobile site (`sp.`) serves no embedded data,
          // and any other host must not receive the session cookie.
          if (currentUri.scheme != _watchPageBaseUri.scheme ||
              currentUri.host != _watchPageBaseUri.host) {
            return const WatchPageWebSocketUrlResult.unavailable();
          }
          response = null;
          continue;
        }

        break;
      }

      if (response == null || response.statusCode != 200) {
        if (response != null) {
          await response.drain<void>().timeout(_responseTimeout);
        }
        return const WatchPageWebSocketUrlResult.unavailable();
      }

      final String body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_responseTimeout);
      return parseWatchPageWebSocketUrl(body);
    } on Object catch (error) {
      // Only the error type is logged: the request carried the session
      // cookie and messages from the HTTP stack may echo request details.
      appDebugLog(
        '[WatchPageWebSocketUrlResolver] fetch failed: ${error.runtimeType}',
      );
      return const WatchPageWebSocketUrlResult.unavailable();
    } finally {
      httpClient?.close(force: true);
    }
  }
}
