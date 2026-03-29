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
      await prefs.setString(
        'usercolor.b1',
        '{"u1": 123, "u2": "bad", "_lastUsedAt": 999}',
      );

      final Map<String, int> result = await store.load('b1');
      expect(result, <String, int>{'u1': 123});
    });

    test('load does not expose _lastUsedAt as a color entry', () async {
      await store.setColor(
        broadcasterId: 'b1',
        userId: 'u1',
        colorValue: 0xFFE53935,
      );

      final Map<String, int> result = await store.load('b1');
      expect(result.containsKey('_lastUsedAt'), isFalse);
      expect(result, <String, int>{'u1': 0xFFE53935});
    });

    test('load updates _lastUsedAt so entry survives cleanup', () async {
      // Create an entry with a timestamp just over 365 days ago.
      final int oldTimestamp = DateTime.now()
          .subtract(const Duration(days: 366))
          .millisecondsSinceEpoch;
      await prefs.setString(
        'usercolor.aging',
        '{"u1": 111, "_lastUsedAt": $oldTimestamp}',
      );
      await prefs.setString('usercolor._index', '["aging"]');

      // Access via load() — this should refresh _lastUsedAt to now.
      await store.load('aging');

      // Cleanup with default 365-day maxAge should NOT remove it.
      final int removed = await store.cleanup();
      expect(removed, 0);
      expect(await store.load('aging'), <String, int>{'u1': 111});
    });

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
        final Map<String, int> result = await store.load('recent');
        expect(result, <String, int>{'u1': 0xFFE53935});
      });

      test('removes old entries and keeps recent ones', () async {
        // Old entry: manually write with old timestamp.
        final int oldTimestamp = DateTime.now()
            .subtract(const Duration(days: 400))
            .millisecondsSinceEpoch;
        await prefs.setString(
          'usercolor.old_b',
          '{"u1": 111, "_lastUsedAt": $oldTimestamp}',
        );

        // Recent entry via setColor (auto-sets current timestamp).
        await store.setColor(
          broadcasterId: 'new_b',
          userId: 'u2',
          colorValue: 222,
        );

        // Set the index to include both.
        await prefs.setString('usercolor._index', '["old_b", "new_b"]');

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(prefs.getString('usercolor.old_b'), isNull);
        expect(await store.load('new_b'), <String, int>{'u2': 222});
      });

      test('returns 0 when index is empty', () async {
        final int removed = await store.cleanup();
        expect(removed, 0);
      });

      test('removes entry with missing _lastUsedAt (treated as epoch 0)',
          () async {
        await prefs.setString('usercolor.no_ts', '{"u1": 123}');
        await prefs.setString('usercolor._index', '["no_ts"]');

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(prefs.getString('usercolor.no_ts'), isNull);
      });

      test('custom maxAge is respected', () async {
        // Entry from 10 days ago.
        final int recentTimestamp = DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch;
        await prefs.setString(
          'usercolor.ten_days',
          '{"u1": 111, "_lastUsedAt": $recentTimestamp}',
        );
        await prefs.setString('usercolor._index', '["ten_days"]');

        // maxAge=365 days: should keep.
        expect(await store.cleanup(), 0);

        // maxAge=5 days: should remove.
        expect(
          await store.cleanup(maxAge: const Duration(days: 5)),
          1,
        );
        expect(prefs.getString('usercolor.ten_days'), isNull);
      });
    });
  });
}
