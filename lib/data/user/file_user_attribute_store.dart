import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'user_attribute_store.dart';

/// File-based implementation of [UserAttributeStore].
///
/// Stores each broadcaster's attributes in a separate JSON file under
/// `<root>/<broadcasterId>.json`, where `<root>` is provided at
/// construction (typically `<appDocDir>/user_attributes`).
///
/// ## Durability
///
/// Each write uses [File.writeAsString] with `flush: true`, which invokes
/// the underlying OS `fsync` so the data is durably written before the
/// future completes.  Combined with the lifecycle flush in `SelectScreen`
/// (`flushPendingWrites` on pause/inactive/detached), this ensures that
/// even `unawaited` writes complete before the process can be killed.
///
/// The previous `SharedPreferencesUserAttributeStore` relied on the
/// Android `commit()` path which is synchronous to disk, but the pub.dev
/// docs for `shared_preferences` advise against using the package for
/// critical data.  A dedicated file-per-broadcaster layout also gives
/// better separation and extensibility.
///
/// ## File layout
///
/// ```
/// <root>/
///   <broadcasterId_1>.json
///   <broadcasterId_2>.json
///   ...
///   _index.json            -- list of known broadcaster IDs (for cleanup)
/// ```
///
/// Each broadcaster JSON shares the same shape as the legacy
/// `SharedPreferencesUserAttributeStore` payload:
///
/// ```json
/// {
///   "user1": 0xFFE53935,                         // legacy color-only
///   "user2": {"c": 0xFF1E88E5, "n": "たろう"},   // color + nickname
///   "user3": {"n": "じろう"},                     // nickname only
///   "_lastUsedAt": 1234567890
/// }
/// ```
///
/// ## Concurrency
///
/// A per-broadcaster lock (serialised via [Future] chaining) guarantees
/// that read-modify-write cycles for the same broadcaster never interleave
/// even when callers invoke multiple `unawaited` operations in rapid
/// succession.
class FileUserAttributeStore implements UserAttributeStore {
  FileUserAttributeStore({required Directory root}) : _root = root;

  final Directory _root;
  final Map<String, Future<void>> _locks = <String, Future<void>>{};
  Future<void> _indexLock = Future<void>.value();

  static const String _indexFileName = '_index.json';
  static const String _lastUsedAtField = userAttrLastUsedAtField;

  /// Illegal characters on common filesystems. We sanitise broadcaster IDs
  /// defensively even though in practice they are numeric user IDs.
  static final RegExp _illegalChars = RegExp(r'[^A-Za-z0-9._-]');

  String _sanitize(String broadcasterId) =>
      broadcasterId.replaceAll(_illegalChars, '_');

  File _fileFor(String broadcasterId) =>
      File('${_root.path}/${_sanitize(broadcasterId)}.json');

  File get _indexFile => File('${_root.path}/$_indexFileName');

  /// Serialises operations per broadcasterId so concurrent
  /// read-modify-write cycles do not clobber each other.
  Future<T> _withLock<T>(String broadcasterId, Future<T> Function() op) {
    final Future<void> previous = _locks[broadcasterId] ?? Future<void>.value();
    final Completer<T> completer = Completer<T>();
    final Future<void> next = previous.then((_) async {
      try {
        final T result = await op();
        completer.complete(result);
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    _locks[broadcasterId] = next.whenComplete(() {
      if (identical(_locks[broadcasterId], next)) {
        _locks.remove(broadcasterId);
      }
    });
    return completer.future;
  }

  Future<void> _ensureRoot() async {
    if (!await _root.exists()) {
      await _root.create(recursive: true);
    }
  }

  Future<Map<String, dynamic>> _readRaw(String broadcasterId) async {
    final File file = _fileFor(broadcasterId);
    if (!await file.exists()) {
      return <String, dynamic>{};
    }
    try {
      final String raw = await file.readAsString();
      if (raw.isEmpty) {
        return <String, dynamic>{};
      }
      final Object? decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } on Object catch (e) {
      developer.log(
        'Failed to read user attributes for $broadcasterId: $e',
        name: 'FileUserAttributeStore',
      );
      return <String, dynamic>{};
    }
  }

  Future<void> _writeRaw(String broadcasterId, Map<String, dynamic> raw) async {
    await _ensureRoot();
    final File file = _fileFor(broadcasterId);
    try {
      await file.writeAsString(json.encode(raw), flush: true);
    } on Object catch (e) {
      developer.log(
        'Failed to write user attributes for $broadcasterId: $e',
        name: 'FileUserAttributeStore',
      );
      rethrow;
    }
    await _addToIndex(broadcasterId);
  }

  @override
  Future<Map<String, int>> loadColors(String broadcasterId) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      if (raw.isEmpty) {
        return <String, int>{};
      }
      await _touchLastUsedAt(broadcasterId, raw);
      return extractColors(raw);
    });
  }

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      if (raw.isEmpty) {
        return <String, String>{};
      }
      await _touchLastUsedAt(broadcasterId, raw);
      return extractNicknames(raw);
    });
  }

  @override
  Future<UserAttributesSnapshot> loadAttributes(String broadcasterId) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      if (raw.isEmpty) {
        return (colors: <String, int>{}, nicknames: <String, String>{});
      }
      await _touchLastUsedAt(broadcasterId, raw);
      return (colors: extractColors(raw), nicknames: extractNicknames(raw));
    });
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      final UserEntry updated = existing.copyWith(color: colorValue);
      raw[userId] = updated.toJson();
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _writeRaw(broadcasterId, raw);
    });
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      if (existing.color == null) {
        return;
      }
      final UserEntry updated = existing.copyWithoutColor();
      if (updated.isEmpty) {
        raw.remove(userId);
      } else {
        raw[userId] = updated.toJson();
      }
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _writeRaw(broadcasterId, raw);
    });
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      final UserEntry updated = existing.copyWith(nickname: nickname);
      raw[userId] = updated.toJson();
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _writeRaw(broadcasterId, raw);
    });
  }

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) {
    return _withLock(broadcasterId, () async {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      final UserEntry existing = readUserEntry(raw, userId);
      if (existing.nickname == null) {
        return;
      }
      final UserEntry updated = existing.copyWithoutNickname();
      if (updated.isEmpty) {
        raw.remove(userId);
      } else {
        raw[userId] = updated.toJson();
      }
      raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
      await _writeRaw(broadcasterId, raw);
    });
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    if (!await _root.exists()) {
      return 0;
    }
    final List<String> index = await _readIndex();
    if (index.isEmpty) {
      return 0;
    }
    final int cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final List<String> remaining = <String>[];
    int removedCount = 0;

    for (final String broadcasterId in index) {
      final Map<String, dynamic> raw = await _readRaw(broadcasterId);
      final int lastUsedAt = raw[_lastUsedAtField] is int
          ? raw[_lastUsedAtField] as int
          : 0;

      if (lastUsedAt < cutoff) {
        final File file = _fileFor(broadcasterId);
        if (await file.exists()) {
          await file.delete();
        }
        removedCount++;
      } else {
        remaining.add(broadcasterId);
      }
    }

    await _writeIndex(remaining);
    return removedCount;
  }

  /// Imports a legacy JSON payload verbatim for [broadcasterId].
  ///
  /// Used by [UserAttributeStoreMigrator] to copy entries from the previous
  /// `SharedPreferencesUserAttributeStore` without re-encoding. The raw
  /// string is validated to be a JSON object and written with `flush: true`
  /// so durability is guaranteed. Existing data for the same broadcaster is
  /// overwritten.
  Future<void> importRawJson(String broadcasterId, String rawJson) {
    return _withLock(broadcasterId, () async {
      final Object? decoded = json.decode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      await _writeRaw(broadcasterId, decoded);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal helpers (mirror SharedPreferencesUserAttributeStore so the JSON
  // payload shape stays identical, enabling one-shot migration).
  // ---------------------------------------------------------------------------

  Future<void> _touchLastUsedAt(
    String broadcasterId,
    Map<String, dynamic> raw,
  ) async {
    raw[_lastUsedAtField] = DateTime.now().millisecondsSinceEpoch;
    await _writeRaw(broadcasterId, raw);
  }

  Future<List<String>> _readIndex() async {
    final File file = _indexFile;
    if (!await file.exists()) {
      return <String>[];
    }
    try {
      final String raw = await file.readAsString();
      if (raw.isEmpty) {
        return <String>[];
      }
      final Object? decoded = json.decode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
      return <String>[];
    } on Object {
      return <String>[];
    }
  }

  Future<void> _writeIndex(List<String> index) async {
    await _ensureRoot();
    await _indexFile.writeAsString(json.encode(index), flush: true);
  }

  Future<void> _addToIndex(String broadcasterId) {
    return _withIndexLock(() async {
      final List<String> index = await _readIndex();
      if (index.contains(broadcasterId)) {
        return;
      }
      index.add(broadcasterId);
      await _writeIndex(index);
    });
  }

  /// Serialises index operations so concurrent writes to different
  /// broadcasters cannot produce a lost-update on the shared
  /// `_index.json` file.
  Future<T> _withIndexLock<T>(Future<T> Function() op) {
    final Completer<T> completer = Completer<T>();
    final Future<void> next = _indexLock.then((_) async {
      try {
        completer.complete(await op());
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    _indexLock = next.whenComplete(() {});
    return completer.future;
  }

  @override
  Future<void> flushPendingWrites() async {
    // Wait for all per-broadcaster locks and the index lock to drain.
    await Future.wait(<Future<void>>[..._locks.values, _indexLock]);
  }
}
