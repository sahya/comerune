import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

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
///
/// ## Filesystem assumptions
///
/// `<root>` is assumed to be a regular directory on the **same filesystem**
/// as the rendered tmp files. Atomic write-then-rename relies on
/// `File.rename` being atomic, which only holds within a single filesystem
/// (POSIX `rename(2)` semantics). Pointing `<root>` at a directory that
/// crosses a filesystem boundary (e.g. a bind mount, FUSE union, or
/// network mount with non-atomic rename) breaks the durability guarantee.
///
/// ## Tmp orphan sweep
///
/// [_sweepTmpOrphans] is invoked exactly once per [cleanup] call. In
/// typical usage [cleanup] is called once per app start (typically right
/// after migration completes), so the sweep also runs once per app
/// start; if a caller invokes [cleanup] multiple times the sweep will
/// run that many times. The sweep is intentionally not run on every
/// write to keep the hot path cheap.
class FileUserAttributeStore implements UserAttributeStore {
  FileUserAttributeStore({required Directory root}) : _root = root;

  final Directory _root;
  final Map<String, Future<void>> _locks = <String, Future<void>>{};
  Future<void> _indexLock = Future<void>.value();
  // Static so that multiple concurrent FileUserAttributeStore instances
  // pointed at the same root cannot collide on the per-process counter.
  static int _tmpCounter = 0;

  static const String _indexFileName = '_index.json';

  /// Infix marking a tmp file produced by [_atomicWriteString].
  ///
  /// The `-` character is intentional for readability and for being
  /// unlikely to collide with real broadcaster IDs (which are numeric or
  /// `lv*` in practice). Note however that `-` is **not** stripped by
  /// [_sanitize] (the regex `[^A-Za-z0-9._-]` preserves `-`), so the
  /// presence of `-` in the infix offers no hard guarantee on its own.
  ///
  /// **The only authoritative protection against deleting a legitimate
  /// broadcaster file is the strict suffix check in
  /// [_isWellFormedTmpSuffix]**, which requires exactly three
  /// dot-separated all-digit tokens after this infix.
  ///
  /// Exposed via [tmpInfix] for tests so test fixtures stay in sync with
  /// any future rename of this constant.
  static const String _tmpInfix = '.atomic-tmp.';

  /// Test-only accessor for [_tmpInfix].
  @visibleForTesting
  static const String tmpInfix = _tmpInfix;

  static const String _lastUsedAtField = userAttrLastUsedAtField;

  /// Illegal characters on common filesystems. We sanitise broadcaster IDs
  /// defensively even though in practice they are numeric user IDs.
  static final RegExp _illegalChars = RegExp(r'[^A-Za-z0-9._-]');

  String _sanitize(String broadcasterId) =>
      broadcasterId.replaceAll(_illegalChars, '_');

  File _fileFor(String broadcasterId) =>
      File('${_root.path}/${_sanitize(broadcasterId)}.json');

  File get _indexFile => File('${_root.path}/$_indexFileName');

  /// Builds a unique temporary file path for [target] using process id,
  /// monotonic timestamp and an in-process counter to avoid collisions
  /// between concurrent writers (and across crashed/restarted processes).
  File _tmpFileFor(File target) {
    final int counter = _tmpCounter++;
    final int micros = DateTime.now().microsecondsSinceEpoch;
    return File('${target.path}$_tmpInfix$pid.$micros.$counter');
  }

  /// Writes [contents] to [target] atomically using the standard
  /// write-then-rename pattern: write to a unique tmp file with
  /// `flush: true` (fsync), then rename over [target]. Rename is
  /// atomic on POSIX and on the Dart VM on Windows for same-volume
  /// targets. On rename failure the tmp file is best-effort deleted
  /// before rethrowing.
  Future<void> _atomicWriteString(File target, String contents) async {
    final File tmp = _tmpFileFor(target);
    try {
      await tmp.writeAsString(contents, flush: true);
      await tmp.rename(target.path);
    } on Object {
      try {
        if (await tmp.exists()) {
          await tmp.delete();
        }
      } on Object catch (e) {
        // Best-effort cleanup; surface the secondary failure to logs but
        // do not let it mask the primary error that triggered cleanup.
        // Log only the basename so the OS user's home path (PII) does
        // not leak into logs.
        developer.log(
          'Failed to clean up tmp file ${_basename(tmp.path)} after '
          'write failure: $e',
          name: 'FileUserAttributeStore',
        );
      }
      rethrow;
    }
  }

  /// Returns the final path component of [path] using the platform
  /// separator. Used to keep absolute paths (which may include the OS
  /// user's home directory) out of logs.
  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;

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
      await _atomicWriteString(file, json.encode(raw));
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

  /// Removes broadcaster entries that have not been accessed for longer
  /// than [maxAge]. Defaults to 365 days.
  ///
  /// The implementation iterates **sequentially** over the snapshotted
  /// index and, for each broadcaster, takes the per-broadcaster lock
  /// (via [_withLock]) before reading and deleting. This means an
  /// in-flight write (`setColor`, `setNickname`, etc.) for the same
  /// broadcaster is awaited before its file may be removed, and a
  /// racing write that adds a brand-new broadcaster after the index
  /// snapshot is preserved by the final index re-read.
  ///
  /// As a side-effect, [_sweepTmpOrphans] is invoked at the start of
  /// every cleanup to reclaim leaked tmp files from previously
  /// crashed processes.
  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    if (!await _root.exists()) {
      return 0;
    }
    await _sweepTmpOrphans();

    // Snapshot the index under the index lock so concurrent _addToIndex
    // calls do not interleave the read.
    final List<String> index = await _withIndexLock<List<String>>(_readIndex);
    if (index.isEmpty) {
      // Fast path: nothing to delete and the empty index file (if any)
      // is already canonical. Skip the trailing index re-read and write.
      return 0;
    }
    final int cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final Set<String> removedIds = <String>{};

    // Per-broadcaster lock around read-and-delete prevents a concurrent
    // setColor / setNickname for the same broadcaster from racing with
    // the deletion. The index lock is intentionally NOT held here to
    // avoid the lock-order inversion: write paths take per-broadcaster
    // lock first and then the index lock (via _addToIndex).
    for (final String broadcasterId in index) {
      final bool removed = await _withLock<bool>(broadcasterId, () async {
        final Map<String, dynamic> raw = await _readRaw(broadcasterId);
        final int lastUsedAt = raw[_lastUsedAtField] is int
            ? raw[_lastUsedAtField] as int
            : 0;
        if (lastUsedAt < cutoff) {
          final File file = _fileFor(broadcasterId);
          if (await file.exists()) {
            await file.delete();
          }
          return true;
        }
        return false;
      });
      if (removed) {
        removedIds.add(broadcasterId);
      }
    }

    if (removedIds.isEmpty) {
      // No removals — the snapshotted index is still consistent with the
      // surviving files, so skip rewriting the index. A concurrent
      // setColor may have added a new broadcaster which already updated
      // the index via _addToIndex; we must not clobber that update.
      return 0;
    }

    // Final index update under the index lock. Re-read the latest index
    // (a concurrent setColor may have added a brand-new broadcaster) and
    // only drop IDs we deleted whose files were not subsequently revived
    // by a racing write between our delete and this re-check.
    await _withIndexLock<void>(() async {
      final List<String> current = await _readIndex();
      final List<String> remaining = <String>[];
      for (final String id in current) {
        if (removedIds.contains(id) && !await _fileFor(id).exists()) {
          continue;
        }
        remaining.add(id);
      }
      await _writeIndex(remaining);
    });
    return removedIds.length;
  }

  /// Best-effort removal of leftover `*<tmpInfix><pid>.<micros>.<counter>`
  /// files from previously crashed write-then-rename attempts.
  ///
  /// Only files whose name matches the **exact** tmp suffix shape
  /// (`<tmpInfix>` followed by exactly three dot-separated all-digit
  /// tokens) are considered. This guards against deleting a legitimate
  /// broadcaster file whose ID happens to contain `<tmpInfix>` followed
  /// by digits — for example, a malicious or unusual broadcaster ID.
  ///
  /// Files whose embedded pid equals the current process pid are skipped
  /// so an in-flight tmp file from this process is never deleted out
  /// from under an awaiting `rename`.
  ///
  /// Failures are logged but never rethrown — sweep is best-effort and
  /// must not block the rest of [cleanup].
  Future<void> _sweepTmpOrphans() async {
    try {
      await for (final FileSystemEntity entry in _root.list(
        followLinks: false,
      )) {
        if (entry is! File) {
          continue;
        }
        final String name = entry.path.split(Platform.pathSeparator).last;
        final int infixIndex = name.indexOf(_tmpInfix);
        if (infixIndex < 0) {
          continue;
        }
        final String suffix = name.substring(infixIndex + _tmpInfix.length);
        if (!_isWellFormedTmpSuffix(suffix)) {
          continue;
        }
        final int? filePid = int.tryParse(suffix.split('.').first);
        if (filePid == null || filePid == pid) {
          continue;
        }
        try {
          await entry.delete();
        } on Object catch (e) {
          developer.log(
            'Failed to delete orphan tmp ${_basename(entry.path)}: $e',
            name: 'FileUserAttributeStore',
          );
        }
      }
    } on Object catch (e) {
      developer.log(
        'Failed to sweep tmp orphans: $e',
        name: 'FileUserAttributeStore',
      );
    }
  }

  /// Returns true iff [suffix] (the part after [_tmpInfix]) is exactly
  /// three dot-separated tokens, each consisting solely of ASCII digits.
  ///
  /// Matches the exact shape produced by [_tmpFileFor]:
  /// `<pid>.<micros>.<counter>`. Any extra dots, missing tokens, or
  /// non-digit characters reject the match — preventing broadcaster IDs
  /// that happen to contain `<tmpInfix>123` from being mis-classified.
  ///
  /// Exposed for unit tests via [isWellFormedTmpSuffix] so the strict
  /// shape contract — the *only* guarantee against deleting a legitimate
  /// broadcaster file — has dedicated coverage independent of the
  /// directory-walking sweep code path.
  @visibleForTesting
  static bool isWellFormedTmpSuffix(String suffix) =>
      _isWellFormedTmpSuffix(suffix);

  static bool _isWellFormedTmpSuffix(String suffix) {
    final List<String> parts = suffix.split('.');
    if (parts.length != 3) {
      return false;
    }
    for (final String part in parts) {
      if (part.isEmpty) {
        return false;
      }
      for (int i = 0; i < part.length; i++) {
        final int code = part.codeUnitAt(i);
        if (code < 0x30 || code > 0x39) {
          return false;
        }
      }
    }
    return true;
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
    try {
      await _atomicWriteString(_indexFile, json.encode(index));
    } on Object catch (e) {
      // Differentiated from the inner _atomicWriteString failure log so
      // operators can distinguish "the broadcaster index file failed to
      // persist" from a generic per-broadcaster write failure. No path
      // is included to avoid leaking the OS user's home directory.
      developer.log(
        'Failed to persist broadcaster index: $e',
        name: 'FileUserAttributeStore',
      );
      rethrow;
    }
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
