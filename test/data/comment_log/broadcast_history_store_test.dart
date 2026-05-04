import 'package:comerune/data/comment_log/broadcast_history_store.dart';
import 'package:comerune/domain/comment_log/broadcast_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

BroadcastHistoryEntry _entry(
  String lv, {
  DateTime? recordedAt,
  int totalComments = 1,
  int uniqueUserCount = 1,
  int durationSeconds = 60,
}) {
  return BroadcastHistoryEntry(
    lv: lv,
    recordedAt: recordedAt ?? DateTime.utc(2026, 5, 1, 12, 0),
    totalComments: totalComments,
    uniqueUserCount: uniqueUserCount,
    durationSeconds: durationSeconds,
  );
}

void main() {
  group('SharedPreferencesBroadcastHistoryStore', () {
    test('add then loadAll returns the entry', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await store.add(_entry('lv1'));

      final List<BroadcastHistoryEntry> all = store.loadAll();
      expect(all, hasLength(1));
      expect(all.first.lv, 'lv1');
    });

    test('add inserts new entries at the head (newest first)', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await store.add(_entry('lv1', recordedAt: DateTime.utc(2026, 5, 1)));
      await store.add(_entry('lv2', recordedAt: DateTime.utc(2026, 5, 2)));
      await store.add(_entry('lv3', recordedAt: DateTime.utc(2026, 5, 3)));

      final List<String> lvs = store
          .loadAll()
          .map((BroadcastHistoryEntry e) => e.lv)
          .toList();
      expect(lvs, <String>['lv3', 'lv2', 'lv1']);
    });

    test(
      'add with same lv replaces the existing entry (no duplicates)',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesBroadcastHistoryStore store =
            SharedPreferencesBroadcastHistoryStore(prefs: prefs);

        await store.add(_entry('lv1', totalComments: 1));
        await store.add(_entry('lv1', totalComments: 99));

        final List<BroadcastHistoryEntry> all = store.loadAll();
        expect(all, hasLength(1));
        expect(all.first.totalComments, 99);
      },
    );

    test('respects the maxEntries cap (oldest dropped)', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs, maxEntries: 3);

      for (int i = 1; i <= 5; i++) {
        await store.add(_entry('lv$i', recordedAt: DateTime.utc(2026, 5, i)));
      }

      final List<String> lvs = store
          .loadAll()
          .map((BroadcastHistoryEntry e) => e.lv)
          .toList();
      expect(lvs, <String>['lv5', 'lv4', 'lv3']);
    });

    test('removeByLv removes only the matching entry', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await store.add(_entry('lv1'));
      await store.add(_entry('lv2'));
      await store.add(_entry('lv3'));

      await store.removeByLv('lv2');

      final List<String> lvs = store
          .loadAll()
          .map((BroadcastHistoryEntry e) => e.lv)
          .toList();
      expect(lvs, <String>['lv3', 'lv1']);
    });

    test('removeByLv with empty string is a no-op', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await store.add(_entry('lv1'));
      await store.removeByLv('');

      expect(store.loadAll(), hasLength(1));
    });

    test('clearAll removes everything and is idempotent', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await store.add(_entry('lv1'));
      await store.add(_entry('lv2'));

      await store.clearAll();
      expect(store.loadAll(), isEmpty);

      // Calling again should not throw or write back any state.
      await store.clearAll();
      expect(store.loadAll(), isEmpty);
    });

    test('loadAll on empty storage returns an empty list (no exception)', () {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);
      expect(store.loadAll(), isEmpty);
    });

    test(
      'loadAll on malformed JSON returns empty list and does not throw',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        await prefs.setString(
          SharedPreferencesBroadcastHistoryStore.storageKey,
          'not-json',
        );
        final SharedPreferencesBroadcastHistoryStore store =
            SharedPreferencesBroadcastHistoryStore(prefs: prefs);

        expect(store.loadAll(), isEmpty);
      },
    );

    test(
      'loadAll skips entries that fail validation but keeps the rest',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        // Mix one well-formed entry with one bad shape.
        await prefs.setString(
          SharedPreferencesBroadcastHistoryStore.storageKey,
          '['
          '{"lv":"lv1","recordedAt":"2026-05-01T00:00:00Z",'
          '"totalComments":1,"uniqueUserCount":1,"durationSeconds":1},'
          '"not-an-object"'
          ']',
        );
        final SharedPreferencesBroadcastHistoryStore store =
            SharedPreferencesBroadcastHistoryStore(prefs: prefs);
        final List<BroadcastHistoryEntry> all = store.loadAll();
        expect(all, hasLength(1));
        expect(all.first.lv, 'lv1');
      },
    );

    test('concurrent add() calls all land without losing entries', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      await Future.wait<void>(<Future<void>>[
        store.add(_entry('lv101', recordedAt: DateTime.utc(2026, 5, 1, 1))),
        store.add(_entry('lv102', recordedAt: DateTime.utc(2026, 5, 1, 2))),
        store.add(_entry('lv103', recordedAt: DateTime.utc(2026, 5, 1, 3))),
      ]);

      final List<String> lvs =
          store
              .loadAll()
              .map((BroadcastHistoryEntry e) => e.lv)
              .toSet()
              .toList()
            ..sort();
      expect(lvs, <String>['lv101', 'lv102', 'lv103']);
    });

    test(
      'concurrent add() preserves enqueue order at the head (newest first)',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesBroadcastHistoryStore store =
            SharedPreferencesBroadcastHistoryStore(prefs: prefs);

        // Enqueue order: 1 → 2 → 3. The serial chain guarantees the
        // last-enqueued add runs last and lands at the head.
        await Future.wait<void>(<Future<void>>[
          store.add(_entry('lv1001', recordedAt: DateTime.utc(2026, 5, 1, 1))),
          store.add(_entry('lv1002', recordedAt: DateTime.utc(2026, 5, 1, 2))),
          store.add(_entry('lv1003', recordedAt: DateTime.utc(2026, 5, 1, 3))),
        ]);
        await store.flushPendingWrites();

        expect(store.loadAll().first.lv, 'lv1003');
      },
    );

    test('flushPendingWrites awaits in-flight serial writes', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore store =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);

      // Fire-and-forget add (mimicking the SelectScreen unawaited path).
      // ignore: unawaited_futures
      store.add(_entry('lv9001', recordedAt: DateTime.utc(2026, 5, 1)));
      await store.flushPendingWrites();

      expect(store.loadAll(), hasLength(1));
      expect(store.loadAll().first.lv, 'lv9001');
    });
  });
}
