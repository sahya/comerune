import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/user/user_attribute_store.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesUserAttributeStore', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesUserAttributeStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesUserAttributeStore(prefs: prefs);
    });

    // -----------------------------------------------------------------------
    // Color tests (backward compatible with UserColorStore)
    // -----------------------------------------------------------------------

    test('loadColors returns empty map when no data exists', () async {
      final Map<String, int> result = await store.loadColors('broadcaster1');
      expect(result, isEmpty);
    });

    test('setColor stores and loadColors retrieves it', () async {
      await store.setColor(
        broadcasterId: 'broadcaster1',
        userId: 'user1',
        colorValue: 0xFFE53935,
      );

      final Map<String, int> result = await store.loadColors('broadcaster1');
      expect(result, <String, int>{'user1': 0xFFE53935});
    });

    test('setColor for multiple users under same broadcaster', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u2',
        colorValue: 0xFF1E88E5,
      );

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, <String, int>{'u1': 0xFFE53935, 'u2': 0xFF1E88E5});
    });

    test('setColor overwrites existing color for same user', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFF1E88E5,
      );

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, <String, int>{'u1': 0xFF1E88E5});
    });

    test('different broadcasters have independent maps', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b2',
        userId: 'u1',
        colorValue: 0xFF1E88E5,
      );

      expect(
        await store.loadColors('b1'),
        <String, int>{'u1': 0xFFE53935},
      );
      expect(
        await store.loadColors('b2'),
        <String, int>{'u1': 0xFF1E88E5},
      );
    });

    test('removeColor removes the color for a user', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u2',
        colorValue: 0xFF1E88E5,
      );

      await store.removeColor(broadcasterId: 'b1', userId: 'u1');

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, <String, int>{'u2': 0xFF1E88E5});
    });

    test('removeColor is a no-op when user has no color', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      await store.removeColor(broadcasterId: 'b1', userId: 'u999');

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, <String, int>{'u1': 0xFFE53935});
    });

    test('loadColors returns empty map when stored JSON is invalid', () async {
      await prefs.setString('usercolor.b1', 'not-json');

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, isEmpty);
    });

    test('loadColors reads legacy int format', () async {
      // Legacy format from old UserColorStore: plain int values.
      await prefs.setString(
        'usercolor.b1',
        '{"u1": 123, "u2": "bad", "_lastUsedAt": 999}',
      );

      final Map<String, int> result = await store.loadColors('b1');
      expect(result, <String, int>{'u1': 123});
    });

    test('loadColors does not expose _lastUsedAt', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final Map<String, int> result = await store.loadColors('b1');
      expect(result.containsKey('_lastUsedAt'), isFalse);
    });

    // -----------------------------------------------------------------------
    // Nickname tests
    // -----------------------------------------------------------------------

    test('loadNicknames returns empty map when no data exists', () async {
      final Map<String, String> result =
          await store.loadNicknames('broadcaster1');
      expect(result, isEmpty);
    });

    test('setNickname stores and loadNicknames retrieves it', () async {
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      final Map<String, String> result = await store.loadNicknames('b1');
      expect(result, <String, String>{'u1': 'たろう'});
    });

    test('setNickname overwrites existing nickname', () async {
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'じろう',
      );

      final Map<String, String> result = await store.loadNicknames('b1');
      expect(result, <String, String>{'u1': 'じろう'});
    });

    test('removeNickname removes the nickname for a user', () async {
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      await store.removeNickname(broadcasterId: 'b1', userId: 'u1');

      final Map<String, String> result = await store.loadNicknames('b1');
      expect(result, isEmpty);
    });

    test('removeNickname is a no-op when user has no nickname', () async {
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      await store.removeNickname(broadcasterId: 'b1', userId: 'u999');

      final Map<String, String> result = await store.loadNicknames('b1');
      expect(result, <String, String>{'u1': 'たろう'});
    });

    // -----------------------------------------------------------------------
    // Mixed color + nickname tests
    // -----------------------------------------------------------------------

    test('color and nickname coexist for same user', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      expect(
        await store.loadColors('b1'),
        <String, int>{'u1': 0xFFE53935},
      );
      expect(
        await store.loadNicknames('b1'),
        <String, String>{'u1': 'たろう'},
      );
    });

    test('removeColor preserves nickname', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      await store.removeColor(broadcasterId: 'b1', userId: 'u1');

      expect(await store.loadColors('b1'), isEmpty);
      expect(
        await store.loadNicknames('b1'),
        <String, String>{'u1': 'たろう'},
      );
    });

    test('removeNickname preserves color', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      await store.removeNickname(broadcasterId: 'b1', userId: 'u1');

      expect(
        await store.loadColors('b1'),
        <String, int>{'u1': 0xFFE53935},
      );
      expect(await store.loadNicknames('b1'), isEmpty);
    });

    test('removing both color and nickname cleans up the user entry', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );
      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      await store.removeColor(broadcasterId: 'b1', userId: 'u1');
      await store.removeNickname(broadcasterId: 'b1', userId: 'u1');

      expect(await store.loadColors('b1'), isEmpty);
      expect(await store.loadNicknames('b1'), isEmpty);
    });

    // -----------------------------------------------------------------------
    // Backward compatibility with legacy data
    // -----------------------------------------------------------------------

    test('reads legacy int-only format as colors', () async {
      // Simulate data written by old UserColorStore.
      await prefs.setString(
        'usercolor.b1',
        '{"u1": 4293467445, "u2": 4280391909, "_lastUsedAt": 999}',
      );

      final Map<String, int> colors = await store.loadColors('b1');
      expect(colors, <String, int>{'u1': 4293467445, 'u2': 4280391909});

      final Map<String, String> nicknames = await store.loadNicknames('b1');
      expect(nicknames, isEmpty);
    });

    test('adding nickname to legacy color entry preserves color', () async {
      // Legacy color-only entry.
      await prefs.setString(
        'usercolor.b1',
        '{"u1": 4293467445, "_lastUsedAt": 999}',
      );

      await store.setNickname(
        broadcasterId: 'b1',
        userId: 'u1',
        nickname: 'たろう',
      );

      expect(
        await store.loadColors('b1'),
        <String, int>{'u1': 4293467445},
      );
      expect(
        await store.loadNicknames('b1'),
        <String, String>{'u1': 'たろう'},
      );
    });

    // -----------------------------------------------------------------------
    // Cleanup tests
    // -----------------------------------------------------------------------

    group('cleanup', () {
      test('removes entries older than maxAge', () async {
        final int oldTimestamp = DateTime.now()
            .subtract(const Duration(days: 400))
            .millisecondsSinceEpoch;
        await prefs.setString(
          'usercolor.old_broadcaster',
          '{"u1": 123, "_lastUsedAt": $oldTimestamp}',
        );
        await prefs.setString('usercolor._index', '["old_broadcaster"]');

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(prefs.getString('usercolor.old_broadcaster'), isNull);
      });

      test('keeps entries newer than maxAge', () async {
        await store.setColor(
          broadcasterId: 'recent',
          userId: 'u1',
          colorValue: 0xFFE53935,
        );

        final int removed = await store.cleanup();

        expect(removed, 0);
        final Map<String, int> result = await store.loadColors('recent');
        expect(result, <String, int>{'u1': 0xFFE53935});
      });

      test('returns 0 when index is empty', () async {
        final int removed = await store.cleanup();
        expect(removed, 0);
      });
    });
  });
}
