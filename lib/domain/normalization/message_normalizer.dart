import 'dart:convert';
import 'dart:developer';

import 'package:meta/meta.dart';

import '../models/app_message.dart';

const String kLegacyUnsupportedFormatContent = 'legacy: 未対応フォーマット';
const String kLegacyUnsupportedFormatMarkerKey = 'legacy_unsupported_format';
const int _maxLogStringLength = 40;
const String _maskedLogValue = '***';
final RegExp _sensitiveKeyPattern = RegExp(
  'token|cookie|auth|credential|password|passwd|secret|session',
  caseSensitive: false,
);

@visibleForTesting
String sanitizeLegacyPayloadForLog(String rawJson) {
  final Object? decoded = _tryDecodeJson(rawJson);
  return _sanitizeLegacyPayloadForLog(decoded, fallbackRaw: rawJson);
}

bool isLegacyUnsupportedFormatMessage(AppMessage message) {
  if (message.raw is! Map<dynamic, dynamic>) {
    return false;
  }

  final Map<dynamic, dynamic> raw = message.raw! as Map<dynamic, dynamic>;
  return raw[kLegacyUnsupportedFormatMarkerKey] == true;
}

typedef LegacyMessageIdGenerator = String Function();

abstract interface class LegacyChatExtractor {
  LegacyChatExtraction? extract(
    Map<String, Object?> payload, {
    required DateTime receivedAt,
  });
}

class LegacyChatExtraction {
  const LegacyChatExtraction({
    required this.content,
    required this.userId,
    required this.timestamp,
  });

  final String content;
  final String? userId;
  final DateTime timestamp;
}

class DefaultLegacyChatExtractor implements LegacyChatExtractor {
  const DefaultLegacyChatExtractor();

  @override
  LegacyChatExtraction? extract(
    Map<String, Object?> payload, {
    required DateTime receivedAt,
  }) {
    final Object? chatObject = payload['chat'];
    if (chatObject is! Map) {
      return null;
    }

    final Map<String, Object?> chat = _toStringObjectMap(chatObject);
    final String? content = _readString(chat['content']);
    // Empty content is treated as unsupported legacy format.
    if (content == null || content.isEmpty) {
      return null;
    }

    final String? userId =
        _readString(chat['user_id']) ?? _readString(chat['userId']);
    final DateTime timestamp = _parseTimestamp(chat['timestamp']) ??
        _parseTimestamp(chat['date']) ??
        receivedAt;

    return LegacyChatExtraction(
      content: content,
      userId: userId,
      timestamp: timestamp,
    );
  }

  String? _readString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  DateTime? _parseTimestamp(Object? value) {
    if (value is int) {
      return _fromUnixNumber(value);
    }
    if (value is double) {
      return _fromUnixNumber(value.toInt());
    }
    if (value is String) {
      final int? unix = int.tryParse(value);
      if (unix != null) {
        return _fromUnixNumber(unix);
      }
      return DateTime.tryParse(value);
    }
    return null;
  }

  DateTime _fromUnixNumber(int value) {
    final bool isMilliseconds = value >= 100000000000;
    if (isMilliseconds) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
}

class MessageNormalizer {
  MessageNormalizer({
    LegacyChatExtractor? legacyChatExtractor,
    LegacyMessageIdGenerator? idGenerator,
    DateTime Function()? clockNow,
  })  : _legacyChatExtractor =
            legacyChatExtractor ?? const DefaultLegacyChatExtractor(),
        _clockNow = clockNow ?? DateTime.now,
        _idGenerator = idGenerator;

  final LegacyChatExtractor _legacyChatExtractor;
  final DateTime Function() _clockNow;
  final LegacyMessageIdGenerator? _idGenerator;

  int _sequence = 0;

  AppMessage? normalizeLegacyJson(String rawJson, {DateTime? receivedAt}) {
    final DateTime now = receivedAt ?? _clockNow();

    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException catch (error, stackTrace) {
      log(
        'Failed to parse legacy JSON. payload=${sanitizeLegacyPayloadForLog(rawJson)}',
        name: 'MessageNormalizer',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }

    if (decoded is! Map) {
      log(
        'Legacy payload does not contain chat key. payload=${_sanitizeLegacyPayloadForLog(decoded, fallbackRaw: rawJson)}',
        name: 'MessageNormalizer',
      );
      return _buildUnsupportedMessage(rawJson, now);
    }

    final Map<String, Object?> payload = _toStringObjectMap(decoded);

    final LegacyChatExtraction? extraction =
        _legacyChatExtractor.extract(payload, receivedAt: now);
    if (extraction == null) {
      log(
        'Legacy payload does not contain chat key. payload=${_sanitizeLegacyPayloadForLog(decoded, fallbackRaw: rawJson)}',
        name: 'MessageNormalizer',
      );
      return _buildUnsupportedMessage(rawJson, now);
    }

    return AppMessage(
      id: _nextId(),
      timestamp: extraction.timestamp,
      userId: extraction.userId,
      content: extraction.content,
      type: AppMessageType.chat,
      raw: decoded,
    );
  }

  AppMessage _buildUnsupportedMessage(String rawJson, DateTime timestamp) {
    return AppMessage(
      id: _nextId(),
      timestamp: timestamp,
      userId: null,
      content: kLegacyUnsupportedFormatContent,
      type: AppMessageType.notification,
      raw: <String, Object?>{
        kLegacyUnsupportedFormatMarkerKey: true,
        'payload': rawJson,
      },
    );
  }

  String _nextId() {
    if (_idGenerator != null) {
      return _idGenerator();
    }

    final String id = 'legacy-${_clockNow().microsecondsSinceEpoch}-$_sequence';
    _sequence += 1;
    return id;
  }
}

Map<String, Object?> _toStringObjectMap(Map<dynamic, dynamic> source) {
  return source.map(
    (dynamic key, dynamic value) => MapEntry(key.toString(), value as Object?),
  );
}

String _sanitizeLegacyPayloadForLog(
  Object? decoded, {
  required String fallbackRaw,
}) {
  if (decoded == null) {
    return _sanitizeLogString(fallbackRaw);
  }

  final Object? sanitized = _sanitizeForLog(decoded);
  try {
    return jsonEncode(sanitized);
  } on JsonUnsupportedObjectError {
    return _sanitizeLogString(fallbackRaw);
  }
}

Object? _sanitizeForLog(Object? value, {String? key}) {
  if (value is Map<dynamic, dynamic>) {
    final Map<String, Object?> sanitized = <String, Object?>{};
    value.forEach((dynamic mapKey, dynamic mapValue) {
      final String stringKey = mapKey.toString();
      if (_isSensitiveKey(stringKey)) {
        sanitized[stringKey] = _maskedLogValue;
      } else {
        sanitized[stringKey] =
            _sanitizeForLog(mapValue as Object?, key: stringKey);
      }
    });
    return sanitized;
  }

  if (value is List<dynamic>) {
    return value
        .map((dynamic item) => _sanitizeForLog(item as Object?, key: key))
        .toList();
  }

  if (value is String) {
    return _sanitizeLogString(value);
  }

  return value;
}

Object? _tryDecodeJson(String rawJson) {
  try {
    return jsonDecode(rawJson);
  } on FormatException {
    return null;
  }
}

bool _isSensitiveKey(String key) {
  return _sensitiveKeyPattern.hasMatch(key);
}

String _sanitizeLogString(String value) {
  final Uri? uri = Uri.tryParse(value);
  final String normalized;
  if (uri != null && uri.host.isNotEmpty && uri.hasScheme) {
    final Uri sanitizedUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );
    normalized = sanitizedUri.toString();
  } else {
    normalized = value;
  }

  if (normalized.length <= _maxLogStringLength) {
    return normalized;
  }
  return '${normalized.substring(0, _maxLogStringLength)}...';
}
