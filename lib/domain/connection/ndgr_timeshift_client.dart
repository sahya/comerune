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
    DateTime Function()? now,
  }) : _seedHttpClient = httpClient,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _protobufDecoder = protobufDecoder ?? NdgrProtobufDecoder(),
       _normalizer = normalizer ?? NdgrMessageNormalizer(),
       _now = now ?? DateTime.now,
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

  static const int defaultMaxMessages = 50000;

  final HttpClient Function() _httpClientFactory;
  HttpClient? _seedHttpClient;
  HttpClient? _httpClient;
  final NdgrProtobufDecoder _protobufDecoder;
  final NdgrMessageNormalizer _normalizer;
  final DateTime Function() _now;
  final Duration _backwardSegmentInterval;
  final Duration _connectionTimeout;

  final StreamController<NdgrTimeshiftEvent> _eventsController =
      StreamController<NdgrTimeshiftEvent>.broadcast(sync: true);

  bool _isRunning = false;
  bool _isStopped = false;

  Stream<NdgrTimeshiftEvent> get events => _eventsController.stream;
  bool get isRunning => _isRunning;

  Future<void> fetchPastComments(
    Uri viewApiUri, {
    int maxMessages = defaultMaxMessages,
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
      await _run(viewApiUri, maxMessages: maxMessages);
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

  Future<void> stop() async {
    _isStopped = true;
    _abortActiveConnections();
  }

  void dispose() {
    _isStopped = true;
    _abortActiveConnections();

    if (!_eventsController.isClosed) {
      _eventsController.close();
    }
  }

  Future<void> _run(Uri viewApiUri, {required int maxMessages}) async {
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

    int totalFetched = 0;
    final Set<String> seenIds = <String>{};

    // Fetch Previous segments (most recent past comments).
    // Sort by previousUri descending isn't meaningful since we don't have
    // timestamps on the entry itself — the server returns them newest first.
    for (final String previousUri in entries.previousUris) {
      if (_isStopped || totalFetched >= maxMessages) {
        break;
      }

      final List<AppMessage> batch = await _fetchSegmentMessages(
        Uri.parse(previousUri),
        seenIds: seenIds,
      );
      if (batch.isNotEmpty) {
        totalFetched += batch.length;
        _emit(
          NdgrTimeshiftEvent.progress(
            messages: batch,
            fetchedCount: totalFetched,
          ),
        );
      }
    }

    // Walk the Backward segment linked list for older comments.
    if (entries.backwardSegmentUri != null &&
        !_isStopped &&
        totalFetched < maxMessages) {
      totalFetched += await _walkBackwardSegments(
        Uri.parse(entries.backwardSegmentUri!),
        maxMessages: maxMessages - totalFetched,
        seenIds: seenIds,
        previouslyFetched: totalFetched,
      );
    }

    if (!_isStopped) {
      _emit(NdgrTimeshiftEvent.completed(fetchedCount: totalFetched));
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
          // Stop collecting when a live Segment appears — past entries
          // have already been delivered.
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

  Future<int> _walkBackwardSegments(
    Uri startUri, {
    required int maxMessages,
    required Set<String> seenIds,
    int previouslyFetched = 0,
  }) async {
    // Accumulate backward segment batches in fetch order (newest-first),
    // then emit in reverse (oldest-first) for chronological ordering.
    // Uses add + reversed instead of insert(0) to avoid O(n²) list shifting.
    final List<List<AppMessage>> batches = <List<AppMessage>>[];
    int totalCollected = 0;
    Uri? current = startUri;

    while (!_isStopped && current != null && totalCollected < maxMessages) {
      final HttpClientResponse response = await _fetch(
        current,
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
          if (message != null && seenIds.add(message.id)) {
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
        batches.add(batch);
        totalCollected += batch.length;
      }

      if (packed.nextUri == null) {
        break;
      }

      await Future<void>.delayed(_backwardSegmentInterval);
      current = Uri.parse(packed.nextUri!);
    }

    // Emit backward batches oldest-first so downstream receives
    // comments in chronological order.
    int emitted = 0;
    for (final List<AppMessage> batch in batches.reversed) {
      if (_isStopped) {
        break;
      }
      emitted += batch.length;
      _emit(
        NdgrTimeshiftEvent.progress(
          messages: batch,
          fetchedCount: previouslyFetched + emitted,
        ),
      );
    }

    return emitted;
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
