import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import '../models/app_message.dart';
import 'ndgr_message_normalizer.dart';
import 'ndgr_protobuf_decoder.dart';

enum NdgrTimeshiftEventType { started, progress, completed, error }

class NdgrTimeshiftEvent {
  const NdgrTimeshiftEvent._({
    required this.type,
    this.messages,
    this.fetchedCount,
    this.error,
  });

  const NdgrTimeshiftEvent.started()
    : this._(type: NdgrTimeshiftEventType.started);

  const NdgrTimeshiftEvent.progress({
    required List<AppMessage> messages,
    required int fetchedCount,
  }) : this._(
         type: NdgrTimeshiftEventType.progress,
         messages: messages,
         fetchedCount: fetchedCount,
       );

  const NdgrTimeshiftEvent.completed({required int fetchedCount})
    : this._(
        type: NdgrTimeshiftEventType.completed,
        fetchedCount: fetchedCount,
      );

  const NdgrTimeshiftEvent.error({required Object error})
    : this._(type: NdgrTimeshiftEventType.error, error: error);

  final NdgrTimeshiftEventType type;
  final List<AppMessage>? messages;
  final int? fetchedCount;
  final Object? error;
}

class NdgrTimeshiftClient {
  NdgrTimeshiftClient({
    HttpClient? httpClient,
    HttpClient Function()? httpClientFactory,
    NdgrProtobufDecoder? protobufDecoder,
    NdgrMessageNormalizer? normalizer,
    Duration backwardSegmentInterval = const Duration(milliseconds: 7),
    Duration connectionTimeout = const Duration(seconds: 15),
    int hardLimit = defaultHardLimit,
    DateTime Function()? now,
  }) : _seedHttpClient = httpClient,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _protobufDecoder = protobufDecoder ?? NdgrProtobufDecoder(),
       _normalizer = normalizer ?? NdgrMessageNormalizer(),
       _now = now ?? DateTime.now,
       _backwardSegmentInterval = backwardSegmentInterval,
       _connectionTimeout = connectionTimeout,
       _hardLimit = hardLimit {
    if (connectionTimeout <= Duration.zero) {
      throw ArgumentError.value(
        connectionTimeout,
        'connectionTimeout',
        'must be > Duration.zero',
      );
    }
    if (hardLimit < 1) {
      throw ArgumentError.value(hardLimit, 'hardLimit', 'must be >= 1');
    }
  }

  static const int defaultInitialLimit = 5000;
  static const int defaultHardLimit = 100000;

  final HttpClient Function() _httpClientFactory;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;
  final NdgrProtobufDecoder _protobufDecoder;
  final NdgrMessageNormalizer _normalizer;
  final DateTime Function() _now;
  final Duration _backwardSegmentInterval;
  final Duration _connectionTimeout;
  final int _hardLimit;

  final StreamController<NdgrTimeshiftEvent> _eventsController =
      StreamController<NdgrTimeshiftEvent>.broadcast(sync: true);

  bool _isRunning = false;
  bool _isStopped = false;

  // Cursor state for incremental fetching.
  bool _isSessionOpen = false;
  List<String> _remainingPreviousUris = <String>[];
  Uri? _nextBackwardUri;
  final Set<String> _seenIds = <String>{};
  int _totalFetched = 0;
  bool _hasMore = false;

  Stream<NdgrTimeshiftEvent> get events => _eventsController.stream;
  bool get isRunning => _isRunning;
  bool get isSessionOpen => _isSessionOpen;
  bool get hasMore => _hasMore;
  int get totalFetched => _totalFetched;

  Future<void> fetchPastComments(
    Uri viewApiUri, {
    int maxMessages = defaultInitialLimit,
  }) async {
    if (_isRunning) {
      throw StateError('NdgrTimeshiftClient is already running');
    }
    if (maxMessages < 1) {
      throw ArgumentError.value(maxMessages, 'maxMessages', 'must be >= 1');
    }

    _isRunning = true;
    _isStopped = false;

    try {
      if (!_isSessionOpen) {
        await _openSession(viewApiUri);
      }
      await _fetchUpTo(maxMessages);
    } catch (error, stackTrace) {
      if (_isStopped) {
        return;
      }
      log(
        'Timeshift fetch failed',
        name: 'NdgrTimeshiftClient',
        error: error,
        stackTrace: stackTrace,
      );
      _emit(NdgrTimeshiftEvent.error(error: error));
      rethrow;
    } finally {
      _isRunning = false;
    }
  }

  Future<void> fetchMore({required int count}) async {
    if (_isRunning) {
      throw StateError('NdgrTimeshiftClient is already running');
    }
    if (!_isSessionOpen) {
      throw StateError('No session open. Call fetchPastComments first.');
    }
    if (!_hasMore) {
      return;
    }
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be >= 1');
    }

    _isRunning = true;
    _isStopped = false;

    try {
      await _fetchUpTo(count);
    } catch (error, stackTrace) {
      if (_isStopped) {
        return;
      }
      log(
        'Timeshift fetchMore failed',
        name: 'NdgrTimeshiftClient',
        error: error,
        stackTrace: stackTrace,
      );
      _emit(NdgrTimeshiftEvent.error(error: error));
      rethrow;
    } finally {
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    _isStopped = true;
    _abortActiveConnections();
  }

  void resetSession() {
    if (_isRunning) {
      throw StateError(
        'Cannot reset session while a fetch is in progress. Call stop() first.',
      );
    }
    _isSessionOpen = false;
    _remainingPreviousUris = <String>[];
    _nextBackwardUri = null;
    _seenIds.clear();
    _totalFetched = 0;
    _hasMore = false;
  }

  void dispose() {
    _isStopped = true;
    _abortActiveConnections();
    resetSession();

    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }

  Future<void> _openSession(Uri viewApiUri) async {
    _emit(const NdgrTimeshiftEvent.started());

    final Uri fetchUri = _uriWithAt(viewApiUri, 'now');
    final int? currentAt = await _fetchCurrentAt(fetchUri);
    if (_isStopped) {
      return;
    }

    if (currentAt == null) {
      throw StateError('Failed to resolve current timestamp from NDGR');
    }

    final Uri viewAtUri = _uriWithAt(viewApiUri, currentAt.toString());
    final _CollectedEntries entries = await _collectEntries(viewAtUri);
    if (_isStopped) {
      return;
    }

    _remainingPreviousUris = List<String>.from(entries.previousUris);
    _nextBackwardUri = entries.backwardSegmentUri != null
        ? Uri.parse(entries.backwardSegmentUri!)
        : null;
    _seenIds.clear();
    _totalFetched = 0;
    _hasMore = _remainingPreviousUris.isNotEmpty || _nextBackwardUri != null;
    _isSessionOpen = true;
  }

  Future<void> _fetchUpTo(int count) async {
    if (_totalFetched >= _hardLimit) {
      _hasMore = false;
      _emit(NdgrTimeshiftEvent.completed(fetchedCount: _totalFetched));
      return;
    }

    final int effectiveCount = count.clamp(1, _hardLimit - _totalFetched);
    int fetched = 0;

    // Drain remaining Previous segments first.
    while (!_isStopped &&
        fetched < effectiveCount &&
        _remainingPreviousUris.isNotEmpty) {
      final String uri = _remainingPreviousUris.removeAt(0);
      final List<AppMessage> batch = await _fetchSegmentMessages(
        Uri.parse(uri),
        seenIds: _seenIds,
      );
      if (batch.isNotEmpty) {
        fetched += batch.length;
        _totalFetched += batch.length;
        _emit(
          NdgrTimeshiftEvent.progress(
            messages: batch,
            fetchedCount: _totalFetched,
          ),
        );
      }
    }

    // Walk Backward segments — emit each segment immediately.
    while (!_isStopped &&
        fetched < effectiveCount &&
        _nextBackwardUri != null) {
      final HttpClientResponse response = await _fetch(
        _nextBackwardUri!,
        phase: 'backward',
      );
      final Uint8List bytes = await _readAllBytes(response);

      final NdgrPackedSegment packed = _protobufDecoder.decodePackedSegment(
        bytes,
      );

      final List<AppMessage> batch = <AppMessage>[];
      for (final NdgrChunkedMessage chunkedMessage in packed.messages) {
        try {
          final AppMessage? message = _normalizer.normalizeChunkedMessage(
            chunkedMessage,
            receivedAt: _now().toUtc(),
          );
          if (message != null && _seenIds.add(message.id)) {
            batch.add(message);
          }
        } on Object catch (error, stackTrace) {
          log(
            'Failed to normalize timeshift backward message. Skip.',
            name: 'NdgrTimeshiftClient',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      if (batch.isNotEmpty) {
        fetched += batch.length;
        _totalFetched += batch.length;
        _emit(
          NdgrTimeshiftEvent.progress(
            messages: batch,
            fetchedCount: _totalFetched,
          ),
        );
      }

      _nextBackwardUri = packed.nextUri != null
          ? Uri.parse(packed.nextUri!)
          : null;

      if (_nextBackwardUri != null && fetched < effectiveCount) {
        await Future<void>.delayed(_backwardSegmentInterval);
      }
    }

    final bool hasRemainingEntries =
        _remainingPreviousUris.isNotEmpty || _nextBackwardUri != null;
    _hasMore = hasRemainingEntries && _totalFetched < _hardLimit;

    if (!_isStopped) {
      _emit(NdgrTimeshiftEvent.completed(fetchedCount: _totalFetched));
    }
  }

  Future<int?> _fetchCurrentAt(Uri uri) async {
    final HttpClientResponse response = await _fetch(uri, phase: 'at-now');
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();
    int? currentAt;

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          final NdgrChunkedEntry entry = _protobufDecoder.decodeChunkedEntry(
            frame,
          );
          if (entry.nextAt != null) {
            currentAt = entry.nextAt;
          }
        } on FormatException {
          // Skip malformed frames.
        }
      }
    }

    decoder.clear();
    return currentAt;
  }

  Future<_CollectedEntries> _collectEntries(Uri uri) async {
    final HttpClientResponse response = await _fetch(uri, phase: 'collect');
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();

    final List<String> previousUris = <String>[];
    String? backwardSegmentUri;

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          final NdgrChunkedEntry entry = _protobufDecoder.decodeChunkedEntry(
            frame,
          );

          if (entry.previousUri != null) {
            previousUris.add(entry.previousUri!);
          }
          if (entry.backwardSegmentUri != null) {
            backwardSegmentUri = entry.backwardSegmentUri;
          }
          if (entry.segmentUri != null) {
            decoder.clear();
            return _CollectedEntries(
              previousUris: previousUris,
              backwardSegmentUri: backwardSegmentUri,
            );
          }
        } on FormatException {
          // Skip malformed frames.
        }
      }
    }

    decoder.clear();
    return _CollectedEntries(
      previousUris: previousUris,
      backwardSegmentUri: backwardSegmentUri,
    );
  }

  Future<List<AppMessage>> _fetchSegmentMessages(
    Uri uri, {
    required Set<String> seenIds,
  }) async {
    final HttpClientResponse response = await _fetch(uri, phase: 'segment');
    final NdgrLengthDelimitedDecoder decoder = NdgrLengthDelimitedDecoder();
    final List<AppMessage> messages = <AppMessage>[];

    await for (final List<int> chunk in response) {
      if (_isStopped) {
        break;
      }

      final List<Uint8List> frames = decoder.add(chunk);
      for (final Uint8List frame in frames) {
        try {
          final NdgrChunkedMessage chunkedMessage = _protobufDecoder
              .decodeChunkedMessage(frame);
          final AppMessage? message = _normalizer.normalizeChunkedMessage(
            chunkedMessage,
            receivedAt: _now().toUtc(),
          );
          if (message != null && seenIds.add(message.id)) {
            messages.add(message);
          }
        } on Object catch (error, stackTrace) {
          log(
            'Failed to decode/normalize timeshift segment message. '
            'Skip frame.',
            name: 'NdgrTimeshiftClient',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    decoder.clear();
    return messages;
  }

  Future<HttpClientResponse> _fetch(Uri uri, {required String phase}) async {
    final HttpClientRequest request = await _activeHttpClient.getUrl(uri);
    final HttpClientResponse response = await request.close();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'NDGR timeshift $phase request failed with status ${response.statusCode}',
        uri: uri,
      );
    }

    return response;
  }

  Uri _uriWithAt(Uri baseUri, String at) {
    final Map<String, String> query = Map<String, String>.from(
      baseUri.queryParameters,
    );
    query['at'] = at;
    return baseUri.replace(queryParameters: query);
  }

  Future<Uint8List> _readAllBytes(HttpClientResponse response) async {
    final BytesBuilder bytesBuilder = BytesBuilder(copy: false);
    await for (final List<int> chunk in response) {
      bytesBuilder.add(chunk);
    }
    return bytesBuilder.toBytes();
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

  void _emit(NdgrTimeshiftEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }
}

class _CollectedEntries {
  const _CollectedEntries({
    required this.previousUris,
    this.backwardSegmentUri,
  });

  final List<String> previousUris;
  final String? backwardSegmentUri;
}
