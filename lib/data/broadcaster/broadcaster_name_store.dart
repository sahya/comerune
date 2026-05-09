import 'dart:convert';
import 'dart:developer' as developer;

import '../../application/settings/settings_store.dart';

/// Issue #727 follow-up: persistent cache of `broadcasterId → display name`
/// pairs so the NG picker can render friendly names for every tile in one
/// synchronous pass without N async resolves.
///
/// The cache is populated opportunistically during normal app use — every
/// time the app resolves a broadcaster's name (e.g. via `programinfo`),
/// the resolved name is written back through [setName]. The picker then
/// reads from this cache via [loadName] / [loadAll].
abstract class BroadcasterNameStore {
  /// Sets the human-readable display name for [broadcasterId].
  ///
  /// No-op when [broadcasterId] is empty or [name] is empty (we never want
  /// a tile that displays "()" or is keyed by an empty ID).
  Future<void> setName(String broadcasterId, String name);

  /// Returns the cached name for [broadcasterId], or `null` when unknown.
  String? loadName(String broadcasterId);

  /// Returns a snapshot of all cached `broadcasterId → name` mappings.
  ///
  /// Used by the picker so it can render names for every tile in one pass
  /// without N async calls.
  Map<String, String> loadAll();

  /// Issue #833: removes cached entries whose `lastUsedAt` is older than
  /// [maxAge].
  ///
  /// Designed to be invoked once per startup. The default retention is
  /// **730 days (2 years)** — intentionally longer than
  /// `UserAttributeStore.cleanup()`'s 365 days to accommodate annual /
  /// seasonal broadcasters that a user may revisit after a long gap.
  ///
  /// Returns the number of entries removed.
  Future<int> cleanup({Duration maxAge = const Duration(days: 730)});
}

/// SharedPreferences-backed implementation of [BroadcasterNameStore].
///
/// Storage layout (current schema, Issue #833):
/// - Single SharedPreferences key: `broadcaster.names`
/// - JSON object: `{"<broadcasterId>": {"name": "<name>",
///   "lastUsedAt": <epoch_ms>}, ...}`
/// - Defensive parsing: malformed JSON returns an empty map.
///
/// Legacy schema (pre-Issue #833):
/// - Same key, but the value is a plain string: `{"<broadcasterId>":
///   "<name>", ...}`. Loaded transparently and rewritten with
///   `lastUsedAt = DateTime.now()` on the next [setName] / [cleanup]
///   call (one-shot migration).
///
/// Concurrent [setName] calls go through a serial write chain, mirroring
/// the pattern used by `SharedPreferencesBroadcasterNgStore`, so two
/// concurrent callers cannot interleave a partial read-modify-write.
// TODO(#727 follow-up): consider an in-memory snapshot cache invalidated
// on setName() so loadName() does not re-parse on every call. Picker
// currently mitigates by using loadAll() once per build via the
// BroadcasterNgListScreen.broadcasterNamesSnapshot parameter.
class SharedPreferencesBroadcasterNameStore implements BroadcasterNameStore {
  SharedPreferencesBroadcasterNameStore({required SharedPreferencesLike prefs})
    : _prefs = prefs;

  static const String _storageKey = 'broadcaster.names';

  /// Minimum interval between consecutive `lastUsedAt` writes triggered by
  /// a [loadName] read for the same broadcaster. Reads inside this window
  /// skip the SharedPreferences write entirely so that a hot broadcaster
  /// does not cause one disk write per UI build.
  static const Duration _touchThrottle = Duration(hours: 24);

  final SharedPreferencesLike _prefs;
  Future<void> _pendingWriteChain = Future<void>.value();

  /// In-memory record of the last time we persisted `lastUsedAt` for a
  /// broadcasterId via the lazy-touch path on [loadName]. Volatile by
  /// design: a process restart resets the throttle so the first read
  /// after launch always refreshes the timestamp.
  final Map<String, int> _lastTouchAt = <String, int>{};

  @override
  Future<void> setName(String broadcasterId, String name) async {
    if (broadcasterId.isEmpty || name.isEmpty) {
      return;
    }
    await _enqueueWrite(() async {
      final Map<String, _Entry> current = _readAll();
      final _Entry? existing = current[broadcasterId];
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (existing != null && existing.name == name) {
        // Name unchanged — only refresh lastUsedAt, and only if the
        // throttle window has elapsed, so a noisy resolver does not
        // produce one write per second.
        final int last = _lastTouchAt[broadcasterId] ?? existing.lastUsedAt;
        // Clock-skew defense: if the recorded `last` is in the future
        // (e.g. user moved device clock forward, then back), the
        // throttle window can never elapse with `now - last` because
        // the value is negative. Treat such entries as "needs refresh"
        // so the user does not get permanently stuck without lastUsedAt
        // updates.
        if (last <= now && now - last < _touchThrottle.inMilliseconds) {
          return;
        }
        current[broadcasterId] = _Entry(name: name, lastUsedAt: now);
      } else {
        current[broadcasterId] = _Entry(name: name, lastUsedAt: now);
      }
      _lastTouchAt[broadcasterId] = now;
      await _prefs.setString(_storageKey, _encode(current));
    });
  }

  @override
  String? loadName(String broadcasterId) {
    if (broadcasterId.isEmpty) {
      return null;
    }
    final Map<String, _Entry> all = _readAll();
    final _Entry? entry = all[broadcasterId];
    if (entry == null) {
      return null;
    }
    // Lazy timestamp update on read — see [_touchThrottle]. We schedule
    // the write through the serial chain so that a concurrent setName
    // cannot interleave; we intentionally do not await the future from
    // inside [loadName] because callers expect a synchronous read.
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int last = _lastTouchAt[broadcasterId] ?? entry.lastUsedAt;
    // Clock-skew defense: refresh when `last > now` (user moved clock
    // backward). Otherwise the difference is negative and the throttle
    // would suppress writes indefinitely.
    final bool needsRefresh =
        last > now || now - last >= _touchThrottle.inMilliseconds;
    if (needsRefresh) {
      _lastTouchAt[broadcasterId] = now;
      _enqueueWrite(() async {
        final Map<String, _Entry> current = _readAll();
        final _Entry? again = current[broadcasterId];
        if (again == null) {
          // Entry was removed (e.g. cleanup) between read and write.
          return;
        }
        current[broadcasterId] = _Entry(name: again.name, lastUsedAt: now);
        await _prefs.setString(_storageKey, _encode(current));
      }).catchError((Object error, StackTrace stackTrace) {
        // Lazy refresh is best-effort; log so a sustained storage
        // failure (disk full / encryption corruption) is not silently
        // swallowed.
        developer.log(
          'Lazy lastUsedAt refresh failed for broadcasterId',
          name: 'BroadcasterNameStore',
          error: error,
          stackTrace: stackTrace,
        );
      });
    }
    return entry.name;
  }

  @override
  Map<String, String> loadAll() {
    final Map<String, _Entry> all = _readAll();
    final Map<String, String> result = <String, String>{};
    all.forEach((String id, _Entry entry) {
      result[id] = entry.name;
    });
    return result;
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 730)}) async {
    return _enqueueWrite<int>(() async {
      final Map<String, _Entry> current = _readAll();
      if (current.isEmpty) {
        return 0;
      }
      final int cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
      final List<MapEntry<String, _Entry>> removed =
          <MapEntry<String, _Entry>>[];
      final Map<String, _Entry> next = <String, _Entry>{};
      current.forEach((String id, _Entry entry) {
        if (entry.lastUsedAt < cutoff) {
          removed.add(MapEntry<String, _Entry>(id, entry));
        } else {
          next[id] = entry;
        }
      });
      if (removed.isEmpty) {
        // Still rewrite if the on-disk payload was a legacy-schema string
        // map — _readAll has now upgraded it in memory and we want the
        // disk to reflect the new schema as a one-shot migration.
        if (_isLegacyOnDisk()) {
          await _prefs.setString(_storageKey, _encode(current));
        }
        return 0;
      }
      await _prefs.setString(_storageKey, _encode(next));
      // Drop throttle entries for removed broadcasters so a future
      // setName for the same id refreshes lastUsedAt immediately.
      for (final MapEntry<String, _Entry> e in removed) {
        _lastTouchAt.remove(e.key);
      }
      // Privacy: keep the summary tight so device logs do not retain a
      // user's per-broadcaster watch-time history. The count + cutoff
      // is enough for support triage; full id/timestamp pairs are kept
      // in `assert` only so they remain visible while debugging but do
      // not ship to release builds.
      developer.log(
        'Cleanup removed ${removed.length} entries (cutoff=$cutoff)',
        name: 'BroadcasterNameStore',
      );
      assert(() {
        final String detail = removed
            .map(
              (MapEntry<String, _Entry> e) => '${e.key}@${e.value.lastUsedAt}',
            )
            .join(', ');
        developer.log(
          'Cleanup removed ids (debug only): $detail',
          name: 'BroadcasterNameStore',
        );
        return true;
      }());
      return removed.length;
    });
  }

  /// Decodes the storage payload, transparently upgrading the legacy
  /// `{id: name}` string-map schema by stamping `lastUsedAt = now` on
  /// every entry.
  ///
  /// Returns an empty map when the payload is missing, malformed, or in
  /// an unexpected shape.
  Map<String, _Entry> _readAll() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, _Entry>{};
    }
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map<dynamic, dynamic>) {
        return <String, _Entry>{};
      }
      final Map<String, _Entry> result = <String, _Entry>{};
      final int nowForLegacy = DateTime.now().millisecondsSinceEpoch;
      decoded.forEach((Object? key, Object? value) {
        if (key is! String || key.isEmpty) {
          return;
        }
        if (value is String && value.isNotEmpty) {
          // Legacy schema — name as bare string. Stamp current time so
          // freshly migrated entries are not immediately considered
          // stale by [cleanup].
          result[key] = _Entry(name: value, lastUsedAt: nowForLegacy);
        } else if (value is Map<dynamic, dynamic>) {
          final Object? nameValue = value['name'];
          final Object? lastUsedValue = value['lastUsedAt'];
          if (nameValue is String && nameValue.isNotEmpty) {
            final int lastUsedAt = lastUsedValue is int
                ? lastUsedValue
                : nowForLegacy;
            result[key] = _Entry(name: nameValue, lastUsedAt: lastUsedAt);
          }
        }
      });
      return result;
    } on Object catch (e) {
      developer.log(
        'Failed to parse broadcaster names cache: $e',
        name: 'BroadcasterNameStore',
      );
      return <String, _Entry>{};
    }
  }

  /// Best-effort detection of legacy on-disk format — only used to decide
  /// whether [cleanup] should rewrite even when nothing is removed (so
  /// the schema migration sticks). Conservative: any parse failure or
  /// unexpected shape returns false so we never rewrite blindly.
  bool _isLegacyOnDisk() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return false;
    }
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map<dynamic, dynamic>) {
        return false;
      }
      for (final Object? value in decoded.values) {
        if (value is String) {
          return true;
        }
      }
      return false;
    } on Object {
      return false;
    }
  }

  String _encode(Map<String, _Entry> entries) {
    final Map<String, Map<String, Object>> serialised =
        <String, Map<String, Object>>{};
    entries.forEach((String id, _Entry entry) {
      serialised[id] = <String, Object>{
        'name': entry.name,
        'lastUsedAt': entry.lastUsedAt,
      };
    });
    return json.encode(serialised);
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final Future<T> scheduled = _pendingWriteChain.then<T>((_) => operation());
    _pendingWriteChain = scheduled.then<void>((_) {}).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      // Swallow to keep the chain alive for subsequent writes — but
      // log so a sustained failure (disk full / serialisation bug)
      // is not invisible. This mirrors the AGENTS.md "no silent
      // catch" rule while preserving the chain-recovery guarantee.
      developer.log(
        'Write chain step failed; continuing with subsequent writes',
        name: 'BroadcasterNameStore',
        error: error,
        stackTrace: stackTrace,
      );
    });
    return scheduled;
  }
}

/// Internal value object: pairs a broadcaster's display name with the
/// epoch-ms timestamp of its last access. Kept private so the on-disk
/// schema is an internal detail of the store.
class _Entry {
  const _Entry({required this.name, required this.lastUsedAt});

  final String name;
  final int lastUsedAt;
}
