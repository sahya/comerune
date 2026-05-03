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
}

/// SharedPreferences-backed implementation of [BroadcasterNameStore].
///
/// Storage layout:
/// - Single SharedPreferences key: `broadcaster.names`
/// - JSON object: `{"<broadcasterId>": "<name>", ...}`
/// - Defensive parsing: malformed JSON returns an empty map.
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

  final SharedPreferencesLike _prefs;
  Future<void> _pendingWriteChain = Future<void>.value();

  @override
  Future<void> setName(String broadcasterId, String name) async {
    if (broadcasterId.isEmpty || name.isEmpty) {
      return;
    }
    await _enqueueWrite(() async {
      final Map<String, String> current = _readAll();
      if (current[broadcasterId] == name) {
        return;
      }
      current[broadcasterId] = name;
      await _prefs.setString(_storageKey, json.encode(current));
    });
  }

  @override
  String? loadName(String broadcasterId) {
    if (broadcasterId.isEmpty) {
      return null;
    }
    return _readAll()[broadcasterId];
  }

  @override
  Map<String, String> loadAll() => _readAll();

  Map<String, String> _readAll() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return <String, String>{};
    }
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! Map<dynamic, dynamic>) {
        return <String, String>{};
      }
      final Map<String, String> result = <String, String>{};
      decoded.forEach((Object? key, Object? value) {
        if (key is String && value is String && key.isNotEmpty) {
          result[key] = value;
        }
      });
      return result;
    } on Object catch (e) {
      developer.log(
        'Failed to parse broadcaster names cache: $e',
        name: 'BroadcasterNameStore',
      );
      return <String, String>{};
    }
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final Future<T> scheduled = _pendingWriteChain.then<T>((_) => operation());
    _pendingWriteChain = scheduled
        .then<void>((_) {})
        .catchError((Object error, StackTrace stackTrace) {});
    return scheduled;
  }
}
