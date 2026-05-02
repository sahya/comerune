import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('SharedPreferencesBroadcasterNgStore', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesBroadcasterNgStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesBroadcasterNgStore(prefs: prefs);
    });

    test(
      'first load returns the template content and persists per-broadcaster',
      () async {
        await store.saveTemplateNgUserIds(<String>{'u1', 'u2'});
        await store.saveTemplateNgWordRules(<NgWordRule>[
          const NgWordRule(pattern: 'spam'),
          const NgWordRule(pattern: 'bot', enabled: false),
        ]);

        final Set<String> ids = await store.loadNgUserIds('b1');
        final List<NgWordRule> rules = await store.loadNgWordRules('b1');

        expect(ids, equals(<String>{'u1', 'u2'}));
        expect(rules.length, 2);
        expect(rules[0].pattern, 'spam');
        expect(rules[1].pattern, 'bot');
        expect(rules[1].enabled, isFalse);

        // Index reflects the seeded broadcaster.
        expect(store.listBroadcasters(), contains('b1'));
      },
    );

    test('save → load round-trip per broadcaster', () async {
      await store.saveNgUserIds('b1', <String>['x', 'y']);
      await store.saveNgWordRules('b1', <NgWordRule>[
        const NgWordRule(pattern: 'foo'),
      ]);

      final Set<String> ids = await store.loadNgUserIds('b1');
      final List<NgWordRule> rules = await store.loadNgWordRules('b1');

      expect(ids, equals(<String>{'x', 'y'}));
      expect(rules.single.pattern, 'foo');
    });

    test('separate broadcasters are isolated', () async {
      await store.saveTemplateNgUserIds(<String>{'tpl'});
      await store.saveNgUserIds('b1', <String>['only-b1']);
      // b2 first access should pick up the template, NOT b1's value.
      final Set<String> b2Ids = await store.loadNgUserIds('b2');
      expect(b2Ids, equals(<String>{'tpl'}));
      // b1 retains its explicit value.
      expect(await store.loadNgUserIds('b1'), equals(<String>{'only-b1'}));
    });

    test('addNgUserId is idempotent and creates an initialized slot', () async {
      await store.addNgUserId('b1', 'u1');
      await store.addNgUserId('b1', 'u1');
      await store.addNgUserId('b1', 'u2');
      final Set<String> ids = await store.loadNgUserIds('b1');
      expect(ids, equals(<String>{'u1', 'u2'}));
    });

    test('removeNgUserId is idempotent', () async {
      await store.saveNgUserIds('b1', <String>['u1', 'u2']);
      await store.removeNgUserId('b1', 'u1');
      await store.removeNgUserId('b1', 'u1');
      await store.removeNgUserId('b1', 'missing');
      final Set<String> ids = await store.loadNgUserIds('b1');
      expect(ids, equals(<String>{'u2'}));
    });

    test('template save/load round-trip', () async {
      await store.saveTemplateNgUserIds(<String>{'a', 'b'});
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'p'),
      ]);
      expect(await store.loadTemplateNgUserIds(), equals(<String>{'a', 'b'}));
      expect((await store.loadTemplateNgWordRules()).single.pattern, 'p');
    });

    test('listBroadcasters reflects added IDs in insertion order', () async {
      await store.saveNgUserIds('b1', <String>['x']);
      await store.saveNgUserIds('b2', <String>['y']);
      await store.saveNgUserIds('b1', <String>['x', 'z']);
      expect(store.listBroadcasters(), <String>['b1', 'b2']);
    });

    test('empty broadcasterId is rejected with ArgumentError', () async {
      expect(() => store.loadNgUserIds(''), throwsArgumentError);
      expect(() => store.loadNgWordRules(''), throwsArgumentError);
      expect(() => store.saveNgUserIds('', <String>['x']), throwsArgumentError);
      expect(
        () => store.saveNgWordRules('', <NgWordRule>[]),
        throwsArgumentError,
      );
      expect(() => store.addNgUserId('', 'u'), throwsArgumentError);
      expect(() => store.removeNgUserId('', 'u'), throwsArgumentError);
    });

    test('flushPendingWrites waits for pending writes', () async {
      // Issue several writes without awaiting individually; the chained
      // future returned by flushPendingWrites must resolve only after all
      // of them have settled.
      final Future<void> a = store.saveNgUserIds('b1', <String>['u1']);
      final Future<void> b = store.addNgUserId('b1', 'u2');
      final Future<void> c = store.saveNgWordRules('b1', <NgWordRule>[
        const NgWordRule(pattern: 'p'),
      ]);
      await store.flushPendingWrites();
      // All three are already settled by this point.
      await Future.wait(<Future<void>>[a, b, c]);
      expect(await store.loadNgUserIds('b1'), equals(<String>{'u1', 'u2'}));
      expect((await store.loadNgWordRules('b1')).single.pattern, 'p');
    });

    test('addNgUserId with empty userId is a no-op', () async {
      await store.saveNgUserIds('b1', <String>['u1']);
      await store.addNgUserId('b1', '');
      expect(await store.loadNgUserIds('b1'), equals(<String>{'u1'}));
    });

    test('saveNgUserIds deduplicates and skips empty strings', () async {
      await store.saveNgUserIds('b1', <String>['u1', 'u1', '', 'u2']);
      expect(await store.loadNgUserIds('b1'), equals(<String>{'u1', 'u2'}));
    });

    test(
      'loadBroadcasterNgAttributes seeds from template once and returns '
      'both NG user IDs and rules in a single call',
      () async {
        await store.saveTemplateNgUserIds(<String>{'tu1', 'tu2'});
        await store.saveTemplateNgWordRules(<NgWordRule>[
          const NgWordRule(pattern: 'tw'),
          const NgWordRule(pattern: 'off', enabled: false),
        ]);

        // First combined load on `b1` should template-seed and then return
        // both halves of the snapshot consistently.
        final ({Set<String> ngUserIds, List<NgWordRule> rules}) first =
            await store.loadBroadcasterNgAttributes('b1');
        expect(first.ngUserIds, equals(<String>{'tu1', 'tu2'}));
        expect(first.rules.length, 2);
        expect(first.rules[0].pattern, 'tw');
        expect(first.rules[1].pattern, 'off');
        expect(first.rules[1].enabled, isFalse);
        expect(store.listBroadcasters(), contains('b1'));

        // Second call must reflect the stored slot, not the template
        // (mutating the template afterwards must not bleed back into `b1`).
        await store.saveTemplateNgUserIds(<String>{'changed'});
        final ({Set<String> ngUserIds, List<NgWordRule> rules}) second =
            await store.loadBroadcasterNgAttributes('b1');
        expect(second.ngUserIds, equals(<String>{'tu1', 'tu2'}));
      },
    );

    test('malformed stored JSON degrades to empty without throwing', () async {
      // Pollute the slot directly so we exercise the catch branch.
      await prefs.setString(
        'settings.filter.broadcaster.b1.ngUserIds',
        '{not-json',
      );
      await prefs.setString(
        'settings.filter.broadcaster.b1.initialized',
        'true',
      );
      expect(await store.loadNgUserIds('b1'), isEmpty);

      await prefs.setString(
        'settings.filter.broadcaster.b1.ngWordRules',
        '@@@',
      );
      expect(await store.loadNgWordRules('b1'), isEmpty);
    });
  });
}
