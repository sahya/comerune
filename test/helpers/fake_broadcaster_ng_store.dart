import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';

/// Issue #727: in-memory fake [BroadcasterNgStore] for widget tests.
///
/// Mirrors the contract enough for the management screens to read /
/// write. Keeps insertion order deterministic via list-backed storage so
/// tests can assert on order.
class FakeBroadcasterNgStore implements BroadcasterNgStore {
  final Map<String, Set<String>> _ngUserIds = <String, Set<String>>{};
  final Map<String, List<NgWordRule>> _ngWordRules =
      <String, List<NgWordRule>>{};
  final List<String> _broadcasters = <String>[];
  Set<String> _templateUserIds = <String>{};
  List<NgWordRule> _templateRules = <NgWordRule>[];

  void seedTemplate({
    Set<String> userIds = const <String>{},
    List<NgWordRule> rules = const <NgWordRule>[],
  }) {
    _templateUserIds = userIds.toSet();
    _templateRules = List<NgWordRule>.from(rules);
  }

  void seedBroadcaster(
    String broadcasterId, {
    Set<String> userIds = const <String>{},
    List<NgWordRule> rules = const <NgWordRule>[],
  }) {
    _ngUserIds[broadcasterId] = userIds.toSet();
    _ngWordRules[broadcasterId] = List<NgWordRule>.from(rules);
    if (!_broadcasters.contains(broadcasterId)) {
      _broadcasters.add(broadcasterId);
    }
  }

  @override
  Future<void> addNgUserId(String broadcasterId, String userId) async {
    (_ngUserIds[broadcasterId] ??= <String>{}).add(userId);
    if (!_broadcasters.contains(broadcasterId)) {
      _broadcasters.add(broadcasterId);
    }
  }

  @override
  Future<void> flushPendingWrites() async {}

  @override
  List<String> listBroadcasters() => List<String>.from(_broadcasters);

  @override
  Future<BroadcasterNgPayload> loadBroadcasterNgAttributes(
    String broadcasterId,
  ) async {
    return (
      ngUserIds: _ngUserIds[broadcasterId] ?? <String>{},
      rules: _ngWordRules[broadcasterId] ?? <NgWordRule>[],
    );
  }

  @override
  Future<Set<String>> loadNgUserIds(String broadcasterId) async {
    return _ngUserIds[broadcasterId] ?? _templateUserIds.toSet();
  }

  @override
  Future<List<NgWordRule>> loadNgWordRules(String broadcasterId) async {
    return _ngWordRules[broadcasterId] ?? List<NgWordRule>.from(_templateRules);
  }

  @override
  Future<Set<String>> loadTemplateNgUserIds() async => _templateUserIds.toSet();

  @override
  Future<List<NgWordRule>> loadTemplateNgWordRules() async =>
      List<NgWordRule>.from(_templateRules);

  @override
  Future<void> removeNgUserId(String broadcasterId, String userId) async {
    _ngUserIds[broadcasterId]?.remove(userId);
  }

  @override
  Future<void> saveNgUserIds(String broadcasterId, Iterable<String> ids) async {
    _ngUserIds[broadcasterId] = ids.toSet();
    if (!_broadcasters.contains(broadcasterId)) {
      _broadcasters.add(broadcasterId);
    }
  }

  @override
  Future<void> saveNgWordRules(
    String broadcasterId,
    List<NgWordRule> rules,
  ) async {
    _ngWordRules[broadcasterId] = List<NgWordRule>.from(rules);
    if (!_broadcasters.contains(broadcasterId)) {
      _broadcasters.add(broadcasterId);
    }
  }

  @override
  Future<void> saveTemplateNgUserIds(Iterable<String> ids) async {
    _templateUserIds = ids.toSet();
  }

  @override
  Future<void> saveTemplateNgWordRules(List<NgWordRule> rules) async {
    _templateRules = List<NgWordRule>.from(rules);
  }
}
