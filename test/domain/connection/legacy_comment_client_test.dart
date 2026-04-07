import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/domain/connection/legacy_comment_client.dart';
import 'package:comerune/domain/models/app_message.dart';
import 'package:comerune/domain/normalization/message_normalizer.dart';

void main() {
  group('LegacyCommentClient', () {
    test('connects and emits normalized legacy chat message', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();

      String? connectedUrl;
      final LegacyCommentClient client = LegacyCommentClient(
        messageNormalizer: MessageNormalizer(
          idGenerator: _sequentialIdGenerator(),
        ),
        webSocketConnector: (String url) async {
          connectedUrl = url;
          return fakeSocket;
        },
      );

      final Future<AppMessage> firstMessage = client.messages.first;
      await client.connect('wss://legacy.example/ws');

      fakeSocket.add(_legacyFixture('chat_message.json'));

      final AppMessage message = await firstMessage;
      expect(connectedUrl, 'wss://legacy.example/ws');
      expect(message.id, 'legacy-1');
      expect(message.type, AppMessageType.chat);
      expect(message.content, 'hello');
      expect(message.userId, 'user-1');

      await client.dispose();
    });

    test('decodes List<int> websocket payload', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();

      final LegacyCommentClient client = LegacyCommentClient(
        messageNormalizer: MessageNormalizer(
          idGenerator: _sequentialIdGenerator(),
        ),
        webSocketConnector: (_) async => fakeSocket,
      );

      final Future<AppMessage> firstMessage = client.messages.first;
      await client.connect('wss://legacy.example/ws');

      fakeSocket.add(utf8.encode(_legacyFixture('chat_message_binary.json')));

      final AppMessage message = await firstMessage;
      expect(message.type, AppMessageType.chat);
      expect(message.content, 'hello-binary');
      expect(message.userId, 'user-2');

      await client.dispose();
    });

    test('skips invalid JSON payload without emitting message', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();
      final LegacyCommentClient client = LegacyCommentClient(
        messageNormalizer: MessageNormalizer(
          idGenerator: _sequentialIdGenerator(),
        ),
        webSocketConnector: (_) async => fakeSocket,
      );

      final List<AppMessage> emitted = <AppMessage>[];
      final StreamSubscription<AppMessage> subscription =
          client.messages.listen(emitted.add);

      await client.connect('wss://legacy.example/ws');
      fakeSocket.add(_legacyFixture('invalid_json.txt'));
      await _flushEvents();

      expect(emitted, isEmpty);

      await subscription.cancel();
      await client.dispose();
    });

    test('emits unsupported-format message when chat key is missing', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();
      final LegacyCommentClient client = LegacyCommentClient(
        messageNormalizer: MessageNormalizer(
          idGenerator: _sequentialIdGenerator(),
          clockNow: () => DateTime.parse('2026-03-22T00:00:00Z'),
        ),
        webSocketConnector: (_) async => fakeSocket,
      );

      final Future<AppMessage> firstMessage = client.messages.first;
      await client.connect('wss://legacy.example/ws');
      fakeSocket.add(_legacyFixture('unsupported_no_chat.json'));

      final AppMessage message = await firstMessage;
      expect(message.type, AppMessageType.notification);
      expect(message.content, kLegacyUnsupportedFormatContent);

      await client.dispose();
    });

    test('notifies disconnected error when websocket stream ends', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();
      final LegacyCommentClient client = LegacyCommentClient(
        webSocketConnector: (_) async => fakeSocket,
      );

      final Future<LegacyCommentClientError> firstError = client.errors.first;
      await client.connect('wss://legacy.example/ws');
      await fakeSocket.finish();

      final LegacyCommentClientError error = await firstError;
      expect(error.code, LegacyCommentClientErrorCode.disconnected);

      await client.dispose();
    });

    test('notifies streamError when websocket stream emits an error', () async {
      final _FakeLegacyWebSocket fakeSocket = _FakeLegacyWebSocket();
      final LegacyCommentClient client = LegacyCommentClient(
        webSocketConnector: (_) async => fakeSocket,
      );

      final Future<LegacyCommentClientError> firstError = client.errors.first;
      await client.connect('wss://legacy.example/ws');
      fakeSocket.addError(StateError('stream failed'));

      final LegacyCommentClientError error = await firstError;
      expect(error.code, LegacyCommentClientErrorCode.streamError);
      expect(error.cause, isA<StateError>());

      await client.dispose();
    });

    test(
      'notifies connectionFailed when websocket connection throws',
      () async {
        final LegacyCommentClient client = LegacyCommentClient(
          webSocketConnector: (_) async => throw StateError('connect failed'),
        );

        final Future<LegacyCommentClientError> firstError = client.errors.first;
        await client.connect('wss://legacy.example/ws');

        final LegacyCommentClientError error = await firstError;
        expect(error.code, LegacyCommentClientErrorCode.connectionFailed);
        expect(error.cause, isA<StateError>());

        await client.dispose();
      },
    );
  });
}

LegacyMessageIdGenerator _sequentialIdGenerator() {
  int sequence = 1;
  return () {
    final String id = 'legacy-$sequence';
    sequence += 1;
    return id;
  };
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

String _legacyFixture(String name) {
  final Uri fixtureUri = Directory.current.uri.resolve(
    'test/fixtures/legacy/$name',
  );
  return File.fromUri(fixtureUri).readAsStringSync();
}

class _FakeLegacyWebSocket implements LegacyWebSocket {
  final StreamController<Object?> _controller =
      StreamController<Object?>.broadcast();

  bool _closed = false;

  @override
  Stream<Object?> get stream => _controller.stream;

  void add(Object? event) {
    if (!_closed) {
      _controller.add(event);
    }
  }

  void addError(Object error) {
    if (!_closed) {
      _controller.addError(error);
    }
  }

  Future<void> finish() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _controller.close();
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await finish();
  }
}
