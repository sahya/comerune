import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/user/user_nickname_store.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesUserNicknameStore', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesUserNicknameStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesUserNicknameStore(prefs: prefs);
    });

    test('loadAll returns empty map when no data exists', () async {
      final Map<String, String> result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('setNickname stores and loadAll retrieves it', () async {
      await store.setNickname(userId: 'user1', nickname: 'たろう');

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'user1': 'たろう'});
    });

    test('setNickname for multiple users', () async {
      await store.setNickname(userId: 'u1', nickname: 'たろう');
      await store.setNickname(userId: 'u2', nickname: 'じろう');

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'u1': 'たろう', 'u2': 'じろう'});
    });

    test('setNickname overwrites existing nickname', () async {
      await store.setNickname(userId: 'u1', nickname: 'たろう');
      await store.setNickname(userId: 'u1', nickname: 'じろう');

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'u1': 'じろう'});
    });

    test('removeNickname removes the nickname for a user', () async {
      await store.setNickname(userId: 'u1', nickname: 'たろう');
      await store.setNickname(userId: 'u2', nickname: 'じろう');

      await store.removeNickname('u1');

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'u2': 'じろう'});
    });

    test('removeNickname is a no-op when user has no nickname', () async {
      await store.setNickname(userId: 'u1', nickname: 'たろう');

      await store.removeNickname('u999');

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'u1': 'たろう'});
    });

    test('loadAll returns empty map when stored JSON is invalid', () async {
      await prefs.setString('user_nicknames', 'not-json');

      final Map<String, String> result = await store.loadAll();
      expect(result, isEmpty);
    });

    test('loadAll ignores non-string values in JSON', () async {
      await prefs.setString(
        'user_nicknames',
        '{"u1": "たろう", "u2": 123, "u3": null}',
      );

      final Map<String, String> result = await store.loadAll();
      expect(result, <String, String>{'u1': 'たろう'});
    });

    test('data persists across store instances', () async {
      await store.setNickname(userId: 'u1', nickname: 'たろう');

      final SharedPreferencesUserNicknameStore store2 =
          SharedPreferencesUserNicknameStore(prefs: prefs);

      final Map<String, String> result = await store2.loadAll();
      expect(result, <String, String>{'u1': 'たろう'});
    });
  });
}
