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
    BouyomiEncodingResolver? encodingResolver,
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

  Uint8List _encodeMessage(String text, BouyomiCharset charset) {
    switch (charset) {
      case BouyomiCharset.utf8:
        return Uint8List.fromList(utf8.encode(text));
      case BouyomiCharset.unicode:
        return _encodeUtf16Le(text);
      case BouyomiCharset.shiftJis:
        return _encodeShiftJis(text);
    }
  }

  Uint8List _encodeShiftJis(String text) {
    final Encoding? shiftJisEncoding = _resolveShiftJisEncoding();
    if (shiftJisEncoding != null) {
      return Uint8List.fromList(shiftJisEncoding.encode(text));
    }

    // Fallback for runtimes where Shift-JIS codec is unavailable.
    // Unsupported characters are replaced with '?' to avoid dropping utterances.
    final List<int> bytes = <int>[];
    for (final int rune in text.runes) {
      bytes.addAll(_encodeShiftJisRuneOrFallback(rune));
    }
    return Uint8List.fromList(bytes);
  }

  List<int> _encodeShiftJisRuneOrFallback(int rune) {
    final List<int>? encoded = _encodeShiftJisRune(rune);
    return encoded ?? const <int>[0x3F];
  }

  List<int>? _encodeShiftJisRune(int rune) {
    if (rune <= 0x7F) {
      return <int>[rune];
    }

    if (rune >= 0xFF61 && rune <= 0xFF9F) {
      return <int>[0xA1 + (rune - 0xFF61)];
    }

    if (rune >= 0x3041 && rune <= 0x3093) {
      return <int>[0x82, 0x9F + (rune - 0x3041)];
    }

    if (rune >= 0x30A1 && rune <= 0x30F6) {
      int second = 0x40 + (rune - 0x30A1);
      if (second >= 0x7F) {
        second += 1;
      }
      return <int>[0x83, second];
    }

    if (rune >= 0xFF10 && rune <= 0xFF19) {
      return <int>[0x82, 0x4F + (rune - 0xFF10)];
    }

    if (rune >= 0xFF21 && rune <= 0xFF3A) {
      return <int>[0x82, 0x60 + (rune - 0xFF21)];
    }

    if (rune >= 0xFF41 && rune <= 0xFF5A) {
      return <int>[0x82, 0x81 + (rune - 0xFF41)];
    }

    switch (rune) {
      case 0x00A5:
        return const <int>[0x5C];
      case 0x203E:
        return const <int>[0x7E];
      case 0x3000:
        return const <int>[0x81, 0x40];
      case 0x3001:
        return const <int>[0x81, 0x41];
      case 0x3002:
        return const <int>[0x81, 0x42];
      case 0x30FB:
        return const <int>[0x81, 0x45];
      case 0x30FC:
        return const <int>[0x81, 0x5B];
      case 0x309B:
        return const <int>[0x81, 0x4A];
      case 0x309C:
        return const <int>[0x81, 0x4B];
      case 0xFF01:
        return const <int>[0x81, 0x49];
      case 0xFF0C:
        return const <int>[0x81, 0x43];
      case 0xFF0E:
        return const <int>[0x81, 0x44];
      case 0xFF1A:
        return const <int>[0x81, 0x46];
      case 0xFF1B:
        return const <int>[0x81, 0x47];
      case 0xFF1F:
        return const <int>[0x81, 0x48];
      default:
        return null;
    }
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
