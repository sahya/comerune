import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../domain/models/follow_program.dart';
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
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
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

    // Extract the vpos base time (Issue #465). N Air uses
    // `programSchedule.vposBaseTime` as the authoritative reference for
    // computing comment `vpos`, which can differ from `beginAt`
    // (開場時刻 vs 配信開始時刻) by several seconds. When this field is
    // present callers should prefer it over `beginAt`; when absent, the
    // existing `beginAt` fallback keeps the previous behaviour intact.
    final DateTime? vposBaseAt = _extractVposBaseAt(data);

    // Extract broadcast status (Issue #639 cause 2). `data.status` is
    // either `'onAir'` (currently broadcasting) or `'ended'` (timeshift).
    // This lets the caller short-circuit live-session attempts for
    // already-ended broadcasts and route them into the NDGR timeshift
    // HTTP flow instead. Unknown / missing values yield `null` so the
    // caller falls back to the existing live-path behaviour.
    final ProgramStatus? programStatus = parseProgramStatus(
      data['status'] as String?,
    );

    log(
      'Resolved NDGR viewUri for $lv via programinfo'
      ' (broadcaster: ${broadcasterInfo.name ?? 'null'}'
      ', userId: ${broadcasterInfo.userId ?? 'null'}'
      ', beginAt: ${beginAt?.toIso8601String() ?? 'null'}'
      ', vposBaseAt: ${vposBaseAt?.toIso8601String() ?? 'null'})',
      name: 'ProgramInfoResolver',
    );
    // Mirror to debugPrint in debug builds so the vposBaseAt extraction is
    // visible in `adb logcat` / `flutter logs` (which do not forward
    // `dart:developer.log` reliably). Stripped in release by kDebugMode.
    if (kDebugMode) {
      debugPrint(
        '[ProgramInfoResolver] Resolved NDGR viewUri for $lv '
        '(beginAt: ${beginAt?.toIso8601String() ?? 'null'}, '
        'vposBaseAt: ${vposBaseAt?.toIso8601String() ?? 'null'})',
      );
    }
    return ProgramInfo(
      viewUri: parsed,
      title: title,
      supplierUserId: broadcasterInfo.userId,
      broadcasterName: broadcasterInfo.name,
      beginAt: beginAt,
      vposBaseAt: vposBaseAt,
      programStatus: programStatus,
    );
  }

  /// Extracts `vposBaseAt` from the programinfo response (Issue #465).
  ///
  /// Tries, in order:
  ///   1. `data.programSchedule.vposBaseTime` — N Air's documented path.
  ///   2. `data.vposBaseAt` — flatter shape observed on some related APIs.
  ///
  /// Both paths are parsed via [parseDateTimeFlexible] so ISO 8601 strings,
  /// seconds-epoch ints and milliseconds-epoch ints are all accepted. Any
  /// other shape (float, map, list, non-parseable string) returns `null`
  /// so the caller falls back to `beginAt`. This conservative path keeps
  /// viewer-visible timestamps safe even if upstream ever renames the
  /// field: at worst we revert to today's `beginAt`-based vpos rather
  /// than decoding something unrelated as a timestamp.
  static DateTime? _extractVposBaseAt(Map<String, dynamic> data) {
    // Candidate A: nested under `programSchedule`.
    final Object? programSchedule = data['programSchedule'];
    if (programSchedule is Map<String, dynamic>) {
      final DateTime? fromSchedule = parseDateTimeFlexible(
        programSchedule['vposBaseTime'],
      );
      if (fromSchedule != null) {
        return fromSchedule;
      }
    }

    // Candidate B: top-level fallback.
    return parseDateTimeFlexible(data['vposBaseAt']);
  }

  /// Extracts the broadcaster user ID and display name from the programinfo
  /// response data.
  ///
  /// Tries `data.broadcaster[0]` first (N Air's documented field) for both
  /// `id` and `name`, then falls back to `data.supplier.programProviderId`
  /// for the user ID and `data.supplier.name` for the display name.
  /// When broadcaster has a name but no id, the name is still captured and
  /// supplier is only consulted for the user ID.
  ///
  /// N-Air's type definition marks `broadcaster[0].id` as required (`number`),
  /// but the actual API response may omit it for some broadcasts. This method
  /// handles the missing-id case defensively to ensure the broadcaster name
  /// is not lost.
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
    this.vposBaseAt,
    this.programStatus,
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

  /// Authoritative vpos base time (Issue #465), extracted from
  /// `data.programSchedule.vposBaseTime` (primary) or `data.vposBaseAt`
  /// (fallback).
  ///
  /// This is the reference N Air uses for comment `vpos` calculation.
  /// It can differ from [beginAt] by several seconds (開場 vs 配信開始)
  /// on extended / rehearsal broadcasts. Callers that compute a `vpos`
  /// for comment posting should prefer this value when non-null and
  /// fall back to [beginAt] otherwise — using `beginAt` as a fallback
  /// keeps behaviour identical to the pre-Issue-#465 code path.
  final DateTime? vposBaseAt;

  /// Program lifecycle status extracted from `data.status` (Issue #639).
  ///
  /// `null` indicates the server did not return a recognised status (legacy
  /// API responses, or unknown string). Callers should treat `null` as
  /// "unknown — assume live" to preserve historical behaviour.
  ///
  /// When equal to [ProgramStatus.ended], the broadcast is a timeshift and
  /// the live session WS / NDGR streaming path should be bypassed in favour
  /// of the NDGR timeshift HTTP fetch path.
  final ProgramStatus? programStatus;

  /// Whether this broadcast is a timeshift (past) broadcast.
  ///
  /// Equivalent to `programStatus == ProgramStatus.ended`. Provided as a
  /// named predicate so call sites (and tests) read intent rather than
  /// a status-value comparison. See [programStatus] for why `null` is
  /// treated as "assume live".
  bool get isTimeshift => programStatus == ProgramStatus.ended;
}

class ProgramInfoResolveException implements Exception {
  ProgramInfoResolveException(this.message, {this.title});

  final String message;

  /// The program title, if it was successfully extracted before the error.
  final String? title;

  @override
  String toString() => 'ProgramInfoResolveException: $message';
}
