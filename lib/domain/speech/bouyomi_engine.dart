import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'speech_engine.dart';

enum BouyomiCharset {
  utf8(0),
  unicode(1),
  shiftJis(2);

  const BouyomiCharset(this.code);

  final int code;
}

class BouyomiSettings {
  const BouyomiSettings({
    required this.host,
    this.speed = -1,
    this.tone = -1,
    this.volume = -1,
    this.voice = 0,
    this.charset = BouyomiCharset.utf8,
  });

  final String host;
  final int speed;
  final int tone;
  final int volume;
  final int voice;
  final BouyomiCharset charset;
}

abstract class BouyomiConnection {
  void add(List<int> data);

  Future<void> flush();

  Future<void> close();
}

typedef BouyomiConnectionOpener = Future<BouyomiConnection> Function(
  String host,
  int port,
  Duration timeout,
);

typedef BouyomiSettingsProvider = BouyomiSettings Function();

class BouyomiPacketBuilder {
  static const int commandSpeak = 1;
  static const int headerLength = 15;

  static Uint8List buildHeader({
    int command = commandSpeak,
    required int speed,
    required int tone,
    required int volume,
    required int voice,
    required BouyomiCharset charset,
    required int messageLength,
  }) {
    final ByteData data = ByteData(headerLength);
    data.setInt16(0, command, Endian.little);
    data.setInt16(2, speed, Endian.little);
    data.setInt16(4, tone, Endian.little);
    data.setInt16(6, volume, Endian.little);
    data.setInt16(8, voice, Endian.little);
    data.setInt8(10, charset.code);
    data.setInt32(11, messageLength, Endian.little);
    return data.buffer.asUint8List();
  }
}

class BouyomiEngine implements SpeechEngine {
  static const int defaultPort = 50001;

  BouyomiEngine({
    required BouyomiSettingsProvider settingsProvider,
    BouyomiConnectionOpener? connectionOpener,
    Duration connectTimeout = const Duration(seconds: 1),
    Duration writeTimeout = const Duration(seconds: 1),
  })  : _settingsProvider = settingsProvider,
        _connectionOpener = connectionOpener ?? _defaultConnectionOpener,
        _connectTimeout = connectTimeout,
        _writeTimeout = writeTimeout;

  final BouyomiSettingsProvider _settingsProvider;
  final BouyomiConnectionOpener _connectionOpener;
  final Duration _connectTimeout;
  final Duration _writeTimeout;

  @override
  Future<void> speak(String text) async {
    final BouyomiSettings settings = _settingsProvider();
    final String host = settings.host.trim();
    if (host.isEmpty || text.isEmpty) {
      return;
    }

    BouyomiConnection? connection;
    try {
      final Uint8List messageBytes = _encodeMessage(text, settings.charset);
      final Uint8List header = BouyomiPacketBuilder.buildHeader(
        speed: settings.speed,
        tone: settings.tone,
        volume: settings.volume,
        voice: settings.voice,
        charset: settings.charset,
        messageLength: messageBytes.length,
      );
      connection = await _connectionOpener(host, defaultPort, _connectTimeout);
      connection.add(header);
      connection.add(messageBytes);
      await connection.flush().timeout(_writeTimeout);
    } on UnsupportedError catch (error, stackTrace) {
      _logSkip(
          'Unsupported charset: ${settings.charset.name}', error, stackTrace);
    } on SocketException catch (error, stackTrace) {
      _logSkip('Socket connection failed.', error, stackTrace);
    } on TimeoutException catch (error, stackTrace) {
      _logSkip('Socket operation timed out.', error, stackTrace);
    } on IOException catch (error, stackTrace) {
      _logSkip('Socket I/O failed.', error, stackTrace);
    } on Object catch (error, stackTrace) {
      _logSkip('Unexpected speech error.', error, stackTrace);
    } finally {
      if (connection != null) {
        try {
          await connection.close();
        } on Object catch (_) {
          // Ignore close failures. The utterance has already been skipped.
        }
      }
    }
  }

  static Future<BouyomiConnection> _defaultConnectionOpener(
    String host,
    int port,
    Duration timeout,
  ) async {
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    return _SocketBouyomiConnection(socket);
  }

  static Uint8List _encodeMessage(String text, BouyomiCharset charset) {
    switch (charset) {
      case BouyomiCharset.utf8:
        return Uint8List.fromList(utf8.encode(text));
      case BouyomiCharset.unicode:
        return _encodeUtf16Le(text);
      case BouyomiCharset.shiftJis:
        // TODO(issue-13): Add Shift-JIS encoding support once codec dependency policy is approved.
        throw UnsupportedError(
          'Shift-JIS encoding is not supported without external codec dependency.',
        );
    }
  }

  static Uint8List _encodeUtf16Le(String text) {
    final List<int> codeUnits = text.codeUnits;
    final ByteData data = ByteData(codeUnits.length * 2);
    for (int i = 0; i < codeUnits.length; i += 1) {
      data.setUint16(i * 2, codeUnits[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  void _logSkip(String message, Object error, StackTrace stackTrace) {
    log(
      'Skipping utterance: $message',
      name: 'BouyomiEngine',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _SocketBouyomiConnection implements BouyomiConnection {
  _SocketBouyomiConnection(this._socket);

  final Socket _socket;

  @override
  void add(List<int> data) {
    _socket.add(data);
  }

  @override
  Future<void> flush() {
    return _socket.flush();
  }

  @override
  Future<void> close() {
    return _socket.close();
  }
}
