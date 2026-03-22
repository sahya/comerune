import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_message.dart';
import 'ndgr_message_normalizer.dart';
import 'ndgr_protobuf_decoder.dart';
import 'ndgr_stall_detector.dart';

enum NdgrClientEventType {
  message,
  stalled,
  error,
}

class NdgrClientEvent {
  const NdgrClientEvent._({
    required this.type,
    this.message,
    this.stallDuration,
    this.error,
    this.stackTrace,
  });

  const NdgrClientEvent.message(AppMessage message)
    : this._(type: NdgrClientEventType.message, message: message);

  const NdgrClientEvent.stalled(Duration stallDuration)
    : this._(
        type: NdgrClientEventType.stalled,
        stallDuration: stallDuration,
      );

  const NdgrClientEvent.error(Object error, StackTrace stackTrace)
    : this._(
        type: NdgrClientEventType.error,
        error: error,
        stackTrace: stackTrace,
      );

  final NdgrClientEventType type;
  final AppMessage? message;
  final Duration? stallDuration;
  final Object? error;
  final StackTrace? stackTrace;
}

class NdgrClient {
  NdgrClient({
    HttpClient? httpClient,
    NdgrProtobufDecoder? protobufDecoder,
    NdgrMessageNormalizer? normalizer,
    Duration stallThreshold = const Duration(seconds: 15),
    Duration stallCheckInterval = const Duration(seconds: 1),
    Duration backwardSegmentInterval = const Duration(milliseconds: 7),
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null,
       _protobufDecoder = protobufDecoder ?? NdgrProtobufDecoder(),
       _normalizer = normalizer ?? NdgrMessageNormalizer(),
       _stallDetector = NdgrStallDetector(
         threshold: stallThreshold,
         now: now,
       ),
       _now = now ?? DateTime.now,
       _stallCheckInterval = stallCheckInterval,
       _backwardSegmentInterval = backwardSegmentInterval;

  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final NdgrProtobufDecoder _protobufDecoder;
  final NdgrMessageNormalizer _normalizer;
  final NdgrStallDetector _stallDetector;
  final DateTime Function() _now;
  final Duration _stallCheckInterval;
  final Duration _backwardSegmentInterval;

  final StreamController<NdgrClientEvent> _eventsController =
      StreamController<NdgrClientEvent>.broadcast();

  Timer? _stallTimer;
  bool _isRunning = false;
  bool _isStopped = false;

  Stream<NdgrClientEvent> get events => _eventsController.stream;

  bool get isRunning => _isRunning;

  Future<void> connect(
    Uri viewApiUri, {
    int historyCount = 100,
    Object at = 'now',
  }) async {
    if (_isRunning) {
      throw StateError('NdgrClient is already running');
    }
    if (historyCount < 0) {
      throw ArgumentError.value(historyCount, 'historyCount', 'must be >= 0');
    }

    _isRunning = true;
    _isStopped = false;
    _startStallTimer();

    try {
      await _runHeadLoop(
        viewApiUri,
        historyCount: historyCount,
        at: at,
      );
    } catch (error, stackTrace) {
      _emitError(error, stackTrace);
      rethrow;
    } finally {
      _stopStallTimer();
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    _isStopped = true;
    _stopStallTimer();
  }

  void dispose() {
    _isStopped = true;
    _stopStallTimer();

    if (_ownsHttpClient) {
      _httpClient.close(force: true);
    }

    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }

  Future<void> _runHeadLoop(
    Uri viewApiUri, {
    required int historyCount,
    required Object at,
  }) async {
    Object? nextAt = at;
    bool initPhase = true;

    while (!_isStopped && nextAt != null) {
      final Uri fetchUri = _uriWithAt(viewApiUri, nextAt);
      nextAt = null;

      await for (final NdgrChunkedEntry entry in _streamChunkedEntries(fetchUri)) {
        if (_isStopped) {
          return;
        }

        if (entry.backwardSegmentUri != null) {
          if (initPhase && historyCount > 0) {
            final List<NdgrChunkedMessage> backwards = await _pullBackwards(
              Uri.parse(entry.backwardSegmentUri!),
              historyCount,
            );
            for (final NdgrChunkedMessage message in backwards) {
              _handleChunkedMessage(message);
            }
          }
          continue;
        }

        if (entry.previousUri != null) {
          if (initPhase) {
            await _retrieveMessages(Uri.parse(entry.previousUri!));
          }
          continue;
        }

        if (entry.segmentUri != null) {
          initPhase = false;
          await _retrieveMessages(Uri.parse(entry.segmentUri!));
          continue;
        }

        if (entry.nextAt != null) {
          nextAt = entry.nextAt;
        }
      }
    }
  }

  Future<List<NdgrChunkedMessage>> _pullBackwards(Uri fetchUri, int want) async {
    if (want == 0) {
      return const <NdgrChunkedMessage>[];
    }

    final List<List<NdgrChunkedMessage>> buffer = <List<NdgrChunkedMessage>>[];
    int length = 0;
    Uri? current = fetchUri;

    while (!_isStopped && current != null && length < want) {
      final HttpClientResponse response = await _fetch(current, phase: 'backward');
      final Uint8List bytes = await _readAllBytes(response);

      final NdgrPackedSegment packed = _protobufDecoder.decodePackedSegment(bytes);
      buffer.insert(0, packed.messages);
      length += packed.messages.length;

      if (packed.nextUri == null) {
        break;
      }

      await Future<void>.delayed(_backwardSegmentInterval);
      current = Uri.parse(packed.nextUri!);
    }

    final List<NdgrChunkedMessage> flattened =
        buffer.expand((List<NdgrChunkedMessage> messages) => messages).toList();

    if (flattened.length <= want) {
      return flattened;
    }

    return flattened.sublist(flattened.length - want);
  }

  Future<void> _retrieveMessages(Uri uri) async {
    await for (final NdgrChunkedMessage message in _streamChunkedMessages(uri)) {
      if (_isStopped) {
        return;
      }
      _handleChunkedMessage(message);
    }
  }

  void _handleChunkedMessage(NdgrChunkedMessage message) {
    _stallDetector.markReceived(_now());

    final AppMessage? normalized = _normalizer.normalizeChunkedMessage(
      message,
      receivedAt: _now().toUtc(),
    );

    if (normalized != null) {
      _eventsController.add(NdgrClientEvent.message(normalized));
    }
  }

  Stream<NdgrChunkedEntry> _streamChunkedEntries(Uri uri) async* {
    final HttpClientResponse response = await _fetch(uri, phase: 'head');
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          _stallDetector.markReceived(_now());
          yield _protobufDecoder.decodeChunkedEntry(frame);
        } catch (error, stackTrace) {
          log(
            'Failed to decode NDGR ChunkedEntry frame. Skip frame.',
            name: 'NdgrClient',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    if (decoder.fragmentRestoreCount > 0) {
      log(
        'NDGR fragment restored ${decoder.fragmentRestoreCount} times (head).',
        name: 'NdgrClient',
      );
    }
    decoder.clear();
  }

  Stream<NdgrChunkedMessage> _streamChunkedMessages(Uri uri) async* {
    final HttpClientResponse response = await _fetch(uri, phase: 'segment');
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          yield _protobufDecoder.decodeChunkedMessage(frame);
        } catch (error, stackTrace) {
          log(
            'Failed to decode NDGR ChunkedMessage frame. Skip frame.',
            name: 'NdgrClient',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    if (decoder.fragmentRestoreCount > 0) {
      log(
        'NDGR fragment restored ${decoder.fragmentRestoreCount} times (segment).',
        name: 'NdgrClient',
      );
    }
    decoder.clear();
  }

  Future<HttpClientResponse> _fetch(Uri uri, {required String phase}) async {
    final HttpClientRequest request = await _httpClient.getUrl(uri);
    final HttpClientResponse response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'NDGR $phase request failed with status ${response.statusCode}',
        uri: uri,
      );
    }

    return response;
  }

  Uri _uriWithAt(Uri baseUri, Object at) {
    final Map<String, String> query = Map<String, String>.from(
      baseUri.queryParameters,
    );
    query['at'] = at.toString();
    return baseUri.replace(queryParameters: query);
  }

  Future<Uint8List> _readAllBytes(HttpClientResponse response) async {
    final BytesBuilder bytesBuilder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      bytesBuilder.add(chunk);
    }
    return bytesBuilder.toBytes();
  }

  void _startStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(_stallCheckInterval, (_) {
      if (_isStopped || !_isRunning) {
        return;
      }

      if (_stallDetector.shouldNotifyStall()) {
        final Duration elapsed = _stallDetector.elapsedSinceLastReceived()!;
        _eventsController.add(NdgrClientEvent.stalled(elapsed));
      }
    });
  }

  void _stopStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _emitError(Object error, StackTrace stackTrace) {
    log(
      'NDGR client error',
      name: 'NdgrClient',
      error: error,
      stackTrace: stackTrace,
    );
    if (!_eventsController.isClosed) {
      _eventsController.add(NdgrClientEvent.error(error, stackTrace));
    }
  }
}
