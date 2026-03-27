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
typedef BouyomiEncodingResolver = Encoding? Function(String name);

class BouyomiPacketBuilder {
  static const int commandSpeak = 1;
  static const int headerLength = 15;

  static Uint8List buildHeader({
    required int speed,
    required int tone,
    required int volume,
    required int voice,
    required BouyomiCharset charset,
    required int messageLength,
  }) {
    final ByteData data = ByteData(headerLength);
    data.setInt16(0, commandSpeak, Endian.little);
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
    BouyomiEncodingResolver? encodingResolver,
    // TODO(PR#25-optional): Consider increasing default timeout (for example,
    //  3s) for unstable Wi-Fi environments.
    Duration connectTimeout = const Duration(seconds: 1),
    Duration writeTimeout = const Duration(seconds: 1),
  })  : _settingsProvider = settingsProvider,
        _connectionOpener = connectionOpener ?? _defaultConnectionOpener,
        _encodingResolver = encodingResolver ?? Encoding.getByName,
        _connectTimeout = connectTimeout,
        _writeTimeout = writeTimeout;

  final BouyomiSettingsProvider _settingsProvider;
  final BouyomiConnectionOpener _connectionOpener;
  final BouyomiEncodingResolver _encodingResolver;
  final Duration _connectTimeout;
  final Duration _writeTimeout;

  @override
  Future<void> speak(String text) async {
    final BouyomiSettings settings = _settingsProvider();
    final String host = settings.host.trim();
    if (text.isEmpty) {
      return;
    }
    if (host.isEmpty) {
      // TODO(PR#25-optional): Revisit wording as developer-focused log text.
      _logInfo('Skipping utterance: Host is empty. Check settings.');
      return;
    }

    BouyomiConnection? connection;
    try {
      final _EncodedMessage encodedMessage =
          _encodeMessage(text, settings.charset);
      final Uint8List header = BouyomiPacketBuilder.buildHeader(
        speed: settings.speed,
        tone: settings.tone,
        volume: settings.volume,
        voice: settings.voice,
        charset: encodedMessage.charset,
        messageLength: encodedMessage.bytes.length,
      );
      connection = await _connectionOpener(host, defaultPort, _connectTimeout);
      connection.add(header);
      connection.add(encodedMessage.bytes);
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
    } on Exception catch (error, stackTrace) {
      _logSkip('Unexpected speech error.', error, stackTrace);
    } finally {
      if (connection != null) {
        try {
          // TODO(PR#25-optional): _writeTimeout is also used for close. Consider
          //  renaming this field to a generic I/O timeout in a follow-up.
          await connection.close().timeout(_writeTimeout);
        } on Exception catch (_) {
          // Ignore close failures. The utterance has already been skipped.
        }
      }
    }
  }

  @override
  Future<void> stop() async {
    // Bouyomi uses one connection per utterance and keeps no persistent stream.
  }

  static Future<BouyomiConnection> _defaultConnectionOpener(
    String host,
    int port,
    Duration timeout,
  ) async {
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    return _SocketBouyomiConnection(socket);
  }

  _EncodedMessage _encodeMessage(String text, BouyomiCharset charset) {
    switch (charset) {
      case BouyomiCharset.utf8:
        return _EncodedMessage(
          bytes: Uint8List.fromList(utf8.encode(text)),
          charset: BouyomiCharset.utf8,
        );
      case BouyomiCharset.unicode:
        return _EncodedMessage(
          bytes: _encodeUtf16Le(text),
          charset: BouyomiCharset.unicode,
        );
      case BouyomiCharset.shiftJis:
        return _encodeShiftJis(text);
    }
  }

  _EncodedMessage _encodeShiftJis(String text) {
    final Encoding? shiftJisEncoding = _resolveShiftJisEncoding();
    if (shiftJisEncoding != null) {
      return _EncodedMessage(
        bytes: Uint8List.fromList(shiftJisEncoding.encode(text)),
        charset: BouyomiCharset.shiftJis,
      );
    }

    _logInfo('Shift-JIS codec unavailable, falling back to UTF-8.');
    return _EncodedMessage(
      bytes: Uint8List.fromList(utf8.encode(text)),
      charset: BouyomiCharset.utf8,
    );
  }

  Encoding? _resolveShiftJisEncoding() {
    return _encodingResolver('shift_jis') ??
        _encodingResolver('shift-jis') ??
        _encodingResolver('sjis') ??
        _encodingResolver('cp932') ??
        _encodingResolver('windows-31j');
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

  void _logInfo(String message) {
    log(
      message,
      name: 'BouyomiEngine',
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

class _EncodedMessage {
  const _EncodedMessage({
    required this.bytes,
    required this.charset,
  });

  final Uint8List bytes;
  final BouyomiCharset charset;
}
