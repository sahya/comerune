import 'dart:async';
import 'dart:convert';

import 'package:comerune/domain/connection/session_ws_client.dart';

/// In-memory [SessionWsChannel] for tests: records sent messages and lets a
/// test push server messages with [pushIncoming].
class FakeSessionWsChannel implements SessionWsChannel {
  FakeSessionWsChannel({
    this.failOnPong = false,
    this.failOnKeepSeat = false,
    this.failOnStartWatching = false,
    this.closeDelay = Duration.zero,
  }) : _incoming = StreamController<dynamic>(),
       _sink = FakeSessionWsSink() {
    _sink.onAdd = (dynamic data) {
      sentMessages.add(data);

      if (!failOnPong && !failOnKeepSeat && !failOnStartWatching) {
        return;
      }

      final Map<String, dynamic> decoded =
          jsonDecode(data as String) as Map<String, dynamic>;
      if (failOnStartWatching && decoded['type'] == 'startWatching') {
        throw StateError('startWatching send failed');
      }
      if (failOnPong && decoded['type'] == 'pong') {
        throw StateError('pong send failed');
      }
      if (failOnKeepSeat && decoded['type'] == 'keepSeat') {
        throw StateError('keepSeat send failed');
      }
    };
  }

  final bool failOnPong;
  final bool failOnKeepSeat;
  final bool failOnStartWatching;
  final Duration closeDelay;
  final StreamController<dynamic> _incoming;
  final FakeSessionWsSink _sink;
  final List<dynamic> sentMessages = <dynamic>[];
  int closeCount = 0;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  StreamSink<dynamic> get sink => _sink;

  void pushIncoming(dynamic data) {
    _incoming.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount += 1;
    if (closeDelay > Duration.zero) {
      await Future<void>.delayed(closeDelay);
    }
    await _sink.close();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

class FakeSessionWsSink implements StreamSink<dynamic> {
  void Function(dynamic data)? onAdd;
  final Completer<void> _done = Completer<void>();

  @override
  void add(dynamic data) {
    onAdd?.call(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    return stream.forEach(add);
  }

  @override
  Future<void> close() {
    if (!_done.isCompleted) {
      _done.complete();
    }
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
}
