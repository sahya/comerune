import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_message.dart';
import 'ndgr_message_normalizer.dart';
import 'ndgr_protobuf_decoder.dart';
import 'ndgr_stall_detector.dart';

enum NdgrClientEventType { connected, message, stalled, statistics }

class NdgrClientEvent {
  const NdgrClientEvent._({
    required this.type,
    this.message,
    this.stallDuration,
    this.viewerCount,
  });

  const NdgrClientEvent.connected()
    : this._(type: NdgrClientEventType.connected);

  const NdgrClientEvent.message(AppMessage message)
    : this._(type: NdgrClientEventType.message, message: message);

  const NdgrClientEvent.stalled(Duration stallDuration)
    : this._(type: NdgrClientEventType.stalled, stallDuration: stallDuration);

  const NdgrClientEvent.statistics({int? viewerCount})
    : this._(type: NdgrClientEventType.statistics, viewerCount: viewerCount);

  final NdgrClientEventType type;
  final AppMessage? message;
  final Duration? stallDuration;
  final int? viewerCount;
}

class NdgrAt {
  const NdgrAt._(this._queryValue);

  static const NdgrAt now = NdgrAt._('now');

  factory NdgrAt.timestamp(int unixTimeSeconds) {
    if (unixTimeSeconds < 0) {
      throw ArgumentError.value(
        unixTimeSeconds,
        'unixTimeSeconds',
        'must be >= 0',
      );
    }
    return NdgrAt._(unixTimeSeconds.toString());
  }

  final String _queryValue;

  String asQueryValue() => _queryValue;
}

class NdgrClient {
  NdgrClient({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    NdgrProtobufDecoder? protobufDecoder,
    NdgrMessageNormalizer? normalizer,
    Duration stallThreshold = const Duration(seconds: 15),
    Duration stallCheckInterval = const Duration(seconds: 1),
    Duration backwardSegmentInterval = const Duration(milliseconds: 7),
    Duration connectionTimeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _seedHttpClient = httpClient,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _protobufDecoder = protobufDecoder ?? NdgrProtobufDecoder(),
       _normalizer = normalizer ?? NdgrMessageNormalizer(),
       _stallDetector = NdgrStallDetector(threshold: stallThreshold, now: now),
       _now = now ?? DateTime.now,
       _stallCheckInterval = stallCheckInterval,
       _backwardSegmentInterval = backwardSegmentInterval,
       _connectionTimeout = connectionTimeout {
    if (connectionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectionTimeout,
        'connectionTimeout',
        'must be > Duration.zero',
      );
    }
  }

  final HttpClient Function() _httpClientFactory;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;
  final NdgrProtobufDecoder _protobufDecoder;
  final NdgrMessageNormalizer _normalizer;
  final NdgrStallDetector _stallDetector;
  final DateTime Function() _now;
  final Duration _stallCheckInterval;
  final Duration _backwardSegmentInterval;
  final Duration _connectionTimeout;

  final StreamController<NdgrClientEvent> _eventsController =
      StreamController<NdgrClientEvent>.broadcast();

  Timer? _stallTimer;
  bool _isRunning = false;
  bool _isStopped = false;
  bool _hasEmittedConnected = false;
  NdgrAt? _lastNextAt;

  Stream<NdgrClientEvent> get events => _eventsController.stream;

  bool get isRunning => _isRunning;
  NdgrAt? get lastNextAt => _lastNextAt;

  /// Connects to NDGR and streams comments.
  ///
  /// Failure is signaled only by this Future throwing.
  /// `events` stream emits `connected` / `message` / `stalled` events.
  Future<void> connect(
    Uri viewApiUri, {
    int historyCount = 100,
    NdgrAt at = NdgrAt.now,
  }) async {
    if (_isRunning) {
      throw StateError('NdgrClient is already running');
    }
    if (historyCount < 0) {
      throw ArgumentError.value(historyCount, 'historyCount', 'must be >= 0');
    }

    _isRunning = true;
    _isStopped = false;
    _hasEmittedConnected = false;
    _lastNextAt = at;
    _stopStallTimer();
    _stallDetector.reset();

    try {
      await _runHeadLoop(viewApiUri, historyCount: historyCount, at: at);
    } catch (error, stackTrace) {
      if (_isStopped) {
        return;
      }
      log(
        'NDGR client connect failed',
        name: 'NdgrClient',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _stopStallTimer();
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    _isStopped = true;
    _stopStallTimer();
    _abortActiveConnections();
  }

  void dispose() {
    _isStopped = true;
    _stopStallTimer();
    _abortActiveConnections();

    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }

  Future<void> _runHeadLoop(
    Uri viewApiUri, {
    required int historyCount,
    required NdgrAt at,
  }) async {
    NdgrAt? nextAt = at;
    bool initPhase = true;
    int remainingHistory = historyCount;

    while (!_isStopped && nextAt != null) {
      final Uri fetchUri = _uriWithAt(viewApiUri, nextAt);
      nextAt = null;

      await for (final NdgrChunkedEntry entry in _streamChunkedEntries(
        fetchUri,
      )) {
        if (_isStopped) {
          return;
        }

        if (entry.backwardSegmentUri != null) {
          if (initPhase && remainingHistory > 0) {
            final List<NdgrChunkedMessage> backwards = await _pullBackwards(
              Uri.parse(entry.backwardSegmentUri!),
              remainingHistory,
            );
            for (final NdgrChunkedMessage message in backwards) {
              final bool emitted = _handleChunkedMessage(message);
              if (emitted && remainingHistory > 0) {
                remainingHistory -= 1;
              }
            }
          }
          continue;
        }

        if (entry.previousUri != null) {
          if (initPhase && remainingHistory > 0) {
            final int emittedCount = await _retrieveMessages(
              Uri.parse(entry.previousUri!),
              limit: remainingHistory,
            );
            remainingHistory -= emittedCount;
          }
          continue;
        }

        if (entry.segmentUri != null) {
          initPhase = false;
          await _retrieveMessages(Uri.parse(entry.segmentUri!));
          continue;
        }

        if (entry.nextAt != null) {
          nextAt = NdgrAt.timestamp(entry.nextAt!);
          _lastNextAt = nextAt;
        }
      }
    }
  }

  Future<List<NdgrChunkedMessage>> _pullBackwards(
    Uri fetchUri,
    int want,
  ) async {
    if (want == 0) {
      return const <NdgrChunkedMessage>[];
    }

    final List<List<NdgrChunkedMessage>> buffer = <List<NdgrChunkedMessage>>[];
    int length = 0;
    Uri? current = fetchUri;

    while (!_isStopped && current != null && length < want) {
      final HttpClientResponse response = await _fetch(
        current,
        phase: 'backward',
      );
      final Uint8List bytes = await _readAllBytes(response);

      final NdgrPackedSegment packed = _protobufDecoder.decodePackedSegment(
        bytes,
      );
      buffer.insert(0, packed.messages);
      length += packed.messages.length;

      if (packed.nextUri == null) {
        break;
      }

      // Avoid hammering the backward endpoint with tight consecutive requests.
      await Future<void>.delayed(_backwardSegmentInterval);
      current = Uri.parse(packed.nextUri!);
    }

    final List<NdgrChunkedMessage> flattened = buffer
        .expand((List<NdgrChunkedMessage> messages) => messages)
        .toList();

    if (flattened.length <= want) {
      return flattened;
    }

    return flattened.sublist(flattened.length - want);
  }

  Future<int> _retrieveMessages(Uri uri, {int? limit}) async {
    int emittedCount = 0;

    await for (final NdgrChunkedMessage message in _streamChunkedMessages(
      uri,
    )) {
      if (_isStopped) {
        return emittedCount;
      }

      final bool emitted = _handleChunkedMessage(message);
      if (emitted) {
        emittedCount += 1;
      }

      if (limit != null && emittedCount >= limit) {
        break;
      }
    }

    return emittedCount;
  }

  bool _handleChunkedMessage(NdgrChunkedMessage message) {
    final DateTime receivedAt = _now();
    _markReceivedAndEnsureTimer(receivedAt);

    if (message.statistics != null) {
      _eventsController.add(
        NdgrClientEvent.statistics(viewerCount: message.statistics!.viewers),
      );
    }

    final AppMessage? normalized = _normalizer.normalizeChunkedMessage(
      message,
      receivedAt: receivedAt.toUtc(),
    );

    if (normalized != null) {
      _eventsController.add(NdgrClientEvent.message(normalized));
      return true;
    }

    return false;
  }

  Stream<NdgrChunkedEntry> _streamChunkedEntries(Uri uri) async* {
    final HttpClientResponse response = await _fetch(uri, phase: 'head');
    _emitConnectedIfNeeded();
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          _markReceivedAndEnsureTimer(_now());
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
          _markReceivedAndEnsureTimer(_now());
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
    final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
    final HttpClientResponse response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'NDGR $phase request failed with status ${response.statusCode}',
        uri: uri,
      );
    }

    return response;
  }

  Uri _uriWithAt(Uri baseUri, NdgrAt at) {
    final Map<String, String> query = Map<String, String>.from(
      baseUri.queryParameters,
    );
    query['at'] = at.asQueryValue();
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

  void _markReceivedAndEnsureTimer(DateTime timestamp) {
    _stallDetector.markReceived(timestamp);
    if (_stallTimer == null) {
      _startStallTimer();
    }
  }

  HttpClient get _activeHttpClient {
    final HttpClient? current = _httpClient;
    if (current != null) {
      current.connectionTimeout = _connectionTimeout;
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

  void _abortActiveConnections() {
    final HttpClient? active = _httpClient;
    if (active == null) {
      return;
    }

    active.close(force: true);
    _httpClient = null;
  }

  void _emitConnectedIfNeeded() {
    if (_hasEmittedConnected || _eventsController.isClosed) {
      return;
    }
    _hasEmittedConnected = true;
    _eventsController.add(const NdgrClientEvent.connected());
  }
}
