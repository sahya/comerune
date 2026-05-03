import 'dart:convert';
import 'dart:developer' as developer;

import '../../application/settings/settings_store.dart';
import '../../domain/models/ng_word_rule.dart';

/// Issue #727: payload returned by [BroadcasterNgStore.loadBroadcasterNgAttributes].
///
/// Pure (broadcasterId-less) per-broadcaster NG attributes, used by load
/// and save callers that already know which broadcaster the values
/// belong to.
typedef BroadcasterNgPayload = ({
  Set<String> ngUserIds,
  List<NgWordRule> rules,
});

/// Issue #727: in-memory tagged variant of [BroadcasterNgPayload].
///
/// The `broadcasterId` field tags which broadcaster the [ngUserIds] and
/// [rules] belong to so consumers can compare it against the currently
/// active broadcaster to detect stale async loads. `null` means
/// "no snapshot loaded" (initial state, or after disconnect/clear).
typedef BroadcasterNgSnapshot = ({
  String? broadcasterId,
  Set<String> ngUserIds,
  List<NgWordRule> rules,
});

/// Persists per-broadcaster NG user IDs and NG word rules.
///
/// Broadcasters inherit the global "template" until the user performs a
/// broadcaster-specific write. Reads return the effective values (slot when it
/// exists, template otherwise) without creating a new per-broadcaster slot.
/// The slot is created only when the user actually customizes that
/// broadcaster's settings.
///
/// Implementation notes:
/// - Modeled after `UserAttributeStore`: writes go through a serial chain so
///   concurrent callers cannot interleave a partial read-modify-write.
/// - Storage layout (SharedPreferences keys):
///     `settings.filter.broadcaster.<id>.ngUserIds` — JSON string array
///     `settings.filter.broadcaster.<id>.ngWordRules` — JSON [{pattern,enabled}]
///     `settings.filter.broadcaster.<id>.initialized` — `'true'` after seeding
///     `settings.filter.template.ngUserIds` — JSON string array
///     `settings.filter.template.ngWordRules` — JSON [{pattern,enabled}]
///     `settings.filter.broadcaster._index` — JSON list of broadcaster IDs
///
abstract class BroadcasterNgStore {
  /// Returns NG user IDs for [broadcasterId].
  ///
  /// Returns the effective NG user IDs for [broadcasterId]: the
  /// per-broadcaster slot when initialized, otherwise the template.
  Future<Set<String>> loadNgUserIds(String broadcasterId);

  /// Returns the effective NG word rules for [broadcasterId]: the
  /// per-broadcaster slot when initialized, otherwise the template.
  Future<List<NgWordRule>> loadNgWordRules(String broadcasterId);

  /// Combined load that minimizes I/O round-trips. Returns the effective
  /// per-broadcaster snapshot: the broadcaster slot when initialized,
  /// otherwise the template fallback without persisting a new slot.
  Future<BroadcasterNgPayload> loadBroadcasterNgAttributes(
    String broadcasterId,
  );

  /// Replace all NG user IDs for [broadcasterId].
  Future<void> saveNgUserIds(String broadcasterId, Iterable<String> ids);

  /// Replace all NG word rules for [broadcasterId].
  Future<void> saveNgWordRules(String broadcasterId, List<NgWordRule> rules);

  /// Add a single NG user (long-press flow). Idempotent.
  Future<void> addNgUserId(String broadcasterId, String userId);

  /// Remove a single NG user. Idempotent.
  Future<void> removeNgUserId(String broadcasterId, String userId);

  /// Template = seed for any future broadcaster's first customization.
  Future<Set<String>> loadTemplateNgUserIds();

  Future<List<NgWordRule>> loadTemplateNgWordRules();

  Future<void> saveTemplateNgUserIds(Iterable<String> ids);

  Future<void> saveTemplateNgWordRules(List<NgWordRule> rules);

  /// Ordered list of broadcaster IDs that have per-broadcaster slots.
  List<String> listBroadcasters();

  /// Waits for any in-flight persistence writes to complete.
  Future<void> flushPendingWrites();
}

class SharedPreferencesBroadcasterNgStore implements BroadcasterNgStore {
  SharedPreferencesBroadcasterNgStore({required SharedPreferencesLike prefs})
    : _prefs = prefs;

  final SharedPreferencesLike _prefs;
  Future<void> _pendingWriteChain = Future<void>.value();

  static const String _broadcasterKeyPrefix = 'settings.filter.broadcaster.';
  static const String _ngUserIdsSuffix = '.ngUserIds';
  static const String _ngWordRulesSuffix = '.ngWordRules';
  static const String _initializedSuffix = '.initialized';
  static const String _indexKey = 'settings.filter.broadcaster._index';
  static const String _templateNgUserIdsKey =
      'settings.filter.template.ngUserIds';
  static const String _templateNgWordRulesKey =
      'settings.filter.template.ngWordRules';

  /// Number of leading characters of a broadcaster ID kept verbatim in
  /// redacted log output. Anything past this prefix is replaced with
  /// `***` so device logs / crash reports never carry the full ID.
  static const int _redactPrefixLength = 4;

  static String _ngUserIdsKey(String broadcasterId) =>
      '$_broadcasterKeyPrefix$broadcasterId$_ngUserIdsSuffix';

  static String _ngWordRulesKey(String broadcasterId) =>
      '$_broadcasterKeyPrefix$broadcasterId$_ngWordRulesSuffix';

  static String _initializedKey(String broadcasterId) =>
      '$_broadcasterKeyPrefix$broadcasterId$_initializedSuffix';

  static void _validateBroadcasterId(String broadcasterId) {
    if (broadcasterId.isEmpty) {
      throw ArgumentError.value(
        broadcasterId,
        'broadcasterId',
        'must not be empty',
      );
    }
  }

  @override
  Future<Set<String>> loadNgUserIds(String broadcasterId) async {
    _validateBroadcasterId(broadcasterId);
    return _readNgUserIds(_effectiveNgUserIdsKey(broadcasterId));
  }

  @override
  Future<List<NgWordRule>> loadNgWordRules(String broadcasterId) async {
    _validateBroadcasterId(broadcasterId);
    return _readNgWordRules(_effectiveNgWordRulesKey(broadcasterId));
  }

  @override
  Future<BroadcasterNgPayload> loadBroadcasterNgAttributes(
    String broadcasterId,
  ) async {
    _validateBroadcasterId(broadcasterId);
    final Set<String> ids = _readNgUserIds(
      _effectiveNgUserIdsKey(broadcasterId),
    );
    final List<NgWordRule> rules = _readNgWordRules(
      _effectiveNgWordRulesKey(broadcasterId),
    );
    return (ngUserIds: ids, rules: rules);
  }

  @override
  Future<void> saveNgUserIds(String broadcasterId, Iterable<String> ids) async {
    _validateBroadcasterId(broadcasterId);
    await _enqueueWrite(() async {
      await _ensureInitializedInline(broadcasterId);
      await _persistInitializedSlotState(
        broadcasterId: broadcasterId,
        ids: _normalizeIds(ids),
        rules: _readNgWordRules(_ngWordRulesKey(broadcasterId)),
      );
    });
  }

  @override
  Future<void> saveNgWordRules(
    String broadcasterId,
    List<NgWordRule> rules,
  ) async {
    _validateBroadcasterId(broadcasterId);
    await _enqueueWrite(() async {
      await _ensureInitializedInline(broadcasterId);
      await _persistInitializedSlotState(
        broadcasterId: broadcasterId,
        ids: _readNgUserIds(_ngUserIdsKey(broadcasterId)).toList(),
        rules: rules,
      );
    });
  }

  @override
  Future<void> addNgUserId(String broadcasterId, String userId) async {
    _validateBroadcasterId(broadcasterId);
    if (userId.isEmpty) {
      return;
    }
    await _enqueueWrite(() async {
      await _ensureInitializedInline(broadcasterId);
      final Set<String> current = _readNgUserIds(_ngUserIdsKey(broadcasterId));
      if (current.contains(userId)) {
        return;
      }
      await _persistInitializedSlotState(
        broadcasterId: broadcasterId,
        ids: <String>[...current, userId],
        rules: _readNgWordRules(_ngWordRulesKey(broadcasterId)),
      );
    });
  }

  @override
  Future<void> removeNgUserId(String broadcasterId, String userId) async {
    _validateBroadcasterId(broadcasterId);
    if (userId.isEmpty) {
      return;
    }
    await _enqueueWrite(() async {
      await _ensureInitializedInline(broadcasterId);
      final Set<String> current = _readNgUserIds(_ngUserIdsKey(broadcasterId));
      if (!current.contains(userId)) {
        return;
      }
      final List<String> updated = current
          .where((String id) => id != userId)
          .toList();
      await _persistInitializedSlotState(
        broadcasterId: broadcasterId,
        ids: updated,
        rules: _readNgWordRules(_ngWordRulesKey(broadcasterId)),
      );
    });
  }

  @override
  Future<Set<String>> loadTemplateNgUserIds() async {
    return _readNgUserIds(_templateNgUserIdsKey);
  }

  @override
  Future<List<NgWordRule>> loadTemplateNgWordRules() async {
    return _readNgWordRules(_templateNgWordRulesKey);
  }

  @override
  Future<void> saveTemplateNgUserIds(Iterable<String> ids) async {
    await _enqueueWrite(() async {
      await _prefs.setString(
        _templateNgUserIdsKey,
        json.encode(_normalizeIds(ids)),
      );
    });
  }

  @override
  Future<void> saveTemplateNgWordRules(List<NgWordRule> rules) async {
    await _enqueueWrite(() async {
      await _prefs.setString(
        _templateNgWordRulesKey,
        json.encode(rules.map((NgWordRule r) => r.toMap()).toList()),
      );
    });
  }

  @override
  List<String> listBroadcasters() => _readIndex();

  @override
  Future<void> flushPendingWrites() => _pendingWriteChain;

  bool _isInitialized(String broadcasterId) =>
      _prefs.getString(_initializedKey(broadcasterId)) == 'true';

  String _effectiveNgUserIdsKey(String broadcasterId) {
    return _isInitialized(broadcasterId)
        ? _ngUserIdsKey(broadcasterId)
        : _templateNgUserIdsKey;
  }

  String _effectiveNgWordRulesKey(String broadcasterId) {
    return _isInitialized(broadcasterId)
        ? _ngWordRulesKey(broadcasterId)
        : _templateNgWordRulesKey;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Seeds a broadcaster slot from the template inside the write chain.
  ///
  /// Called only by broadcaster-specific write operations so simply reading a
  /// connected broadcaster never creates a persistent slot.
  Future<void> _ensureInitializedInline(String broadcasterId) async {
    if (_isInitialized(broadcasterId)) {
      return;
    }
    final Set<String> templateIds = _readNgUserIds(_templateNgUserIdsKey);
    final List<NgWordRule> templateRules = _readNgWordRules(
      _templateNgWordRulesKey,
    );
    await _prefs.setString(
      _ngUserIdsKey(broadcasterId),
      json.encode(templateIds.toList()),
    );
    await _prefs.setString(
      _ngWordRulesKey(broadcasterId),
      json.encode(templateRules.map((NgWordRule r) => r.toMap()).toList()),
    );
    await _prefs.setString(_initializedKey(broadcasterId), 'true');
    await _addToIndex(broadcasterId);
  }

  Future<void> _persistInitializedSlotState({
    required String broadcasterId,
    required List<String> ids,
    required List<NgWordRule> rules,
  }) async {
    if (ids.isEmpty && rules.isEmpty) {
      await _removeBroadcasterSlot(broadcasterId);
      return;
    }
    await _prefs.setString(_ngUserIdsKey(broadcasterId), json.encode(ids));
    await _prefs.setString(
      _ngWordRulesKey(broadcasterId),
      json.encode(rules.map((NgWordRule r) => r.toMap()).toList()),
    );
    await _prefs.setString(_initializedKey(broadcasterId), 'true');
    await _addToIndex(broadcasterId);
  }

  Future<void> _removeBroadcasterSlot(String broadcasterId) async {
    await _prefs.remove(_ngUserIdsKey(broadcasterId));
    await _prefs.remove(_ngWordRulesKey(broadcasterId));
    await _prefs.remove(_initializedKey(broadcasterId));
    await _removeFromIndex(broadcasterId);
  }

  Set<String> _readNgUserIds(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <String>{};
    }
    try {
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      return decoded.whereType<String>().toSet();
    } on Object catch (e) {
      developer.log(
        'Failed to parse NG user IDs at ${_redactKey(key)}: $e',
        name: 'BroadcasterNgStore',
      );
      return <String>{};
    }
  }

  List<NgWordRule> _readNgWordRules(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <NgWordRule>[];
    }
    try {
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (Map<dynamic, dynamic> e) =>
                NgWordRule.fromMap(e.cast<String, dynamic>()),
          )
          .toList();
    } on Object catch (e) {
      developer.log(
        'Failed to parse NG word rules at ${_redactKey(key)}: $e',
        name: 'BroadcasterNgStore',
      );
      return <NgWordRule>[];
    }
  }

  /// Redacts the broadcaster-id segment of a per-broadcaster preferences
  /// key for developer-log output, so error messages do not leak full IDs
  /// into device logs or crash reports.
  static String _redactKey(String key) {
    if (!key.startsWith(_broadcasterKeyPrefix)) {
      return key;
    }
    final String tail = key.substring(_broadcasterKeyPrefix.length);
    final int dot = tail.indexOf('.');
    final String idPart = dot < 0 ? tail : tail.substring(0, dot);
    final String suffix = dot < 0 ? '' : tail.substring(dot);
    final String redactedId = idPart.length > _redactPrefixLength
        ? '${idPart.substring(0, _redactPrefixLength)}***'
        : '***';
    return '$_broadcasterKeyPrefix$redactedId$suffix';
  }

  List<String> _normalizeIds(Iterable<String> ids) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String id in ids) {
      if (id.isEmpty) {
        continue;
      }
      if (seen.add(id)) {
        result.add(id);
      }
    }
    return result;
  }

  List<String> _readIndex() {
    final String? raw = _prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) {
      return <String>[];
    }
    try {
      final List<dynamic> decoded = json.decode(raw) as List<dynamic>;
      return decoded.whereType<String>().toList();
    } on Object {
      return <String>[];
    }
  }

  Future<void> _addToIndex(String broadcasterId) async {
    final List<String> index = _readIndex();
    if (index.contains(broadcasterId)) {
      return;
    }
    index.add(broadcasterId);
    await _prefs.setString(_indexKey, json.encode(index));
  }

  Future<void> _removeFromIndex(String broadcasterId) async {
    final List<String> remaining = _readIndex()
        .where((String id) => id != broadcasterId)
        .toList();
    if (remaining.isEmpty) {
      await _prefs.remove(_indexKey);
      return;
    }
    await _prefs.setString(_indexKey, json.encode(remaining));
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final Future<T> scheduled = _pendingWriteChain.then<T>((_) => operation());
    _pendingWriteChain = scheduled
        .then<void>((_) {})
        .catchError((Object error, StackTrace stackTrace) {});
    return scheduled;
  }
}
