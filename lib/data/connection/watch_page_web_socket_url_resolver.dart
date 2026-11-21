import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../app_logging.dart';

/// Resolves the logged-in viewer's session WebSocket URL from the niconico
/// watch page (`<script id="embedded-data">` → `site.relive.webSocketUrl`).
///
/// Used by the comment-post path before opening a comment-only session
/// WebSocket. Every failure is reported as `null` so that the caller can
/// fall back to cookie authentication.
class WatchPageWebSocketUrlResolver {
  WatchPageWebSocketUrlResolver({
    HttpClient Function()? httpClientFactory,
    Uri? watchPageBaseUri,
    Duration fetchTimeout = defaultFetchTimeout,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _watchPageBaseUri = watchPageBaseUri ?? Uri.parse(_watchPageBaseUrl),
       _fetchTimeout = fetchTimeout;

  /// Upper bound for the whole watch-page fetch (all redirects, headers and
  /// body). Part of the comment-post time budget (Issue #1029).
  static const Duration defaultFetchTimeout = Duration(seconds: 8);

  static const String _watchPageBaseUrl = 'https://live.nicovideo.jp/watch/';

  /// Desktop User-Agent for the watch page fetch.
  ///
  /// The mobile Android UA (`Chrome Mobile`) triggers a 302 redirect to
  /// `sp.live.nicovideo.jp` which serves a mobile page WITHOUT the
  /// `<script id="embedded-data">` tag. A desktop Chrome UA returns the
  /// desktop page that contains embedded-data with the webSocketUrl.
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static final RegExp _embeddedDataPattern = RegExp(
    r'<script[^>]*\bid="embedded-data"[^>]*\bdata-props="([^"]*)"',
    caseSensitive: false,
  );

  static const int _maxWatchPageRedirects = 5;

  final HttpClient Function() _httpClientFactory;
  final Uri _watchPageBaseUri;
  final Duration _fetchTimeout;

  /// Returns the session WebSocket URL for [lv], or `null` on any failure.
  Future<Uri?> resolve(String lv, String userSession) async {
    return _fetchWatchPageWsUrl(_watchPageBaseUri.resolve(lv), userSession);
  }

  Future<Uri?> _fetchWatchPageWsUrl(Uri watchUri, String userSession) async {
    HttpClient? httpClient;
    Timer? deadline;
    try {
      httpClient = _httpClientFactory();
      httpClient.connectionTimeout = const Duration(seconds: 5);
      // Force-closing the client aborts whatever step is pending (connect,
      // headers or body read) so the fetch really stops at the deadline. A
      // plain `Future.timeout` would leave the request running and skip the
      // `finally` below until the stalled read completed (Issue #1029).
      final HttpClient client = httpClient;
      deadline = Timer(_fetchTimeout, () => client.close(force: true));

      Uri currentUri = watchUri;
      HttpClientResponse? response;

      for (
        int redirectCount = 0;
        redirectCount <= _maxWatchPageRedirects;
        redirectCount++
      ) {
        final HttpClientRequest request = await httpClient.getUrl(currentUri);
        request.followRedirects = false;
        request.headers.set('Cookie', 'user_session=$userSession');
        request.headers.set('X-Niconico-Session', userSession);
        request.headers.set('User-Agent', _desktopUserAgent);
        request.headers.set('Accept', 'text/html');

        response = await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final String? location = response.headers.value('location');
          await response.drain<void>();
          if (location == null || location.isEmpty) {
            return null;
          }
          currentUri = currentUri.resolve(location);
          if (currentUri.host.startsWith('sp.')) {
            return null;
          }
          continue;
        }

        break;
      }

      if (response == null || response.statusCode != 200) {
        if (response != null) {
          await response.drain<void>();
        }
        return null;
      }

      final String body = await response.transform(utf8.decoder).join();
      return _extractWsUrlFromHtml(body);
    } on Object catch (e) {
      appDebugLog('[WatchPageWebSocketUrlResolver] fetch failed: $e');
      return null;
    } finally {
      deadline?.cancel();
      httpClient?.close(force: true);
    }
  }

  Uri? _extractWsUrlFromHtml(String body) {
    final RegExpMatch? match = _embeddedDataPattern.firstMatch(body);
    if (match == null) {
      return null;
    }

    final String? escaped = match.group(1);
    if (escaped == null || escaped.isEmpty) {
      return null;
    }
    final String json = _unescapeHtmlAttribute(escaped);
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final Object? site = decoded['site'];
    if (site is! Map<String, dynamic>) {
      return null;
    }
    final Object? relive = site['relive'];
    if (relive is! Map<String, dynamic>) {
      return null;
    }
    final String? wsUrl = relive['webSocketUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      return null;
    }

    final Uri parsed = Uri.parse(wsUrl);
    final Map<String, String> queryParams = Map<String, String>.from(
      parsed.queryParameters,
    );
    if (!queryParams.containsKey('frontend_id')) {
      queryParams['frontend_id'] = '9';
    }
    return parsed.replace(queryParameters: queryParams);
  }

  static String _unescapeHtmlAttribute(String input) {
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
}
