import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import '../utils/begin_at_parser.dart';

/// Resolves the NDGR view URI from the niconico programinfo API.
///
/// Follows the same flow as N Air (official niconico streaming tool):
/// 1. Call programinfo API with user_session cookie
/// 2. Extract rooms[].viewUri from the response
///
/// This bypasses the WebSocket handshake entirely — the viewUri is
/// obtained directly via a single HTTP call.
class ProgramInfoResolver {
  ProgramInfoResolver({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    String userAgent = defaultUserAgent,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new,
        _userAgent = userAgent,
        _connectionTimeout = connectionTimeout {
    if (httpClient != null) {
      _seedHttpClient = httpClient;
    }
  }

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome Mobile Safari/537.36';

  static const String _live2BaseUrl = 'https://live2.nicovideo.jp';

  final HttpClient Function() _httpClientFactory;
  final String _userAgent;
  final Duration _connectionTimeout;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;

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

  /// Resolves the NDGR view URI and program title for the given live program.
  ///
  /// [lv] is the live program ID (e.g., "lv350186414").
  /// [userSession] is the value of the user_session cookie.
  ///
  /// Returns a [ProgramInfo] containing the NDGR view URI and program title.
  /// Throws [ProgramInfoResolveException] on failure.
  Future<ProgramInfo> resolve({
    required String lv,
    String userSession = '',
  }) async {
    final Uri uri = Uri.parse('$_live2BaseUrl/watch/$lv/programinfo');
    final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
    if (userSession.trim().isNotEmpty) {
      // Send session via both Cookie and X-Niconico-Session headers.
      // N Air uses Cookie header; some niconico APIs accept X-Niconico-Session.
      request.headers.set('Cookie', 'user_session=$userSession');
      request.headers.set('X-Niconico-Session', userSession);
    }
    request.headers.set('User-Agent', _userAgent);

    final HttpClientResponse response = await request.close();
    if (response.statusCode != 200) {
      final String body = await _readLimitedBody(response);
      throw ProgramInfoResolveException(
        'Failed to fetch program info: HTTP ${response.statusCode}: $body',
      );
    }

    final String body = await response.transform(utf8.decoder).join();
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info response is not a JSON object',
      );
    }

    final Object? data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info response missing "data" field',
      );
    }

    final String? title = data['title'] as String?;

    final Object? rooms = data['rooms'];
    if (rooms is! List || rooms.isEmpty) {
      throw ProgramInfoResolveException(
        'Program info response has no rooms',
        title: title,
      );
    }

    final Object? firstRoom = rooms[0];
    if (firstRoom is! Map<String, dynamic>) {
      throw ProgramInfoResolveException(
        'Program info room entry is not a JSON object',
        title: title,
      );
    }

    final String? viewUri = firstRoom['viewUri'] as String?;
    if (viewUri == null || viewUri.isEmpty) {
      throw ProgramInfoResolveException(
        'Program info room missing "viewUri" field',
        title: title,
      );
    }

    final Uri? parsed = Uri.tryParse(viewUri);
    if (parsed == null) {
      throw ProgramInfoResolveException(
        'Invalid viewUri: $viewUri',
        title: title,
      );
    }

    // Extract broadcaster info if available.
    //
    // The programinfo API returns broadcaster info in `data.broadcaster`
    // (array of {id, name}), as defined in N Air's ProgramInfo type.
    // The `name` field provides the display name directly, avoiding an
    // additional HTTP request to the nickname API.
    // Some responses may also include `data.supplier.programProviderId`
    // (undocumented but observed in related APIs) and `data.supplier.name`.
    // We try `broadcaster` first, then fall back to `supplier` for the user
    // ID and display name when broadcaster is unavailable.
    final ({String? userId, String? name}) broadcasterInfo =
        _extractBroadcasterInfo(data);

    // Extract the program start time so the UI can show elapsed time
    // instead of wall-clock time for each comment.
    final DateTime? beginAt = parseBeginAt(data);

    log(
      'Resolved NDGR viewUri for $lv via programinfo'
      ' (broadcaster: ${broadcasterInfo.name ?? 'null'}'
      ', userId: ${broadcasterInfo.userId ?? 'null'})',
      name: 'ProgramInfoResolver',
    );
    return ProgramInfo(
      viewUri: parsed,
      title: title,
      supplierUserId: broadcasterInfo.userId,
      broadcasterName: broadcasterInfo.name,
      beginAt: beginAt,
    );
  }

  /// Extracts the broadcaster user ID and display name from the programinfo
  /// response data.
  ///
  /// Tries `data.broadcaster[0]` first (N Air's documented field) for both
  /// `id` and `name`, then falls back to `data.supplier.programProviderId`
  /// for the user ID and `data.supplier.name` for the display name.
  /// When broadcaster has a name but no id, the name is still captured and
  /// supplier is only consulted for the user ID.
  static ({String? userId, String? name}) _extractBroadcasterInfo(
    Map<String, dynamic> data,
  ) {
    String? broadcasterName;
    String? broadcasterUserId;

    // Primary: data.broadcaster (array of {id, name}).
    final Object? broadcaster = data['broadcaster'];
    if (broadcaster is List && broadcaster.isNotEmpty) {
      final Object? first = broadcaster[0];
      if (first is Map<String, dynamic>) {
        final Object? id = first['id'];
        final Object? name = first['name'];
        if (id != null) {
          broadcasterUserId = id.toString();
        }
        if (name is String && name.isNotEmpty) {
          broadcasterName = name;
        }
        // If both id and name are available, return immediately.
        if (broadcasterUserId != null && broadcasterName != null) {
          return (userId: broadcasterUserId, name: broadcasterName);
        }
      }
    }

    // Fallback: data.supplier.programProviderId / data.supplier.name
    // (undocumented but observed).
    final Object? supplier = data['supplier'];
    if (supplier is Map<String, dynamic>) {
      final Object? name = supplier['name'];
      if (broadcasterName == null && name is String && name.isNotEmpty) {
        broadcasterName = name;
      }
      if (broadcasterUserId == null) {
        final Object? providerId = supplier['programProviderId'];
        if (providerId != null) {
          broadcasterUserId = providerId.toString();
        }
      }
    }

    if (broadcasterUserId != null || broadcasterName != null) {
      return (userId: broadcasterUserId, name: broadcasterName);
    }

    return (userId: null, name: null);
  }

  /// Reads at most [_maxErrorBodyBytes] bytes from the response to avoid
  /// consuming excessive memory on large error responses.
  static const int _maxErrorBodyBytes = 512;

  Future<String> _readLimitedBody(HttpClientResponse response) async {
    final List<int> bytes = <int>[];
    bool truncated = false;
    try {
      await for (final List<int> chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length >= _maxErrorBodyBytes) {
          truncated = true;
          break;
        }
      }
    } finally {
      // Drain any remaining bytes to release the underlying TCP connection
      // back to the pool. Without this, a partial read leaves the socket
      // open until the server or OS times it out.
      if (truncated) {
        await response.drain<void>();
      }
    }
    final String result = utf8.decode(
      truncated ? bytes.sublist(0, _maxErrorBodyBytes) : bytes,
      allowMalformed: true,
    );
    return truncated ? '$result...' : result;
  }

  void dispose() {
    _httpClient?.close();
    _httpClient = null;
    _seedHttpClient = null;
  }
}

/// Resolved program metadata returned by [ProgramInfoResolver.resolve].
class ProgramInfo {
  const ProgramInfo({
    required this.viewUri,
    this.title,
    this.supplierUserId,
    this.broadcasterName,
    this.beginAt,
  });

  /// The NDGR view URI extracted from `data.rooms[0].viewUri`.
  final Uri viewUri;

  /// The program title from `data.title`, or `null` when absent.
  final String? title;

  /// The broadcaster's user ID, extracted from `data.broadcaster[0].id`
  /// or `data.supplier.programProviderId`.
  final String? supplierUserId;

  /// The broadcaster's display name, extracted from `data.broadcaster[0].name`.
  /// Available immediately without an additional HTTP request.
  final String? broadcasterName;

  /// The program start time from `data.beginAt`, used to display elapsed
  /// time for comments. `null` when the field is absent or unparseable.
  final DateTime? beginAt;
}

class ProgramInfoResolveException implements Exception {
  ProgramInfoResolveException(this.message, {this.title});

  final String message;

  /// The program title, if it was successfully extracted before the error.
  final String? title;

  @override
  String toString() => 'ProgramInfoResolveException: $message';
}
