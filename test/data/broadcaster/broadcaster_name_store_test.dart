import 'package:flutter_test/flutter_test.dart';

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
  });
}
