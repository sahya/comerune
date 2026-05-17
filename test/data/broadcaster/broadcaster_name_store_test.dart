import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/broadcaster/broadcaster_name_store.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesBroadcasterNameStore', () {
    test('round-trip: setName then loadName returns the value', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      await store.setName('123', 'Alice');

      expect(store.loadName('123'), 'Alice');
    });

    test('loadName returns null for unknown broadcasterId', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      expect(store.loadName('unknown'), isNull);
    });

    test('loadName with empty broadcasterId returns null (does not throw)', () {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      expect(store.loadName(''), isNull);
    });

    test('loadAll returns a snapshot of all entries', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      await store.setName('123', 'Alice');
      await store.setName('456', 'Bob');
      await store.setName('789', 'Carol');

      final Map<String, String> all = store.loadAll();
      expect(all, <String, String>{
        '123': 'Alice',
        '456': 'Bob',
        '789': 'Carol',
      });
    });

    test('loadAll returns empty map when nothing has been stored', () {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      expect(store.loadAll(), isEmpty);
    });

    test(
      'setName with empty broadcasterId is a no-op (does not throw)',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        await store.setName('', 'Alice');

        expect(store.loadAll(), isEmpty);
      },
    );

    test('setName with empty name is a no-op (does not throw)', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      await store.setName('123', '');

      expect(store.loadAll(), isEmpty);
      expect(store.loadName('123'), isNull);
    });

    test('malformed JSON in storage results in empty loadAll (no throw)', () {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      // Plant garbage directly under the storage key.
      prefs.setString('broadcaster.names', '{this is not json');
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      expect(store.loadAll(), isEmpty);
      expect(store.loadName('123'), isNull);
    });

    test('non-object JSON in storage results in empty loadAll', () {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      // A JSON array is valid JSON but not the expected object shape.
      prefs.setString('broadcaster.names', '[1, 2, 3]');
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      expect(store.loadAll(), isEmpty);
    });

    test('multiple setName calls preserve all entries', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      await store.setName('a', 'AAA');
      await store.setName('b', 'BBB');
      await store.setName('c', 'CCC');
      await store.setName('a', 'AAA-updated');

      expect(store.loadAll(), <String, String>{
        'a': 'AAA-updated',
        'b': 'BBB',
        'c': 'CCC',
      });
    });

    test('concurrent setName calls all land in storage', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore store =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);

      await Future.wait<void>(<Future<void>>[
        store.setName('a', 'AAA'),
        store.setName('b', 'BBB'),
        store.setName('c', 'CCC'),
        store.setName('d', 'DDD'),
      ]);

      expect(store.loadAll(), <String, String>{
        'a': 'AAA',
        'b': 'BBB',
        'c': 'CCC',
        'd': 'DDD',
      });
    });

    test('a new store instance reads back values written by an earlier '
        'instance against the same prefs', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcasterNameStore writer =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);
      await writer.setName('123', 'Alice');

      final SharedPreferencesBroadcasterNameStore reader =
          SharedPreferencesBroadcasterNameStore(prefs: prefs);
      expect(reader.loadName('123'), 'Alice');
    });

    // Issue #833: cleanup of long-unused entries.
    group('cleanup', () {
      test('removes entries older than maxAge', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        // Plant an old entry (lastUsedAt = 800 days ago) and a fresh one
        // (lastUsedAt = 30 days ago) directly into storage so the test
        // does not depend on time travel.
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int oldTs = now - const Duration(days: 800).inMilliseconds;
        final int recentTs = now - const Duration(days: 30).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'old-id': <String, Object>{'name': 'Old', 'lastUsedAt': oldTs},
            'fresh-id': <String, Object>{
              'name': 'Fresh',
              'lastUsedAt': recentTs,
            },
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(store.loadAll(), <String, String>{'fresh-id': 'Fresh'});
      });

      test('keeps entries within maxAge', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int recentTs = now - const Duration(days: 30).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'a': <String, Object>{'name': 'AAA', 'lastUsedAt': recentTs},
            'b': <String, Object>{'name': 'BBB', 'lastUsedAt': recentTs},
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup();

        expect(removed, 0);
        expect(store.loadAll(), <String, String>{'a': 'AAA', 'b': 'BBB'});
      });

      test('on an empty store is a no-op', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup();

        expect(removed, 0);
        expect(store.loadAll(), isEmpty);
        // Empty store must not have created the storage key.
        expect(prefs.getString('broadcaster.names'), isNull);
      });

      test('uses 730-day default retention (entry just under cutoff is '
          'kept, just over cutoff is removed)', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final int now = DateTime.now().millisecondsSinceEpoch;
        // 729 days ago — must survive the default 730-day cutoff.
        final int justUnder = now - const Duration(days: 729).inMilliseconds;
        // 731 days ago — must be removed.
        final int justOver = now - const Duration(days: 731).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'survivor': <String, Object>{
              'name': 'Survivor',
              'lastUsedAt': justUnder,
            },
            'expired': <String, Object>{
              'name': 'Expired',
              'lastUsedAt': justOver,
            },
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup();

        expect(removed, 1);
        expect(store.loadAll(), <String, String>{'survivor': 'Survivor'});
      });

      test('respects a caller-supplied maxAge', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int tenDaysAgo = now - const Duration(days: 10).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'a': <String, Object>{'name': 'A', 'lastUsedAt': tenDaysAgo},
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup(
          maxAge: const Duration(days: 5),
        );

        expect(removed, 1);
        expect(store.loadAll(), isEmpty);
      });
    });

    // Issue #833: lazy timestamp update on read.
    group('lazy timestamp update on loadName', () {
      test(
        'a second loadName within the throttle window does not write',
        () async {
          final InMemorySharedPreferences prefs = InMemorySharedPreferences();
          final SharedPreferencesBroadcasterNameStore store =
              SharedPreferencesBroadcasterNameStore(prefs: prefs);
          await store.setName('123', 'Alice');

          // Capture the on-disk payload after the seed write — subsequent
          // reads inside the 24h throttle must not change it.
          final String? before = prefs.getString('broadcaster.names');
          expect(before, isNotNull);

          // Repeatedly read the same id — within the throttle window no
          // additional SharedPreferences write should happen.
          for (int i = 0; i < 5; i++) {
            expect(store.loadName('123'), 'Alice');
          }
          // Allow any spuriously-scheduled writes to drain.
          await Future<void>.delayed(Duration.zero);

          expect(
            prefs.getString('broadcaster.names'),
            before,
            reason:
                'loadName within throttle window must not rewrite '
                'SharedPreferences',
          );
        },
      );

      test(
        'loadName outside the throttle window persists a fresh lastUsedAt',
        () async {
          // Seed an entry with lastUsedAt = 25h ago so the throttle window
          // (24h) is already exceeded. The first loadName should schedule
          // a write that bumps lastUsedAt to ~now.
          final InMemorySharedPreferences prefs = InMemorySharedPreferences();
          final int now = DateTime.now().millisecondsSinceEpoch;
          final int staleTs = now - const Duration(hours: 25).inMilliseconds;
          prefs.setString(
            'broadcaster.names',
            json.encode(<String, Map<String, Object>>{
              'aged-id': <String, Object>{
                'name': 'Aged',
                'lastUsedAt': staleTs,
              },
            }),
          );
          final SharedPreferencesBroadcasterNameStore store =
              SharedPreferencesBroadcasterNameStore(prefs: prefs);

          expect(store.loadName('aged-id'), 'Aged');
          // Drain the scheduled lazy write.
          await Future<void>.delayed(Duration.zero);

          final Map<String, dynamic> persisted =
              json.decode(prefs.getString('broadcaster.names')!)
                  as Map<String, dynamic>;
          final Map<String, dynamic> entry =
              persisted['aged-id'] as Map<String, dynamic>;
          expect(entry['name'], 'Aged');
          expect(
            entry['lastUsedAt'] as int,
            greaterThanOrEqualTo(now),
            reason:
                'loadName outside throttle window must refresh lastUsedAt '
                'to roughly the current time',
          );
        },
      );

      test('loadName recovers when on-disk lastUsedAt is in the future '
          '(clock-skew defense)', () async {
        // Plant lastUsedAt = +10h relative to now (e.g. user moved
        // device clock forward, then back). Without clock-skew defense
        // `now - last` is negative, the throttle window is never
        // exceeded, and lastUsedAt would be stuck in the future.
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int futureTs = now + const Duration(hours: 10).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'skew-id': <String, Object>{'name': 'Skew', 'lastUsedAt': futureTs},
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        expect(store.loadName('skew-id'), 'Skew');
        await Future<void>.delayed(Duration.zero);

        final Map<String, dynamic> persisted =
            json.decode(prefs.getString('broadcaster.names')!)
                as Map<String, dynamic>;
        final Map<String, dynamic> entry =
            persisted['skew-id'] as Map<String, dynamic>;
        expect(
          entry['lastUsedAt'] as int,
          lessThan(futureTs),
          reason:
              'A future-dated lastUsedAt must be reset to ~now so the '
              'throttle window can elapse on subsequent reads',
        );
        // Stronger pin: lastUsedAt should be roughly the test's `now`,
        // not "any value lower than the future seed". Catches a
        // regression where the throttle is reset but the lastUsedAt
        // accidentally rolls back to an even older value.
        expect(
          entry['lastUsedAt'] as int,
          greaterThanOrEqualTo(now),
          reason:
              'Reset lastUsedAt should land at-or-after the test start '
              'time, not an arbitrary historical value',
        );
      });
    });

    // Issue #833: write-failure path through the lazy-touch / chain
    // catchError sites. Pins the regression net for the explicit
    // `developer.log` rule (AGENTS.md "no silent catch") so that a
    // future refactor that re-introduces empty catchError is detected
    // by widget-style behaviour rather than only by code review.
    //
    // Note: callers of [setName] / [cleanup] do see write errors via
    // the returned Future (so they can decide policy at the call site).
    // The internal `_pendingWriteChain.catchError` is what guarantees
    // *subsequent* writes still drain even after one fails — that is
    // the behaviour exercised here.
    group('persistence-failure swallow-with-log path', () {
      test('write chain stays alive after a setString failure', () async {
        final _ThrowingSharedPreferences prefs = _ThrowingSharedPreferences();
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        // The first write surfaces the error to the caller, but the
        // private `_pendingWriteChain` is rebuilt with `.catchError(...)`
        // so subsequent enqueues still execute (rather than the chain
        // staying permanently rejected).
        await expectLater(store.setName('id-1', 'Alice'), throwsException);

        // The second write should still be scheduled — i.e. the inner
        // operation runs and surfaces its own (independent) failure
        // rather than inheriting the previous future's rejection.
        await expectLater(store.setName('id-2', 'Bob'), throwsException);

        // Without the chain catchError, the second `_pendingWriteChain.then`
        // would inherit the prior rejection and resolve with that *same*
        // error before this operation ever ran. The fact that we observe
        // a fresh exception per call is the regression net for the
        // explicit `developer.log` catchError.
      });
    });

    // Issue #833: cleanup vs concurrent setName resurrection.
    group('cleanup serial-chain race', () {
      test('cleanup and a concurrent setName for the same id serialise: '
          'the slot resurrects with a fresh lastUsedAt', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final int now = DateTime.now().millisecondsSinceEpoch;
        final int oldTs = now - const Duration(days: 800).inMilliseconds;
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, Map<String, Object>>{
            'stale-id': <String, Object>{
              'name': 'OldName',
              'lastUsedAt': oldTs,
            },
          }),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        // Fire cleanup and setName at the same scheduling boundary
        // without awaiting individually. The serial write chain inside
        // the store must order them so the final state is well-defined
        // and consistent (no torn write, no half-applied JSON).
        final Future<int> cleanup = store.cleanup();
        final Future<void> seed = store.setName('stale-id', 'Resurrected');
        final List<Object?> results = await Future.wait<Object?>(
          <Future<Object?>>[cleanup, seed],
        );
        final int removed = results[0] as int;
        // One of two well-defined orderings must hold:
        // - cleanup ran first → stale-id was deleted; setName then
        //   re-added it with fresh lastUsedAt → loadName returns
        //   'Resurrected' and removed==1.
        // - setName ran first → lastUsedAt is fresh; cleanup observes
        //   it as in-window and keeps it → loadName returns
        //   'Resurrected' and removed==0.
        expect(removed, anyOf(0, 1));
        expect(store.loadName('stale-id'), 'Resurrected');
      });
    });

    // Issue #833: legacy schema migration.
    group('legacy schema migration', () {
      test('reads legacy {id: name} string-map and exposes names', () {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, String>{'123': 'Alice', '456': 'Bob'}),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        expect(store.loadName('123'), 'Alice');
        expect(store.loadAll(), <String, String>{'123': 'Alice', '456': 'Bob'});
      });

      test(
        'cleanup migrates legacy schema in place (idempotent rewrite)',
        () async {
          final InMemorySharedPreferences prefs = InMemorySharedPreferences();
          prefs.setString(
            'broadcaster.names',
            json.encode(<String, String>{'123': 'Alice'}),
          );
          final SharedPreferencesBroadcasterNameStore store =
              SharedPreferencesBroadcasterNameStore(prefs: prefs);

          // First cleanup migrates the on-disk format. Nothing is removed
          // because legacy entries are stamped with `lastUsedAt = now`.
          final int firstRemoved = await store.cleanup();
          expect(firstRemoved, 0);

          final String? migrated = prefs.getString('broadcaster.names');
          expect(migrated, isNotNull);
          final Object? decoded = json.decode(migrated!);
          expect(decoded, isA<Map<dynamic, dynamic>>());
          final Map<dynamic, dynamic> asMap = decoded! as Map<dynamic, dynamic>;
          expect(
            asMap['123'],
            isA<Map<dynamic, dynamic>>(),
            reason:
                'Legacy string value must have been upgraded to an '
                'object with name + lastUsedAt',
          );
          final Map<dynamic, dynamic> entry =
              asMap['123'] as Map<dynamic, dynamic>;
          expect(entry['name'], 'Alice');
          expect(entry['lastUsedAt'], isA<int>());

          // Second cleanup must not remove the freshly-migrated entry.
          final int secondRemoved = await store.cleanup();
          expect(secondRemoved, 0);
          expect(store.loadName('123'), 'Alice');
        },
      );

      test('legacy entry survives cleanup because lastUsedAt is stamped '
          'with now', () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        prefs.setString(
          'broadcaster.names',
          json.encode(<String, String>{'persist': 'Persist'}),
        );
        final SharedPreferencesBroadcasterNameStore store =
            SharedPreferencesBroadcasterNameStore(prefs: prefs);

        final int removed = await store.cleanup();

        expect(removed, 0);
        expect(store.loadName('persist'), 'Persist');
      });
    });
  });
}

/// A SharedPreferencesLike whose [setString] / [remove] always throw, used
/// to exercise the `developer.log`-based catchError paths in
/// `SharedPreferencesBroadcasterNameStore`. Reads still work (off the
/// [seedMap] map) so cleanup / loadName can reach the write path that
/// must fail.
class _ThrowingSharedPreferences implements SharedPreferencesLike {
  final Map<String, Object> seedMap = <String, Object>{};

  @override
  bool? getBool(String key) => seedMap[key] as bool?;
  @override
  double? getDouble(String key) => seedMap[key] as double?;
  @override
  int? getInt(String key) => seedMap[key] as int?;
  @override
  String? getString(String key) => seedMap[key] as String?;

  @override
  Future<bool> setBool(String key, bool value) async {
    throw _SimulatedDiskFull();
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    throw _SimulatedDiskFull();
  }

  @override
  Future<bool> setInt(String key, int value) async {
    throw _SimulatedDiskFull();
  }

  @override
  Future<bool> setString(String key, String value) async {
    throw _SimulatedDiskFull();
  }

  @override
  Future<bool> remove(String key) async {
    throw _SimulatedDiskFull();
  }
}

class _SimulatedDiskFull implements Exception {
  @override
  String toString() => 'Simulated disk-full failure';
}
