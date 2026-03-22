import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../../lib/domain/speech/bouyomi_engine.dart';

void main() {
  group('BouyomiPacketBuilder', () {
    test('builds 15-byte little-endian header with signed values', () {
      final Uint8List header = BouyomiPacketBuilder.buildHeader(
        speed: -1,
        tone: 120,
        volume: 80,
        voice: 2,
        charset: BouyomiCharset.unicode,
        messageLength: 256,
      );

      expect(header.length, BouyomiPacketBuilder.headerLength);
      final ByteData data = ByteData.sublistView(header);
      expect(
          data.getInt16(0, Endian.little), BouyomiPacketBuilder.commandSpeak);
      expect(data.getInt16(2, Endian.little), -1);
      expect(data.getInt16(4, Endian.little), 120);
      expect(data.getInt16(6, Endian.little), 80);
      expect(data.getInt16(8, Endian.little), 2);
      expect(data.getInt8(10), BouyomiCharset.unicode.code);
      expect(data.getInt32(11, Endian.little), 256);
    });
  });

  group('BouyomiEngine', () {
    test('sends packet with configured parameters to fixed port 50001',
        () async {
      final _FakeConnection connection = _FakeConnection();
      String? calledHost;
      int? calledPort;

      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(
          host: '192.168.0.10',
          speed: 150,
          tone: 90,
          volume: 70,
          voice: 4,
          charset: BouyomiCharset.utf8,
        ),
        connectionOpener: (String host, int port, Duration timeout) async {
          calledHost = host;
          calledPort = port;
          return connection;
        },
      );

      await engine.speak('テスト');

      expect(calledHost, '192.168.0.10');
      expect(calledPort, BouyomiEngine.defaultPort);
      expect(connection.flushed, isTrue);
      expect(connection.closed, isTrue);

      final Uint8List allBytes = Uint8List.fromList(connection.sentBytes);
      final Uint8List header =
          allBytes.sublist(0, BouyomiPacketBuilder.headerLength);
      final Uint8List body =
          allBytes.sublist(BouyomiPacketBuilder.headerLength);
      final ByteData headerData = ByteData.sublistView(header);

      expect(headerData.getInt16(2, Endian.little), 150);
      expect(headerData.getInt16(4, Endian.little), 90);
      expect(headerData.getInt16(6, Endian.little), 70);
      expect(headerData.getInt16(8, Endian.little), 4);
      expect(headerData.getInt8(10), BouyomiCharset.utf8.code);
      expect(headerData.getInt32(11, Endian.little), body.length);
      expect(utf8.decode(body), 'テスト');
    });

    test('applies unicode charset and sends UTF-16LE payload length', () async {
      final _FakeConnection connection = _FakeConnection();

      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(
          host: 'localhost',
          charset: BouyomiCharset.unicode,
        ),
        connectionOpener: (String host, int port, Duration timeout) async =>
            connection,
      );

      await engine.speak('Aあ');

      final Uint8List allBytes = Uint8List.fromList(connection.sentBytes);
      final Uint8List header =
          allBytes.sublist(0, BouyomiPacketBuilder.headerLength);
      final Uint8List body =
          allBytes.sublist(BouyomiPacketBuilder.headerLength);
      final ByteData headerData = ByteData.sublistView(header);

      expect(headerData.getInt8(10), BouyomiCharset.unicode.code);
      expect(headerData.getInt32(11, Endian.little), body.length);
      expect(body.length, 4);
      expect(body, <int>[0x41, 0x00, 0x42, 0x30]);
    });

    test('applies shift-jis charset with deterministic bytes', () async {
      final _FakeConnection connection = _FakeConnection();

      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(
          host: 'localhost',
          charset: BouyomiCharset.shiftJis,
        ),
        encodingResolver: (String name) => null,
        connectionOpener: (String host, int port, Duration timeout) async =>
            connection,
      );

      await engine.speak('ABCあア');

      final Uint8List allBytes = Uint8List.fromList(connection.sentBytes);
      final Uint8List header =
          allBytes.sublist(0, BouyomiPacketBuilder.headerLength);
      final Uint8List body =
          allBytes.sublist(BouyomiPacketBuilder.headerLength);
      final ByteData headerData = ByteData.sublistView(header);

      expect(headerData.getInt8(10), BouyomiCharset.shiftJis.code);
      expect(headerData.getInt32(11, Endian.little), body.length);
      expect(body, <int>[0x41, 0x42, 0x43, 0x82, 0xA0, 0x83, 0x41]);
    });

    test('skips utterance when socket connection fails', () async {
      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(host: '127.0.0.1'),
        connectionOpener: (String host, int port, Duration timeout) async {
          throw const SocketException('connect failed');
        },
      );

      await expectLater(engine.speak('hello'), completes);
    });

    test('skips utterance when socket connect times out', () async {
      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(host: '127.0.0.1'),
        connectionOpener: (String host, int port, Duration timeout) async =>
            throw TimeoutException('connect timed out'),
      );

      await expectLater(engine.speak('hello'), completes);
    });

    test('skips utterance when socket write times out', () async {
      final _FakeConnection connection = _FakeConnection(
        onFlush: () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        },
      );

      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(host: '127.0.0.1'),
        writeTimeout: const Duration(milliseconds: 1),
        connectionOpener: (String host, int port, Duration timeout) async =>
            connection,
      );

      await expectLater(engine.speak('hello'), completes);
      expect(connection.closed, isTrue);
    });

    test('encodes kanji in shift-jis fallback map', () async {
      final _FakeConnection connection = _FakeConnection();
      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(
          host: '127.0.0.1',
          charset: BouyomiCharset.shiftJis,
        ),
        encodingResolver: (String name) => null,
        connectionOpener: (String host, int port, Duration timeout) async =>
            connection,
      );

      await engine.speak('漢A');
      final Uint8List allBytes = Uint8List.fromList(connection.sentBytes);
      final Uint8List body =
          allBytes.sublist(BouyomiPacketBuilder.headerLength);
      expect(body, <int>[0x8A, 0xBF, 0x41]);
    });

    test('replaces unsupported shift-jis characters with question mark',
        () async {
      final _FakeConnection connection = _FakeConnection();
      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(
          host: '127.0.0.1',
          charset: BouyomiCharset.shiftJis,
        ),
        encodingResolver: (String name) => null,
        connectionOpener: (String host, int port, Duration timeout) async =>
            connection,
      );

      await engine.speak('😀A');
      final Uint8List allBytes = Uint8List.fromList(connection.sentBytes);
      final Uint8List body =
          allBytes.sublist(BouyomiPacketBuilder.headerLength);
      expect(body, <int>[0x3F, 0x41]);
    });

    test('skips utterance when an unexpected error occurs', () async {
      final BouyomiEngine engine = BouyomiEngine(
        settingsProvider: () => const BouyomiSettings(host: '127.0.0.1'),
        connectionOpener: (String host, int port, Duration timeout) async {
          throw StateError('unexpected failure');
        },
      );

      await expectLater(engine.speak('hello'), completes);
    });
  });
}

class _FakeConnection implements BouyomiConnection {
  _FakeConnection({
    this.onFlush,
  });

  final Future<void> Function()? onFlush;
  final List<int> sentBytes = <int>[];
  bool flushed = false;
  bool closed = false;

  @override
  void add(List<int> data) {
    sentBytes.addAll(data);
  }

  @override
  Future<void> flush() async {
    flushed = true;
    if (onFlush != null) {
      await onFlush!();
    }
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
