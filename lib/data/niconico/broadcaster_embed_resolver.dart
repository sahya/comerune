import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../app_logging.dart';
import '../follow/program_parser.dart' as program_parser;
import 'niconico_authed_http_client.dart';

/// Result of [BroadcasterEmbedResolver.resolve]: a numeric broadcaster
/// user ID and (optionally) the broadcaster's display name extracted from
/// the niconico live watch page.
@immutable
class BroadcasterEmbedInfo {
  const BroadcasterEmbedInfo({required this.userId, this.name});

  /// Numeric niconico user ID of the broadcaster (positive integer as
  /// string). Channel / community IDs (`ch...`, `co0`, ...) are filtered
  /// out by [BroadcasterEmbedResolver] before construction.
  final String userId;

  /// Broadcaster display name when present in the embedded data, otherwise
  /// `null`. Callers may seed name caches with this value to avoid an
  /// extra nickname-API round-trip.
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is BroadcasterEmbedInfo &&
      other.userId == userId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(userId, name);

  @override
  String toString() => 'BroadcasterEmbedInfo(userId: $userId, name: $name)';
}

/// Resolves the broadcaster's numeric user ID for an `lv...` program by
/// scraping the public niconico live watch page (`live.nicovideo.jp/watch/<lv>`).
///
/// This is the LV-direct-input counterpart to PR #685's pre-binding via
/// `FollowProgram.providerUserId`: when the user pastes an `lv` directly
/// the follow-list metadata is unavailable and `programInfo.supplierUserId`
/// is sometimes absent for user broadcasts, leading the legacy code path
/// to fall back to using the `lv` itself as a user-attribute key.
///
/// The resolver is intentionally best-effort: any HTTP / parse failure
/// yields `null` so callers can continue with the existing accumulate-and-
/// flush behaviour. It performs a single GET request and never retries.
class BroadcasterEmbedResolver {
  /// [connectionTimeout] is applied to the underlying [HttpClient.connectionTimeout]
  /// and only guards the initial TCP / TLS handshake. [requestTimeout]
  /// wraps the entire fetch (connect → headers → full body read), so it
  /// must be at least as long as [connectionTimeout]; the default of
  /// 5 s connect / 8 s overall reserves ~3 s for the body read of a
  /// ~300 KB document, which is sufficient even on slow mobile networks.
  BroadcasterEmbedResolver({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    Duration connectionTimeout = const Duration(seconds: 5),
    Duration requestTimeout = const Duration(seconds: 8),
    String userAgent = NiconicoAuthedHttpClient.defaultUserAgent,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _connectionTimeout = connectionTimeout,
       _requestTimeout = requestTimeout,
       _userAgent = userAgent {
    if (httpClient != null) {
      _seedHttpClient = httpClient;
    }
  }

  static const String _logName = 'BroadcasterEmbedResolver';
  static const String _baseUrl = 'https://live.nicovideo.jp/watch/';

  /// Cap on the response body we will read into memory. The watch HTML is
  /// ~300 KB in practice; this guard prevents an adversarial / corrupted
  /// response from exhausting memory.
  static const int _maxResponseBytes = 2 * 1024 * 1024;

  final HttpClient Function() _httpClientFactory;
  final Duration _connectionTimeout;
  final Duration _requestTimeout;
  final String _userAgent;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;
  bool _disposed = false;

  HttpClient get _activeHttpClient {
    final HttpClient? current = _httpClient;
    if (current != null) {
      return current;
    }
    final HttpClient? seed = _seedHttpClient;
    if (seed != null) {
      _seedHttpClient = null;
      _httpClient = seed;
      seed.connectionTimeout = _connectionTimeout;
      return seed;
    }
    final HttpClient created = _httpClientFactory();
    created.connectionTimeout = _connectionTimeout;
    _httpClient = created;
    return created;
  }

  /// Fetches the watch page for [lv] and extracts the broadcaster's
  /// numeric user ID (and name if present). Returns `null` when:
  ///
  /// - [lv] is not a valid `lv<digits>` token (mirrors
  ///   [NiconicoAuthedHttpClient.isValidLv] to prevent URL injection),
  /// - the HTTP request fails / times out,
  /// - the response status is not 200,
  /// - the embedded-data script tag is missing,
  /// - the JSON cannot be decoded,
  /// - or no positive numeric user ID can be found in the payload (e.g.
  ///   channel / community broadcasts whose only IDs are `ch...` / `co0`).
  ///
  /// The method intentionally never throws.
  Future<BroadcasterEmbedInfo?> resolve(String lv) async {
    if (_disposed) {
      return null;
    }
    if (!NiconicoAuthedHttpClient.isValidLv(lv)) {
      return null;
    }

    HttpClientRequest? request;
    try {
      final Uri uri = Uri.parse('$_baseUrl$lv');
      // Wrap the entire flow — connect, send, *and* body read — in one
      // timeout so a slow-trickle server cannot dribble bytes for minutes
      // while keeping the connection nominally "open". `request?.abort()`
      // tears down the underlying socket so the body-read stream
      // subscription resolves with an error instead of hanging on the
      // next chunk.
      final BroadcasterEmbedInfo? info =
          await _runFetch(uri, (HttpClientRequest req) {
            request = req;
          }).timeout(
            _requestTimeout,
            onTimeout: () {
              request?.abort();
              throw TimeoutException(
                'Embed page fetch timed out',
                _requestTimeout,
              );
            },
          );
      return info;
    } on TimeoutException {
      appDebugLogLazy(() => '[$_logName] $lv: timeout after $_requestTimeout');
      return null;
    } on Object catch (error) {
      // Match `NiconicoAuthedHttpClient.handleException`: log the runtime
      // type only, not the full exception, to avoid leaking socket-level
      // details (remote addresses, file descriptors, partial payloads)
      // into log sinks that may be attached at runtime.
      appErrorLog(
        name: _logName,
        message: 'Failed to resolve $lv: ${error.runtimeType}',
      );
      return null;
    }
  }

  Future<BroadcasterEmbedInfo?> _runFetch(
    Uri uri,
    void Function(HttpClientRequest request) onRequest,
  ) async {
    final HttpClientRequest req = await _activeHttpClient.getUrl(uri);
    onRequest(req);
    req.headers.set('User-Agent', _userAgent);
    req.headers.set('Accept', 'text/html');
    final HttpClientResponse response = await req.close();

    if (response.statusCode != 200) {
      appDebugLogLazy(
        () => '[$_logName] ${uri.path}: HTTP ${response.statusCode}',
      );
      await response.drain<void>();
      return null;
    }

    final String body = await _readCappedBody(response);
    if (_disposed) {
      return null;
    }
    return _extractFromHtml(body);
  }

  Future<String> _readCappedBody(HttpClientResponse response) async {
    final BytesBuilder buffer = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      buffer.add(chunk);
      if (buffer.length > _maxResponseBytes) {
        // Stop reading; the embedded-data tag appears in the document head
        // so any sane response will fit. Truncating preserves what we have
        // and the regex search will succeed if the tag is already in
        // the prefix.
        break;
      }
    }
    return utf8.decode(buffer.takeBytes(), allowMalformed: true);
  }

  /// Closes the underlying HTTP client. Safe to call multiple times.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _httpClient?.close(force: true);
    _httpClient = null;
    _seedHttpClient = null;
  }
}

/// `<script id="embedded-data" data-props="..."></script>` is the script
/// tag the niconico live page renders the program JSON into. The capture
/// group returns the (HTML-escaped) JSON payload. Hoisted to file level
/// so [extractBroadcasterEmbedInfoFromHtml] does not have to reach into
/// the resolver class for a private static.
final RegExp _embeddedDataPattern = RegExp(
  r'<script[^>]*\bid="embedded-data"[^>]*\bdata-props="([^"]*)"',
  caseSensitive: false,
);

/// Extracts a broadcaster info from a niconico watch-page HTML body.
///
/// Visible for testing so unit tests can exercise parsing without a fake
/// HTTP client. Returns `null` when the embedded-data tag is missing,
/// JSON fails to decode, or no numeric user ID can be located.
@visibleForTesting
BroadcasterEmbedInfo? extractBroadcasterEmbedInfoFromHtml(String html) =>
    _extractFromHtml(html);

BroadcasterEmbedInfo? _extractFromHtml(String html) {
  final RegExpMatch? match = _embeddedDataPattern.firstMatch(html);
  if (match == null) {
    return null;
  }
  final String? escaped = match.group(1);
  if (escaped == null || escaped.isEmpty) {
    return null;
  }
  final String json = _unescapeHtmlAttribute(escaped);
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) {
    return null;
  }

  final Map<String, dynamic>? programMap = _asStringKeyedMap(
    decoded['program'],
  );
  if (programMap == null) {
    return null;
  }

  final String? userId = program_parser.extractProviderUserId(programMap);
  if (userId == null) {
    return null;
  }
  final String? rawName = program_parser.extractProviderName(programMap);
  final String? name = (rawName != null && rawName.isNotEmpty) ? rawName : null;

  return BroadcasterEmbedInfo(userId: userId, name: name);
}

Map<String, dynamic>? _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

/// Decodes the HTML attribute escaping that niconico applies to the
/// embedded-data JSON payload. We accept the small fixed set of named /
/// numeric character references that appear in attribute context. `&amp;`
/// is processed last so that `&amp;quot;` decodes to `&quot;` (single-pass
/// semantics) rather than to `"`.
String _unescapeHtmlAttribute(String input) {
  String s = input;
  // Order matters: substitute the easy ones first so `&amp;quot;` becomes
  // `&quot;` (not `"`).
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
