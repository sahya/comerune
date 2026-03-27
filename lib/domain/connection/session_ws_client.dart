import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:web_socket_channel/web_socket_channel.dart';

enum SessionWsEventType {
  connected,
  disconnected,
  ndgrEndpointResolved,
  legacyEndpointResolved,
  broadcastEnded,
  failed,
  error,
  debugLog,
}

enum SessionWsErrorCode {
  connectFailed,
  endpointResolveFailed,
  keepaliveResponseFailed,
  unknownBroadcastEndEvent,
}

class SessionWsEvent {
  const SessionWsEvent({
    required this.type,
    this.ndgrViewUri,
    this.legacyWebSocketUrl,
    this.errorCode,
    this.error,
    this.stackTrace,
    this.debugMessage,
  });

  final SessionWsEventType type;
  final String? ndgrViewUri;
  final String? legacyWebSocketUrl;
  final SessionWsErrorCode? errorCode;
  final Object? error;
  final StackTrace? stackTrace;
  final String? debugMessage;
}

class SessionEndpointResolution {
  const SessionEndpointResolution({this.ndgrViewUri, this.legacyWebSocketUrl});

  final String? ndgrViewUri;
  final String? legacyWebSocketUrl;

  String? get preferredEndpoint => ndgrViewUri ?? legacyWebSocketUrl;
}

abstract class SessionWsChannel {
  Stream<dynamic> get stream;
  StreamSink<dynamic> get sink;
  Future<void> close([int? code, String? reason]);
}

typedef SessionWsChannelFactory = FutureOr<SessionWsChannel> Function(Uri uri);

class WebSocketSessionWsChannel implements SessionWsChannel {
  WebSocketSessionWsChannel(this._inner);

  final WebSocketChannel _inner;

  @override
  Stream<dynamic> get stream => _inner.stream;

  @override
  StreamSink<dynamic> get sink => _inner.sink;

  @override
  Future<void> close([int? code, String? reason]) async {
    await _inner.sink.close(code, reason);
  }
}

class SessionWsClient {
  SessionWsClient({
    required this.lv,
    SessionWsChannelFactory? channelFactory,
    Duration endpointFallbackDelay = const Duration(milliseconds: 300),
    Duration endpointResolveTimeout = const Duration(seconds: 5),
    Map<String, Map<String, Object>>? keepaliveResponses,
  })  : _channelFactory = channelFactory ?? _defaultChannelFactory,
        _endpointFallbackDelay = endpointFallbackDelay,
        _endpointResolveTimeout = endpointResolveTimeout,
        _keepaliveResponses = keepaliveResponses == null
            ? const <String, Map<String, Object>>{
                'servertime': <String, Object>{'type': 'pong'},
                'ping': <String, Object>{'type': 'pong'},
              }
            : keepaliveResponses.map<String, Map<String, Object>>(
                (String key, Map<String, Object> value) =>
                    MapEntry<String, Map<String, Object>>(
                  key.toLowerCase(),
                  value,
                ),
              );

  final String lv;
  final SessionWsChannelFactory _channelFactory;
  final Duration _endpointFallbackDelay;
  final Duration _endpointResolveTimeout;
  final Map<String, Map<String, Object>> _keepaliveResponses;

  final StreamController<SessionWsEvent> _eventsController =
      StreamController<SessionWsEvent>.broadcast();

  SessionWsChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _legacyFallbackTimer;
  Timer? _endpointResolveTimer;
  Timer? _keepSeatTimer;
  String? _ndgrViewUri;
  String? _legacyWebSocketUrl;
  int? _keepSeatIntervalSec;
  bool _hasEmittedNdgrEndpoint = false;
  bool _hasEmittedLegacyEndpoint = false;
  bool _isConnected = false;
  bool _isClosing = false;
  bool _isDisposed = false;

  Stream<SessionWsEvent> get events => _eventsController.stream;

  Future<void> connect() async {
    if (_isDisposed) {
      throw StateError('SessionWsClient is already disposed');
    }
    if (_isConnected || _isClosing) {
      return;
    }
    _resetEndpointResolutionState();

    final Uri uri = Uri.parse('wss://a.live2.nicovideo.jp/wsapi/v2/watch/$lv');

    try {
      final SessionWsChannel channel = await _channelFactory(uri);
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleIncoming,
        onError: (Object error, StackTrace stackTrace) {
          _emit(
            SessionWsEvent(
              type: SessionWsEventType.error,
              errorCode: SessionWsErrorCode.connectFailed,
              error: error,
              stackTrace: stackTrace,
            ),
          );
        },
        onDone: _handleDone,
      );

      _isConnected = true;
      try {
        _sendStartWatching();
      } catch (_) {
        await _cleanupConnectionState(emitDisconnected: false);
        _emit(
          const SessionWsEvent(
            type: SessionWsEventType.error,
            errorCode: SessionWsErrorCode.connectFailed,
          ),
        );
        return;
      }
      _emit(const SessionWsEvent(type: SessionWsEventType.connected));
      _startEndpointResolveTimer();
    } catch (error, stackTrace) {
      _emit(
        SessionWsEvent(
          type: SessionWsEventType.error,
          errorCode: SessionWsErrorCode.connectFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<void> disconnect() async {
    if (_isDisposed) {
      return;
    }
    if (_isClosing) {
      return;
    }

    _isClosing = true;

    await _subscription?.cancel();
    _subscription = null;

    _legacyFallbackTimer?.cancel();
    _legacyFallbackTimer = null;
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = null;
    _stopKeepSeatTimer();

    final SessionWsChannel? channel = _channel;
    _channel = null;
    _isConnected = false;

    if (channel != null) {
      await channel.close();
    }

    _emit(const SessionWsEvent(type: SessionWsEventType.disconnected));
    _isClosing = false;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    await disconnect();
    _isDisposed = true;
    await _eventsController.close();
  }

  void _handleIncoming(dynamic payload) {
    final String raw = payload is String ? payload : payload.toString();

    final String sanitizedLog = SessionWsLogSanitizer.sanitizeRawJson(raw);
    log(sanitizedLog, name: 'SessionWsClient');
    _emit(
      SessionWsEvent(
        type: SessionWsEventType.debugLog,
        debugMessage: sanitizedLog,
      ),
    );

    final Object? decoded = _tryDecodeJson(raw);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final Map<String, Object>? keepaliveResponse = _resolveKeepaliveResponse(
      decoded,
    );
    if (keepaliveResponse != null) {
      _respondKeepalive(keepaliveResponse);
    }
    _updateKeepSeatTimerFromSeat(decoded);

    final SessionEndpointResolution resolution =
        SessionWsMessageParser.extractEndpoints(decoded);
    _recordEndpoints(resolution);

    _emitNdgrEndpointIfNeeded();
    _scheduleLegacyFallbackIfNeeded();

    final BroadcastEndDetection broadcastEndState =
        SessionWsMessageParser.detectBroadcastEnd(decoded);
    if (broadcastEndState == BroadcastEndDetection.ended) {
      _emit(const SessionWsEvent(type: SessionWsEventType.broadcastEnded));
      return;
    }

    if (broadcastEndState == BroadcastEndDetection.unknown) {
      _emit(
        const SessionWsEvent(
          type: SessionWsEventType.failed,
          errorCode: SessionWsErrorCode.unknownBroadcastEndEvent,
        ),
      );
      unawaited(disconnect());
    }
  }

  void _sendStartWatching() {
    _sendJson(const <String, Object>{
      'type': 'startWatching',
      'data': <String, Object>{
        'stream': <String, Object>{
          'quality': 'abr',
          'protocol': 'hls',
          'latency': 'low',
          'chasePlay': false,
        },
        'room': <String, Object>{
          'protocol': 'webSocket',
          'commentable': false,
        },
        'reconnect': false,
      },
    });
  }

  void _respondKeepalive(Map<String, Object> payload) {
    try {
      _sendJson(payload);
    } catch (error, stackTrace) {
      _emit(
        SessionWsEvent(
          type: SessionWsEventType.error,
          errorCode: SessionWsErrorCode.keepaliveResponseFailed,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      unawaited(disconnect());
    }
  }

  void _sendJson(Map<String, Object> payload) {
    final SessionWsChannel? channel = _channel;
    if (channel == null) {
      throw StateError('Session WS channel is not connected');
    }

    channel.sink.add(jsonEncode(payload));
  }

  Map<String, Object>? _resolveKeepaliveResponse(Map<String, dynamic> decoded) {
    final String? type = decoded['type']?.toString().toLowerCase();
    if (type == null) {
      return null;
    }
    return _keepaliveResponses[type];
  }

  void _updateKeepSeatTimerFromSeat(Map<String, dynamic> decoded) {
    final String? type = decoded['type']?.toString().toLowerCase();
    if (type != 'seat') {
      return;
    }

    final int? intervalSec = _extractKeepSeatIntervalSec(decoded);
    if (intervalSec == null || intervalSec <= 0) {
      return;
    }

    if (_keepSeatTimer != null && _keepSeatIntervalSec == intervalSec) {
      return;
    }

    _stopKeepSeatTimer();
    _keepSeatIntervalSec = intervalSec;
    _keepSeatTimer = Timer.periodic(Duration(seconds: intervalSec), (_) {
      _respondKeepalive(const <String, Object>{'type': 'keepSeat'});
    });
  }

  int? _extractKeepSeatIntervalSec(Map<String, dynamic> decoded) {
    final Object? data = decoded['data'] ?? decoded['body'];
    if (data is! Map) {
      return null;
    }

    final Object? rawInterval =
        data['keepIntervalSec'] ?? data['keep_interval_sec'];
    if (rawInterval is num) {
      return rawInterval.toInt();
    }
    if (rawInterval is String) {
      return int.tryParse(rawInterval);
    }
    return null;
  }

  Object? _tryDecodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _handleDone() {
    _legacyFallbackTimer?.cancel();
    _legacyFallbackTimer = null;
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = null;
    _stopKeepSeatTimer();
    _channel = null;
    _isConnected = false;
    if (_isClosing) {
      return;
    }
    _emit(const SessionWsEvent(type: SessionWsEventType.disconnected));
  }

  void _emit(SessionWsEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  static Future<SessionWsChannel> _defaultChannelFactory(Uri uri) async {
    final WebSocketChannel channel = WebSocketChannel.connect(uri);
    return WebSocketSessionWsChannel(channel);
  }

  void _recordEndpoints(SessionEndpointResolution resolution) {
    if (_ndgrViewUri == null && resolution.ndgrViewUri != null) {
      _ndgrViewUri = resolution.ndgrViewUri;
    }
    if (_legacyWebSocketUrl == null && resolution.legacyWebSocketUrl != null) {
      _legacyWebSocketUrl = resolution.legacyWebSocketUrl;
    }
  }

  void _emitNdgrEndpointIfNeeded() {
    final String? ndgr = _ndgrViewUri;
    if (ndgr == null || _hasEmittedNdgrEndpoint || _hasEmittedLegacyEndpoint) {
      return;
    }

    _legacyFallbackTimer?.cancel();
    _legacyFallbackTimer = null;
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = null;
    _hasEmittedNdgrEndpoint = true;
    _emit(
      SessionWsEvent(
        type: SessionWsEventType.ndgrEndpointResolved,
        ndgrViewUri: ndgr,
      ),
    );
  }

  void _scheduleLegacyFallbackIfNeeded() {
    final String? legacy = _legacyWebSocketUrl;
    if (legacy == null ||
        _hasEmittedNdgrEndpoint ||
        _hasEmittedLegacyEndpoint) {
      return;
    }

    if (_legacyFallbackTimer != null) {
      return;
    }

    _legacyFallbackTimer = Timer(_endpointFallbackDelay, () {
      _legacyFallbackTimer = null;
      if (_hasEmittedNdgrEndpoint || _hasEmittedLegacyEndpoint) {
        return;
      }

      _hasEmittedLegacyEndpoint = true;
      _endpointResolveTimer?.cancel();
      _endpointResolveTimer = null;
      _emit(
        SessionWsEvent(
          type: SessionWsEventType.legacyEndpointResolved,
          legacyWebSocketUrl: legacy,
        ),
      );
    });
  }

  void _resetEndpointResolutionState() {
    _legacyFallbackTimer?.cancel();
    _legacyFallbackTimer = null;
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = null;
    _stopKeepSeatTimer();
    _ndgrViewUri = null;
    _legacyWebSocketUrl = null;
    _keepSeatIntervalSec = null;
    _hasEmittedNdgrEndpoint = false;
    _hasEmittedLegacyEndpoint = false;
  }

  Future<void> _cleanupConnectionState({required bool emitDisconnected}) async {
    _legacyFallbackTimer?.cancel();
    _legacyFallbackTimer = null;
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = null;
    _stopKeepSeatTimer();

    await _subscription?.cancel();
    _subscription = null;

    final SessionWsChannel? channel = _channel;
    _channel = null;
    _isConnected = false;
    if (channel != null) {
      await channel.close();
    }

    if (emitDisconnected) {
      _emit(const SessionWsEvent(type: SessionWsEventType.disconnected));
    }
  }

  void _stopKeepSeatTimer() {
    _keepSeatTimer?.cancel();
    _keepSeatTimer = null;
    _keepSeatIntervalSec = null;
  }

  void _startEndpointResolveTimer() {
    _endpointResolveTimer?.cancel();
    _endpointResolveTimer = Timer(_endpointResolveTimeout, () {
      if (_hasEmittedNdgrEndpoint || _hasEmittedLegacyEndpoint) {
        return;
      }

      _emit(
        const SessionWsEvent(
          type: SessionWsEventType.failed,
          errorCode: SessionWsErrorCode.endpointResolveFailed,
        ),
      );
      unawaited(disconnect());
    });
  }
}

enum BroadcastEndDetection { none, ended, unknown }

class SessionWsMessageParser {
  static final RegExp _urlPattern = RegExp(
    r'((?:https?|wss):\/\/[^\s<>]+)',
    caseSensitive: false,
  );

  static const Set<String> _knownBroadcastEndedReasons = <String>{
    'END_PROGRAM',
    'END_BROADCAST',
    'PROGRAM_ENDED',
    'SERVICE_ENDED',
  };

  static SessionEndpointResolution extractEndpoints(Object? payload) {
    final List<String> texts = <String>[];
    _collectStrings(payload, texts);

    String? ndgrViewUri;
    String? legacyWebSocketUrl;

    for (final String text in texts) {
      for (final RegExpMatch match in _urlPattern.allMatches(text)) {
        final String url = _normalizeDetectedUrl(match.group(0) ?? '');
        if (url.isEmpty) {
          continue;
        }

        if (ndgrViewUri == null &&
            (url.startsWith('http://') || url.startsWith('https://')) &&
            url.contains('/api/view/v4/')) {
          ndgrViewUri = url;
          continue;
        }

        if (legacyWebSocketUrl == null && url.startsWith('wss://')) {
          legacyWebSocketUrl = url;
        }
      }
    }

    return SessionEndpointResolution(
      ndgrViewUri: ndgrViewUri,
      legacyWebSocketUrl: legacyWebSocketUrl,
    );
  }

  static BroadcastEndDetection detectBroadcastEnd(Map<String, dynamic> json) {
    final String type = json['type']?.toString() ?? '';
    if (type.toLowerCase() != 'disconnect') {
      return BroadcastEndDetection.none;
    }

    final String? reason = _extractDisconnectReason(json);
    if (reason == null) {
      return BroadcastEndDetection.unknown;
    }

    final String normalized = reason.toUpperCase();
    if (_knownBroadcastEndedReasons.contains(normalized)) {
      return BroadcastEndDetection.ended;
    }

    return BroadcastEndDetection.unknown;
  }

  static String? _extractDisconnectReason(Map<String, dynamic> json) {
    final Object? data = json['data'];
    if (data is Map<String, dynamic>) {
      final Object? reason = data['reason'];
      if (reason != null) {
        return reason.toString();
      }
    }

    final Object? body = json['body'];
    if (body is Map<String, dynamic>) {
      final Object? reason = body['reason'];
      if (reason != null) {
        return reason.toString();
      }
    }

    final Object? reason = json['reason'];
    return reason?.toString();
  }

  static void _collectStrings(Object? value, List<String> out) {
    if (value == null) {
      return;
    }

    if (value is String) {
      out.add(value);
      return;
    }

    if (value is Map<String, dynamic>) {
      value.forEach((String key, Object? nested) {
        _collectStrings(nested, out);
      });
      return;
    }

    if (value is List<Object?>) {
      for (final Object? nested in value) {
        _collectStrings(nested, out);
      }
      return;
    }

    if (value is Map) {
      value.forEach((Object? key, Object? nested) {
        _collectStrings(nested, out);
      });
      return;
    }

    if (value is List) {
      for (final Object? nested in value) {
        _collectStrings(nested, out);
      }
    }
  }

  static String _normalizeDetectedUrl(String url) {
    return url.replaceAll(RegExp('["\\\'\\],}]+\$'), '');
  }
}

class SessionWsLogSanitizer {
  static final RegExp _sensitiveKeyPattern = RegExp(
    r'(token|cookie|session|auth|credential|secret|password)',
    caseSensitive: false,
  );

  static final RegExp _urlPattern = RegExp(
    r'((?:https?|wss):\/\/[^\s<>]+)',
    caseSensitive: false,
  );

  static String sanitizeRawJson(String rawJson) {
    try {
      final Object? decoded = jsonDecode(rawJson);
      final Object? masked = _maskValue(decoded);
      return jsonEncode(masked);
    } catch (_) {
      return _sanitizeString(rawJson);
    }
  }

  static Object? _maskValue(Object? value) {
    if (value is Map<String, dynamic>) {
      final Map<String, Object?> masked = <String, Object?>{};
      value.forEach((String key, Object? nested) {
        if (_isSensitiveKey(key)) {
          masked[key] = '***';
        } else {
          masked[key] = _maskValue(nested);
        }
      });
      return masked;
    }

    if (value is List) {
      return value
          .map<Object?>((Object? nested) => _maskValue(nested))
          .toList();
    }

    if (value is String) {
      if (_isUrlValue(value)) {
        return _stripUrlQuery(value);
      }
      return _sanitizeString(value);
    }

    if (value is Map) {
      final Map<String, Object?> masked = <String, Object?>{};
      value.forEach((Object? key, Object? nested) {
        final String keyText = key?.toString() ?? '';
        if (_isSensitiveKey(keyText)) {
          masked[keyText] = '***';
        } else {
          masked[keyText] = _maskValue(nested);
        }
      });
      return masked;
    }

    return value;
  }

  static bool _isSensitiveKey(String key) {
    return _sensitiveKeyPattern.hasMatch(key);
  }

  static bool _isUrlValue(String value) {
    final String trimmed = value.trim();
    final Match? match = _urlPattern.matchAsPrefix(trimmed);
    return match != null && match.end == trimmed.length;
  }

  static String _sanitizeString(String input) {
    final String withoutQuery = input.replaceAllMapped(_urlPattern, (Match m) {
      final String original = m.group(0) ?? '';
      return _stripUrlQuery(original);
    });

    if (withoutQuery.length >= 40) {
      return '${withoutQuery.substring(0, 40)}…';
    }
    return withoutQuery;
  }

  static String _stripUrlQuery(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return url;
    }

    if (uri.hasPort) {
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
      ).toString();
    }

    return Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString();
  }
}
