import 'package:comerune/data/user/user_attribute_store.dart';

/// A simple in-memory [UserAttributeStore] for testing.
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
