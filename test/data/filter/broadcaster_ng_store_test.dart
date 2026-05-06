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
      'first load returns the template content without creating a broadcaster slot',
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
        expect(store.listBroadcasters(), isEmpty);
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
      // b2 read should pick up the template, NOT b1's value.
      final Set<String> b2Ids = await store.loadNgUserIds('b2');
      expect(b2Ids, equals(<String>{'tpl'}));
      // b1 retains its explicit value.
      expect(await store.loadNgUserIds('b1'), equals(<String>{'only-b1'}));
      expect(store.listBroadcasters(), <String>['b1']);
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

    test('addNgUserId for a value already in the template does NOT create a '
        'broadcaster slot', () async {
      await store.saveTemplateNgUserIds(<String>{'tpl-user'});

      await store.addNgUserId('b1', 'tpl-user');

      // No-op: nothing changed from the effective state, so no slot
      // should be materialized.
      expect(store.listBroadcasters(), isEmpty);
      expect(await store.loadNgUserIds('b1'), equals(<String>{'tpl-user'}));
    });

    test('removeNgUserId for a value absent from the template does NOT '
        'create a broadcaster slot', () async {
      await store.saveTemplateNgUserIds(<String>{'tpl-user'});

      await store.removeNgUserId('b1', 'absent-user');

      // No-op: removing a value that is not currently in effect must
      // not materialize a slot.
      expect(store.listBroadcasters(), isEmpty);
      expect(await store.loadNgUserIds('b1'), equals(<String>{'tpl-user'}));
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

    test('loadBroadcasterNgAttributes returns template fallback without '
        'creating a slot', () async {
      await store.saveTemplateNgUserIds(<String>{'tu1', 'tu2'});
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'tw'),
        const NgWordRule(pattern: 'off', enabled: false),
      ]);

      final ({Set<String> ngUserIds, List<NgWordRule> rules}) first =
          await store.loadBroadcasterNgAttributes('b1');
      expect(first.ngUserIds, equals(<String>{'tu1', 'tu2'}));
      expect(first.rules.length, 2);
      expect(first.rules[0].pattern, 'tw');
      expect(first.rules[1].pattern, 'off');
      expect(first.rules[1].enabled, isFalse);
      expect(store.listBroadcasters(), isEmpty);

      // Without a dedicated slot, later loads continue to reflect the
      // template fallback.
      await store.saveTemplateNgUserIds(<String>{'changed'});
      final ({Set<String> ngUserIds, List<NgWordRule> rules}) second =
          await store.loadBroadcasterNgAttributes('b1');
      expect(second.ngUserIds, equals(<String>{'changed'}));
    });

    test(
      'addNgUserId seeds from template and then persists a broadcaster slot',
      () async {
        await store.saveTemplateNgUserIds(<String>{'tpl'});
        await store.saveTemplateNgWordRules(<NgWordRule>[
          const NgWordRule(pattern: 'seed-word'),
        ]);

        await store.addNgUserId('b1', 'u1');

        expect(await store.loadNgUserIds('b1'), equals(<String>{'tpl', 'u1'}));
        expect((await store.loadNgWordRules('b1')).single.pattern, 'seed-word');
        expect(store.listBroadcasters(), <String>['b1']);
      },
    );

    test(
      'saveNgWordRules creates a broadcaster slot after template-backed edit',
      () async {
        await store.saveTemplateNgUserIds(<String>{'seed-user'});
        await store.saveTemplateNgWordRules(<NgWordRule>[
          const NgWordRule(pattern: 'seed-word'),
        ]);

        final List<NgWordRule> effective = await store.loadNgWordRules('b1');
        await store.saveNgWordRules('b1', <NgWordRule>[
          ...effective,
          const NgWordRule(pattern: 'added-word'),
        ]);

        final List<NgWordRule> persisted = await store.loadNgWordRules('b1');
        expect(
          persisted.map((NgWordRule rule) => rule.pattern).toList(),
          <String>['seed-word', 'added-word'],
        );
        expect(await store.loadNgUserIds('b1'), equals(<String>{'seed-user'}));
        expect(store.listBroadcasters(), <String>['b1']);
      },
    );

    test('saveNgUserIds creates a broadcaster slot after template-backed edit '
        'while preserving template NG word rules', () async {
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'seed-word'),
      ]);

      await store.saveNgUserIds('b1', <String>['added-user']);

      expect(await store.loadNgUserIds('b1'), equals(<String>{'added-user'}));
      expect(
        (await store.loadNgWordRules('b1')).map((NgWordRule r) => r.pattern),
        <String>['seed-word'],
      );
      expect(store.listBroadcasters(), <String>['b1']);
    });

    test(
      'saveNgWordRules removes the broadcaster slot when both rules and users '
      'become empty',
      () async {
        await store.saveNgUserIds('b1', <String>['u1']);
        await store.saveNgWordRules('b1', <NgWordRule>[
          const NgWordRule(pattern: 'word1'),
        ]);

        await store.saveNgUserIds('b1', const <String>[]);
        expect(store.listBroadcasters(), <String>['b1']);

        await store.saveNgWordRules('b1', const <NgWordRule>[]);

        expect(store.listBroadcasters(), isEmpty);
      },
    );

    test('removing the last broadcaster-specific values falls back to template '
        'content again', () async {
      await store.saveTemplateNgUserIds(<String>{'template-user'});
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'template-word'),
      ]);
      await store.saveNgUserIds('b1', <String>['u1']);
      await store.saveNgWordRules('b1', <NgWordRule>[
        const NgWordRule(pattern: 'word1'),
      ]);

      await store.saveNgUserIds('b1', const <String>[]);
      await store.saveNgWordRules('b1', const <NgWordRule>[]);

      expect(store.listBroadcasters(), isEmpty);
      expect(
        await store.loadNgUserIds('b1'),
        equals(<String>{'template-user'}),
      );
      expect(
        (await store.loadNgWordRules('b1')).map((NgWordRule r) => r.pattern),
        <String>['template-word'],
      );
    });

    test('removeNgUserId removes the broadcaster slot when the last user is '
        'deleted and no rules remain', () async {
      await store.saveNgUserIds('b1', <String>['u1']);

      await store.removeNgUserId('b1', 'u1');

      expect(store.listBroadcasters(), isEmpty);
    });

    test('mutating template after broadcaster slot is committed must not bleed '
        'into the slot NG user IDs', () async {
      await store.saveTemplateNgUserIds(<String>{'tpl-before'});
      await store.saveNgUserIds('b1', <String>['only-b1']);

      // Slot is now committed for b1. Subsequent template edits must not
      // leak into the committed slot, since the slot was created from the
      // template snapshot at write time (Issue #856 / PR #825).
      await store.saveTemplateNgUserIds(<String>{'tpl-after'});

      expect(
        await store.loadNgUserIds('b1'),
        equals(<String>{'only-b1'}),
        reason:
            'Committed broadcaster slot must keep its own NG user IDs '
            'independent of later template edits.',
      );
      expect(
        await store.loadTemplateNgUserIds(),
        equals(<String>{'tpl-after'}),
        reason: 'Template itself should still reflect the latest edit.',
      );
    });

    test('mutating template after broadcaster slot is committed must not bleed '
        'into the slot NG word rules', () async {
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'tpl-before'),
      ]);
      await store.saveNgWordRules('b1', <NgWordRule>[
        const NgWordRule(pattern: 'only-b1'),
      ]);

      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'tpl-after'),
      ]);

      expect(
        (await store.loadNgWordRules(
          'b1',
        )).map((NgWordRule rule) => rule.pattern).toList(),
        <String>['only-b1'],
        reason:
            'Committed broadcaster slot must keep its own NG word rules '
            'independent of later template edits.',
      );
      expect(
        (await store.loadTemplateNgWordRules())
            .map((NgWordRule rule) => rule.pattern)
            .toList(),
        <String>['tpl-after'],
        reason: 'Template itself should still reflect the latest edit.',
      );
    });

    test('cross-axis: saveNgUserIds-committed slot freezes its seeded NG word '
        'rules against later template edits', () async {
      // saveNgUserIds is the only operation customizing the slot here, so
      // the slot's NG word rules come from a template snapshot taken at
      // commit time (Issue #856 / PR #825). Later template-rule edits
      // must not retroactively change the slot's rules.
      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'seeded-rule'),
      ]);
      await store.saveNgUserIds('b1', <String>['only-b1']);

      await store.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'tpl-after'),
      ]);

      expect(
        (await store.loadNgWordRules(
          'b1',
        )).map((NgWordRule rule) => rule.pattern).toList(),
        <String>['seeded-rule'],
        reason:
            'Slot committed by saveNgUserIds must retain the NG word '
            'rules snapshot taken at commit time, independent of later '
            'template edits.',
      );
    });

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
