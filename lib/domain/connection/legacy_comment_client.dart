import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import '../models/app_message.dart';
import '../normalization/message_normalizer.dart';

abstract interface class LegacyWebSocket {
  Stream<Object?> get stream;

  Future<void> close([int? code, String? reason]);
}

typedef LegacyWebSocketConnector = Future<LegacyWebSocket> Function(String url);

enum LegacyCommentClientErrorCode {
  connectionFailed,
  disconnected,
  streamError,
}

class LegacyCommentClientError {
  const LegacyCommentClientError({required this.code, this.cause});

  final LegacyCommentClientErrorCode code;
  final Object? cause;
}

class LegacyCommentClient {
  LegacyCommentClient({
    required LegacyWebSocketConnector webSocketConnector,
    MessageNormalizer? messageNormalizer,
  })  : _messageNormalizer = messageNormalizer ?? MessageNormalizer(),
        _webSocketConnector = webSocketConnector;

  final MessageNormalizer _messageNormalizer;
  final LegacyWebSocketConnector _webSocketConnector;

  final StreamController<AppMessage> _messages =
      StreamController<AppMessage>.broadcast();
  final StreamController<LegacyCommentClientError> _errors =
      StreamController<LegacyCommentClientError>.broadcast();

  StreamSubscription<Object?>? _socketSubscription;
  LegacyWebSocket? _webSocket;
  bool _disconnecting = false;

  Stream<AppMessage> get messages => _messages.stream;
  Stream<LegacyCommentClientError> get errors => _errors.stream;

  Future<void> connect(String legacyWsUrl) async {
    await disconnect();

    try {
      _webSocket = await _webSocketConnector(legacyWsUrl);
    } catch (error, stackTrace) {
      log(
        'Failed to connect to legacy websocket. url=${_sanitizeUrlForLog(legacyWsUrl)}',
        name: 'LegacyCommentClient',
        error: error,
        stackTrace: stackTrace,
      );
      _emitError(
        LegacyCommentClientError(
          code: LegacyCommentClientErrorCode.connectionFailed,
          cause: error,
        ),
      );
      return;
    }

    _socketSubscription = _webSocket!.stream.listen(
      _onSocketData,
      onError: _onSocketError,
      onDone: _onSocketDone,
      cancelOnError: false,
    );
  }

  Future<void> disconnect() async {
    final StreamSubscription<Object?>? subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    final LegacyWebSocket? socket = _webSocket;
    _webSocket = null;
    if (socket != null) {
      _disconnecting = true;
      try {
        await socket.close();
      } finally {
        _disconnecting = false;
      }
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _errors.close();
  }

  void _onSocketData(Object? event) {
    final String? rawJson = _toText(event);
    if (rawJson == null) {
      log(
        'Ignored non-text legacy payload type: ${event.runtimeType}',
        name: 'LegacyCommentClient',
      );
      return;
    }

    final AppMessage? normalized =
        _messageNormalizer.normalizeLegacyJson(rawJson);
    if (normalized != null && !_messages.isClosed) {
      _messages.add(normalized);
    }
  }

  void _onSocketError(Object error, StackTrace stackTrace) {
    log(
      'Legacy websocket stream error.',
      name: 'LegacyCommentClient',
      error: error,
      stackTrace: stackTrace,
    );

    _emitError(
      LegacyCommentClientError(
        code: LegacyCommentClientErrorCode.streamError,
        cause: error,
      ),
    );
  }

  void _onSocketDone() {
    if (_disconnecting) {
      return;
    }

    _emitError(
      const LegacyCommentClientError(
        code: LegacyCommentClientErrorCode.disconnected,
      ),
    );
  }

  String? _toText(Object? event) {
    if (event is String) {
      return event;
    }
    if (event is List<int>) {
      return utf8.decode(event, allowMalformed: true);
    }
    return null;
  }

  void _emitError(LegacyCommentClientError error) {
    if (_errors.isClosed) {
      return;
    }
    _errors.add(error);
  }

  String _sanitizeUrlForLog(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return _truncateForLog(url);
    }

    final Uri sanitized = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    return sanitized.toString();
  }

  String _truncateForLog(String value) {
    if (value.length <= 120) {
      return value;
    }
    return '${value.substring(0, 120)}...';
  }
}
