import 'package:comerune/data/user/user_attribute_store.dart';

/// A simple in-memory [UserAttributeStore] for testing.
///
/// **Semantic differences from the production stores
/// ([FileUserAttributeStore] / [SharedPreferencesUserAttributeStore]):**
///
/// - Production stores hold colors and nicknames in a single raw JSON
///   payload per broadcaster. If the payload is empty (no entries written),
///   both `colors` and `nicknames` are simultaneously empty — they cannot
///   diverge. This fake stores them in two separate `Map`s, so it can
///   represent a state where only one of them has data for a broadcaster.
/// - This fake does not touch any `_lastUsedAt` timestamp; cleanup-by-age
///   semantics are not modelled here. Tests that need to verify the touch
///   behaviour should use the production stores directly (see
///   `test/data/user/`).
///
/// These differences are intentional and acceptable for widget/state tests
/// that only care about the in-memory contract of [UserAttributeStore].
class InMemoryUserAttributeStore implements UserAttributeStore {
  final Map<String, Map<String, int>> _colors = <String, Map<String, int>>{};
  final Map<String, Map<String, String>> _nicknames =
      <String, Map<String, String>>{};

  @override
  Future<Map<String, int>> loadColors(String broadcasterId) async {
    return Map<String, int>.from(
      _colors[broadcasterId] ?? const <String, int>{},
    );
  }

  @override
  Future<Map<String, String>> loadNicknames(String broadcasterId) async {
    return Map<String, String>.from(
      _nicknames[broadcasterId] ?? const <String, String>{},
    );
  }

  @override
  Future<UserAttributesSnapshot> loadAttributes(String broadcasterId) async {
    return (
      colors: Map<String, int>.from(
        _colors[broadcasterId] ?? const <String, int>{},
      ),
      nicknames: Map<String, String>.from(
        _nicknames[broadcasterId] ?? const <String, String>{},
      ),
    );
  }

  @override
  Future<void> setColor({
    required String broadcasterId,
    required String userId,
    required int colorValue,
  }) async {
    _colors.putIfAbsent(broadcasterId, () => <String, int>{})[userId] =
        colorValue;
  }

  @override
  Future<void> removeColor({
    required String broadcasterId,
    required String userId,
  }) async {
    _colors[broadcasterId]?.remove(userId);
  }

  @override
  Future<void> setNickname({
    required String broadcasterId,
    required String userId,
    required String nickname,
  }) async {
    _nicknames.putIfAbsent(broadcasterId, () => <String, String>{})[userId] =
        nickname;
  }

  @override
  Future<void> removeNickname({
    required String broadcasterId,
    required String userId,
  }) async {
    _nicknames[broadcasterId]?.remove(userId);
  }

  @override
  Future<int> cleanup({Duration maxAge = const Duration(days: 365)}) async {
    return 0;
  }

  @override
  Future<void> flushPendingWrites() async {}
}
