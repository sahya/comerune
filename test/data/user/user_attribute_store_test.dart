import 'dart:async';
import 'dart:collection';

import 'package:comerune/application/settings/settings_store.dart';
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

      expect(await store.loadColors('b1'), <String, int>{'u1': 0xFFE53935});
      expect(await store.loadColors('b2'), <String, int>{'u1': 0xFF1E88E5});
    });

    test(
      'flushPendingWrites waits for an in-flight persistence write',
      () async {
        final _DelayedSharedPreferences delayedPrefs =
            _DelayedSharedPreferences();
        store = SharedPreferencesUserAttributeStore(prefs: delayedPrefs);

        unawaited(
          store.setColor(
            broadcasterId: 'b1',
            userId: 'u1',
            colorValue: 0xFFE53935,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final Future<void> flushFuture = store.flushPendingWrites();
        bool flushCompleted = false;
        unawaited(
          flushFuture.then((_) {
            flushCompleted = true;
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(flushCompleted, isFalse);

        await delayedPrefs.drainWrites();
        await flushFuture;

        expect(
          delayedPrefs.getString('usercolor.b1'),
          contains('"u1":4293212469'),
        );
        expect(delayedPrefs.getString('usercolor._index'), '["b1"]');
      },
    );

    test(
      'loadColors touch does not overwrite a pending attribute write',
      () async {
        final _ControlledSharedPreferences controlledPrefs =
            _ControlledSharedPreferences()
              ..seedString('usercolor.b1', '{"existing":123,"_lastUsedAt":1}')
              ..seedString('usercolor._index', '["b1"]');
        store = SharedPreferencesUserAttributeStore(prefs: controlledPrefs);

        unawaited(
          store.setColor(
            broadcasterId: 'b1',
            userId: 'u1',
            colorValue: 0xFFE53935,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final Future<Map<String, int>> loadFuture = store.loadColors('b1');
        await Future<void>.delayed(Duration.zero);

        expect(controlledPrefs.pendingWriteCount, 1);

        await controlledPrefs.completeNextWrite();
        await Future<void>.delayed(Duration.zero);

        expect(controlledPrefs.pendingWriteCount, 1);

        await controlledPrefs.completeNextWrite();
        expect(await loadFuture, <String, int>{'existing': 123});

        expect(
          controlledPrefs.getString('usercolor.b1'),
          contains('"u1":4293212469'),
        );
        expect(
          controlledPrefs.getString('usercolor.b1'),
          contains('"existing":123'),
        );
      },
    );

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
      final Map<String, String> result = await store.loadNicknames(
        'broadcaster1',
      );
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

      expect(await store.loadColors('b1'), <String, int>{'u1': 0xFFE53935});
      expect(await store.loadNicknames('b1'), <String, String>{'u1': 'たろう'});
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
      expect(await store.loadNicknames('b1'), <String, String>{'u1': 'たろう'});
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

      expect(await store.loadColors('b1'), <String, int>{'u1': 0xFFE53935});
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

      expect(await store.loadColors('b1'), <String, int>{'u1': 4293467445});
      expect(await store.loadNicknames('b1'), <String, String>{'u1': 'たろう'});
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

      test('removes old entries and keeps recent ones', () async {
        final int oldTimestamp = DateTime.now()
            .subtract(const Duration(days: 400))
            .millisecondsSinceEpoch;
        await prefs.setString(
          'usercolor.old_b',
          '{"u1": 111, "_lastUsedAt": $oldTimestamp}',
        );

        await store.setColor(
          broadcasterId: 'new_b',
          userId: 'u2',
          colorValue: 222,
        );

        await prefs.setString('usercolor._index', '["old_b", "new_b"]');

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(prefs.getString('usercolor.old_b'), isNull);
        expect(await store.loadColors('new_b'), <String, int>{'u2': 222});
      });

      test('returns 0 when index is empty', () async {
        final int removed = await store.cleanup();
        expect(removed, 0);
      });

      test(
        'removes entry with missing _lastUsedAt (treated as epoch 0)',
        () async {
          await prefs.setString('usercolor.no_ts', '{"u1": 123}');
          await prefs.setString('usercolor._index', '["no_ts"]');

          final int removed = await store.cleanup();

          expect(removed, 1);
          expect(prefs.getString('usercolor.no_ts'), isNull);
        },
      );

      test('custom maxAge is respected', () async {
        final int recentTimestamp = DateTime.now()
            .subtract(const Duration(days: 10))
            .millisecondsSinceEpoch;
        await prefs.setString(
          'usercolor.ten_days',
          '{"u1": 111, "_lastUsedAt": $recentTimestamp}',
        );
        await prefs.setString('usercolor._index', '["ten_days"]');

        expect(await store.cleanup(), 0);

        expect(await store.cleanup(maxAge: const Duration(days: 5)), 1);
        expect(prefs.getString('usercolor.ten_days'), isNull);
      });

      test(
        'loadColors updates _lastUsedAt so entry survives cleanup',
        () async {
          final int oldTimestamp = DateTime.now()
              .subtract(const Duration(days: 366))
              .millisecondsSinceEpoch;
          await prefs.setString(
            'usercolor.aging',
            '{"u1": 111, "_lastUsedAt": $oldTimestamp}',
          );
          await prefs.setString('usercolor._index', '["aging"]');

          await store.loadColors('aging');

          final int removed = await store.cleanup();
          expect(removed, 0);
          expect(await store.loadColors('aging'), <String, int>{'u1': 111});
        },
      );
    });
  });
}

class _DelayedSharedPreferences implements SharedPreferencesLike {
  final Map<String, Object> _values = <String, Object>{};
  final Queue<void Function()> _pendingWrites = Queue<void Function()>();

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) {
    final Completer<bool> completer = Completer<bool>();
    _pendingWrites.add(() {
      _values[key] = value;
      completer.complete(true);
    });
    return completer.future;
  }

  @override
  Future<bool> remove(String key) {
    final Completer<bool> completer = Completer<bool>();
    _pendingWrites.add(() {
      _values.remove(key);
      completer.complete(true);
    });
    return completer.future;
  }

  Future<void> drainWrites() async {
    while (_pendingWrites.isNotEmpty) {
      _pendingWrites.removeFirst()();
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _ControlledSharedPreferences implements SharedPreferencesLike {
  final Map<String, Object> _values = <String, Object>{};
  final Queue<void Function()> _pendingWrites = Queue<void Function()>();

  int get pendingWriteCount => _pendingWrites.length;

  void seedString(String key, String value) {
    _values[key] = value;
  }

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  double? getDouble(String key) => _values[key] as double?;

  @override
  int? getInt(String key) => _values[key] as int?;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) {
    final Completer<bool> completer = Completer<bool>();
    _pendingWrites.add(() {
      _values[key] = value;
      completer.complete(true);
    });
    return completer.future;
  }

  @override
  Future<bool> remove(String key) {
    final Completer<bool> completer = Completer<bool>();
    _pendingWrites.add(() {
      _values.remove(key);
      completer.complete(true);
    });
    return completer.future;
  }

  Future<void> completeNextWrite() async {
    _pendingWrites.removeFirst()();
    await Future<void>.delayed(Duration.zero);
  }
}
