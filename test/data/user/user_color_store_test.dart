import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/data/user/user_color_store.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesUserColorStore', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesUserColorStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesUserColorStore(prefs: prefs);
    });

    test('load returns empty map when no data exists', () async {
      final Map<String, int> result = await store.load('broadcaster1');
      expect(result, isEmpty);
    });

    test('setColor stores and load retrieves it', () async {
      await store.setColor(
        broadcasterId: 'broadcaster1',
        userId: 'user1',
        colorValue: 0xFFE53935,
      );

      final Map<String, int> result = await store.load('broadcaster1');
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

      final Map<String, int> result = await store.load('b1');
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

      final Map<String, int> result = await store.load('b1');
      expect(result, <String, int>{'u1': 0xFF1E88E5});
    });

    test('different broadcasters have independent color maps', () async {
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
        await store.load('b1'),
        <String, int>{'u1': 0xFFE53935},
      );
      expect(
        await store.load('b2'),
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

      final Map<String, int> result = await store.load('b1');
      expect(result, <String, int>{'u2': 0xFF1E88E5});
    });

    test('removeColor is a no-op when user has no color', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      await store.removeColor(broadcasterId: 'b1', userId: 'u999');

      final Map<String, int> result = await store.load('b1');
      expect(result, <String, int>{'u1': 0xFFE53935});
    });

    test('load returns empty map when stored JSON is invalid', () async {
      await prefs.setString('usercolor.b1', 'not-json');

      final Map<String, int> result = await store.load('b1');
      expect(result, isEmpty);
    });

    test('load ignores non-int values in JSON', () async {
      await prefs.setString('usercolor.b1', '{"u1": 123, "u2": "bad"}');

      final Map<String, int> result = await store.load('b1');
      expect(result, <String, int>{'u1': 123});
    });
  });
}
