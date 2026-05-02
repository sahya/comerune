import 'dart:convert';

import 'package:comerune/application/filter/broadcaster_ng_migrator.dart';
import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

void main() {
  group('BroadcasterNgMigrator.migrateIfNeeded', () {
    late InMemorySharedPreferences prefs;
    late SharedPreferencesBroadcasterNgStore store;

    setUp(() {
      prefs = InMemorySharedPreferences();
      store = SharedPreferencesBroadcasterNgStore(prefs: prefs);
    });

    test('runs once and is idempotent via the migration flag', () async {
      await prefs.setString('settings.filter.ngUserIds', 'a\nb');

      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        knownBroadcasterIds: const <String>['b1'],
      );

      expect(prefs.getBool(BroadcasterNgMigrator.migrationFlagKey), isTrue);

      // Mutate the legacy key after the migration ran. A subsequent
      // migrateIfNeeded must NOT pick up the new value.
      await prefs.setString('settings.filter.ngUserIds', 'mutated');
      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        knownBroadcasterIds: const <String>['b1'],
      );

      expect(await store.loadTemplateNgUserIds(), equals(<String>{'a', 'b'}));
    });

    test(
      'merges legacy ngUserIds, ngWords and ngWordRules into the template',
      () async {
        await prefs.setString('settings.filter.ngUserIds', 'u1\n\nu2\n');
        await prefs.setString('settings.filter.ngWords', 'old1\nold2');
        await prefs.setString(
          'settings.filter.ngWordRules',
          jsonEncode(<Map<String, dynamic>>[
            <String, dynamic>{'pattern': 'rule1', 'enabled': true},
            <String, dynamic>{'pattern': 'rule2', 'enabled': false},
            // Duplicate pattern that also appears as a legacy `ngWords`
            // line should not be added twice.
            <String, dynamic>{'pattern': 'old1', 'enabled': true},
          ]),
        );

        await BroadcasterNgMigrator.migrateIfNeeded(
          prefs: prefs,
          store: store,
          knownBroadcasterIds: const <String>[],
        );

        expect(
          await store.loadTemplateNgUserIds(),
          equals(<String>{'u1', 'u2'}),
        );

        final List<NgWordRule> rules = await store.loadTemplateNgWordRules();
        final List<String> patterns = rules
            .map((NgWordRule r) => r.pattern)
            .toList();
        // ngWordRules entries first, then ngWords lines that were not
        // already covered.
        expect(patterns, containsAll(<String>['rule1', 'rule2', 'old2']));
        expect(
          patterns.where((String p) => p == 'old1').length,
          1,
          reason: 'old1 must not be duplicated',
        );
        // rule2's enabled=false flag must survive the migration.
        expect(
          rules.firstWhere((NgWordRule r) => r.pattern == 'rule2').enabled,
          isFalse,
        );
      },
    );

    test('seeds known broadcasters with the merged content', () async {
      await prefs.setString('settings.filter.ngUserIds', 'u1');
      await prefs.setString('settings.filter.ngWords', 'word1');

      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        // Include a duplicate and an empty entry to exercise dedup/skip.
        knownBroadcasterIds: const <String>['b1', '', 'b2', 'b1'],
      );

      expect(await store.loadNgUserIds('b1'), equals(<String>{'u1'}));
      expect(await store.loadNgUserIds('b2'), equals(<String>{'u1'}));
      expect((await store.loadNgWordRules('b1')).single.pattern, 'word1');
      expect(store.listBroadcasters()..sort(), <String>['b1', 'b2']);
    });

    test('missing legacy keys produce an empty template', () async {
      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        knownBroadcasterIds: const <String>[],
      );

      expect(await store.loadTemplateNgUserIds(), isEmpty);
      expect(await store.loadTemplateNgWordRules(), isEmpty);
      expect(prefs.getBool(BroadcasterNgMigrator.migrationFlagKey), isTrue);
    });

    test('malformed ngWordRules JSON does not throw', () async {
      await prefs.setString('settings.filter.ngWordRules', '{not-json');
      await prefs.setString('settings.filter.ngWords', 'survivor');

      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        knownBroadcasterIds: const <String>[],
      );

      // The malformed JSON is dropped; the newline-separated legacy
      // ngWords entries are still ingested.
      final List<NgWordRule> rules = await store.loadTemplateNgWordRules();
      expect(rules.map((NgWordRule r) => r.pattern), <String>['survivor']);
      expect(prefs.getBool(BroadcasterNgMigrator.migrationFlagKey), isTrue);
    });

    test('legacy keys are left in place after migration', () async {
      await prefs.setString('settings.filter.ngUserIds', 'u1');
      await prefs.setString('settings.filter.ngWords', 'w1');
      await prefs.setString(
        'settings.filter.ngWordRules',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{'pattern': 'r1'},
        ]),
      );

      await BroadcasterNgMigrator.migrateIfNeeded(
        prefs: prefs,
        store: store,
        knownBroadcasterIds: const <String>['b1'],
      );

      expect(prefs.getString('settings.filter.ngUserIds'), 'u1');
      expect(prefs.getString('settings.filter.ngWords'), 'w1');
      expect(prefs.getString('settings.filter.ngWordRules'), isNotNull);
    });
  });
}
