import 'dart:convert';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

/// Issue #727 (PR3): exercises [SharedPreferencesSettingsStore.exportAsJson]
/// and [SharedPreferencesSettingsStore.importFromJson] against the new
/// per-broadcaster + template NG layout.
void main() {
  group('exportAsJson', () {
    test('emits broadcasterNgFilter with empty template + empty broadcasters '
        'when nothing is stored', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );

      final String exported = await settingsStore.exportAsJson();
      final Map<String, dynamic> root =
          jsonDecode(exported) as Map<String, dynamic>;
      expect(
        root.containsKey(SharedPreferencesSettingsStore.exportBroadcasterNgKey),
        isTrue,
      );
      final Map<String, dynamic> block =
          root[SharedPreferencesSettingsStore.exportBroadcasterNgKey]
              as Map<String, dynamic>;
      expect(block['version'], 1);
      expect((block['template'] as Map<String, dynamic>)['ngUserIds'], isEmpty);
      expect(
        (block['template'] as Map<String, dynamic>)['ngWordRules'],
        isEmpty,
      );
      expect(block['broadcasters'], isEmpty);
    });

    test('emits template + broadcaster slots when content is stored', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      await ngStore.saveTemplateNgUserIds(<String>{'tpl-1'});
      await ngStore.saveTemplateNgWordRules(<NgWordRule>[
        const NgWordRule(pattern: 'tpl-pattern'),
      ]);
      await ngStore.saveNgUserIds('b1', <String>{'u1'});
      await ngStore.saveNgWordRules('b1', <NgWordRule>[
        const NgWordRule(pattern: 'p1'),
      ]);
      await ngStore.saveNgUserIds('b2', <String>{'u2a', 'u2b'});
      await ngStore.saveNgWordRules('b2', <NgWordRule>[
        const NgWordRule(pattern: 'p2', enabled: false),
      ]);
      await ngStore.flushPendingWrites();

      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );
      final Map<String, dynamic> root =
          jsonDecode(await settingsStore.exportAsJson())
              as Map<String, dynamic>;
      final Map<String, dynamic> block =
          root[SharedPreferencesSettingsStore.exportBroadcasterNgKey]
              as Map<String, dynamic>;

      final Map<String, dynamic> template =
          block['template'] as Map<String, dynamic>;
      expect(template['ngUserIds'], <String>['tpl-1']);
      expect((template['ngWordRules'] as List<dynamic>).length, 1);

      final Map<String, dynamic> broadcasters =
          block['broadcasters'] as Map<String, dynamic>;
      expect(broadcasters.keys, containsAll(<String>['b1', 'b2']));
      final Map<String, dynamic> b1 =
          broadcasters['b1'] as Map<String, dynamic>;
      expect(b1['ngUserIds'], <String>['u1']);
      final List<dynamic> b1Rules = b1['ngWordRules'] as List<dynamic>;
      expect(b1Rules.length, 1);
      expect((b1Rules.first as Map<String, dynamic>)['pattern'], 'p1');
    });

    test(
      'omits broadcasterNgFilter when no BroadcasterNgStore is provided',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(prefs: prefs);
        final Map<String, dynamic> root =
            jsonDecode(await settingsStore.exportAsJson())
                as Map<String, dynamic>;
        expect(
          root.containsKey(
            SharedPreferencesSettingsStore.exportBroadcasterNgKey,
          ),
          isFalse,
        );
      },
    );
  });

  group('importFromJson — new schema', () {
    test(
      'applies template + broadcaster slots and overwrites stale state',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
          prefs: prefs,
        );
        // Pre-state: stale slot for b1 the import must overwrite.
        await ngStore.saveNgUserIds('b1', <String>{'stale'});
        await ngStore.saveNgWordRules('b1', <NgWordRule>[
          const NgWordRule(pattern: 'stale-pattern'),
        ]);
        await ngStore.flushPendingWrites();

        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(
              prefs: prefs,
              broadcasterNgStore: ngStore,
            );

        final Map<String, dynamic> payload = AppSettings.defaults.toJson();
        payload[SharedPreferencesSettingsStore.exportBroadcasterNgKey] =
            <String, dynamic>{
              'version': 1,
              'template': <String, dynamic>{
                'ngUserIds': <String>['tpl-user'],
                'ngWordRules': <Map<String, dynamic>>[
                  <String, dynamic>{'pattern': 'tpl-pattern', 'enabled': true},
                ],
              },
              'broadcasters': <String, dynamic>{
                'b1': <String, dynamic>{
                  'ngUserIds': <String>['u1'],
                  'ngWordRules': <Map<String, dynamic>>[
                    <String, dynamic>{'pattern': 'p1', 'enabled': true},
                  ],
                },
                'b2': <String, dynamic>{
                  'ngUserIds': <String>['u2'],
                  'ngWordRules': <Map<String, dynamic>>[],
                },
              },
            };

        await settingsStore.importFromJson(jsonEncode(payload));
        await ngStore.flushPendingWrites();

        expect(await ngStore.loadTemplateNgUserIds(), <String>{'tpl-user'});
        final List<NgWordRule> tplRules = await ngStore
            .loadTemplateNgWordRules();
        expect(tplRules.length, 1);
        expect(tplRules.first.pattern, 'tpl-pattern');

        // b1 was pre-populated with stale data; assert it was REPLACED,
        // not merged.
        final BroadcasterNgPayload b1 = await ngStore
            .loadBroadcasterNgAttributes('b1');
        expect(b1.ngUserIds, <String>{'u1'});
        expect(b1.rules.length, 1);
        expect(b1.rules.first.pattern, 'p1');

        final BroadcasterNgPayload b2 = await ngStore
            .loadBroadcasterNgAttributes('b2');
        expect(b2.ngUserIds, <String>{'u2'});
        expect(b2.rules, isEmpty);
      },
    );

    test('skips empty broadcasterId keys without throwing', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );

      final Map<String, dynamic> payload = AppSettings.defaults.toJson();
      payload[SharedPreferencesSettingsStore.exportBroadcasterNgKey] =
          <String, dynamic>{
            'version': 1,
            'template': <String, dynamic>{
              'ngUserIds': <String>[],
              'ngWordRules': <Map<String, dynamic>>[],
            },
            'broadcasters': <String, dynamic>{
              '': <String, dynamic>{
                'ngUserIds': <String>['skipped'],
                'ngWordRules': <Map<String, dynamic>>[],
              },
              'real': <String, dynamic>{
                'ngUserIds': <String>['kept'],
                'ngWordRules': <Map<String, dynamic>>[],
              },
            },
          };

      await settingsStore.importFromJson(jsonEncode(payload));
      await ngStore.flushPendingWrites();

      expect(ngStore.listBroadcasters(), <String>['real']);
      final BroadcasterNgPayload real = await ngStore
          .loadBroadcasterNgAttributes('real');
      expect(real.ngUserIds, <String>{'kept'});
    });

    test('tolerates an unknown version field with best-effort apply', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );

      final Map<String, dynamic> payload = AppSettings.defaults.toJson();
      payload[SharedPreferencesSettingsStore.exportBroadcasterNgKey] =
          <String, dynamic>{
            'version': 999,
            'template': <String, dynamic>{
              'ngUserIds': <String>['tpl'],
              'ngWordRules': <Map<String, dynamic>>[],
            },
            'broadcasters': <String, dynamic>{
              'b1': <String, dynamic>{
                'ngUserIds': <String>['u1'],
                'ngWordRules': <Map<String, dynamic>>[],
              },
            },
          };

      await settingsStore.importFromJson(jsonEncode(payload));
      await ngStore.flushPendingWrites();

      expect(await ngStore.loadTemplateNgUserIds(), <String>{'tpl'});
      final BroadcasterNgPayload b1 = await ngStore.loadBroadcasterNgAttributes(
        'b1',
      );
      expect(b1.ngUserIds, <String>{'u1'});
    });

    test('malformed broadcasterNgFilter (non-Map) does not abort and triggers '
        'legacy fallback when legacy fields are present', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      // Pre-existing broadcaster slot so the legacy fallback has
      // something to reseed.
      await ngStore.saveNgUserIds('b1', <String>{'old'});
      await ngStore.saveNgWordRules('b1', const <NgWordRule>[]);
      await ngStore.flushPendingWrites();

      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );

      // broadcasterNgFilter intentionally malformed (string, not Map).
      // Importer treats it as "absent": legacy fallback runs because
      // legacy fields are present.
      final Map<String, dynamic> payload = AppSettings.defaults
          .copyWith(ngUserIds: 'legacy-user', ngWords: 'legacy-pattern')
          .toJson();
      payload[SharedPreferencesSettingsStore.exportBroadcasterNgKey] =
          'not-a-map';

      await settingsStore.importFromJson(jsonEncode(payload));
      await ngStore.flushPendingWrites();

      expect(await ngStore.loadTemplateNgUserIds(), <String>{'legacy-user'});
      final BroadcasterNgPayload b1 = await ngStore.loadBroadcasterNgAttributes(
        'b1',
      );
      expect(b1.ngUserIds, <String>{'legacy-user'});
      expect(b1.rules.map((NgWordRule r) => r.pattern).toList(), <String>[
        'legacy-pattern',
      ]);
    });
  });

  group('importFromJson — legacy fallback', () {
    test(
      'restores template + reseeds known broadcasters from legacy fields',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
          prefs: prefs,
        );
        // Two broadcasters already known to the store.
        await ngStore.saveNgUserIds('b1', <String>{'pre1'});
        await ngStore.saveNgWordRules('b1', const <NgWordRule>[]);
        await ngStore.saveNgUserIds('b2', <String>{'pre2'});
        await ngStore.saveNgWordRules('b2', const <NgWordRule>[]);
        await ngStore.flushPendingWrites();

        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(
              prefs: prefs,
              broadcasterNgStore: ngStore,
            );

        // Legacy export has no broadcasterNgFilter; uses legacy
        // ngUserIds / ngWords / ngWordRules.
        final Map<String, dynamic> payload = AppSettings.defaults
            .copyWith(
              ngUserIds: 'l1\nl2',
              ngWords: 'old-word',
              ngWordRules: const <NgWordRule>[
                NgWordRule(pattern: 'structured', enabled: true),
              ],
            )
            .toJson();
        // Sanity: payload does not include the new key.
        expect(
          payload.containsKey(
            SharedPreferencesSettingsStore.exportBroadcasterNgKey,
          ),
          isFalse,
        );

        await settingsStore.importFromJson(jsonEncode(payload));
        await ngStore.flushPendingWrites();

        // Template populated.
        expect(await ngStore.loadTemplateNgUserIds(), <String>{'l1', 'l2'});
        final List<NgWordRule> tplRules = await ngStore
            .loadTemplateNgWordRules();
        expect(tplRules.map((NgWordRule r) => r.pattern).toSet(), <String>{
          'structured',
          'old-word',
        });

        // Both already-known broadcasters reseeded with legacy values.
        for (final String id in <String>['b1', 'b2']) {
          final BroadcasterNgPayload p = await ngStore
              .loadBroadcasterNgAttributes(id);
          expect(p.ngUserIds, <String>{'l1', 'l2'});
          expect(p.rules.map((NgWordRule r) => r.pattern).toSet(), <String>{
            'structured',
            'old-word',
          });
        }
      },
    );

    test(
      'does not create new broadcaster slots that were absent before import',
      () async {
        final InMemorySharedPreferences prefs = InMemorySharedPreferences();
        final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
          prefs: prefs,
        );
        // Empty store before import.
        expect(ngStore.listBroadcasters(), isEmpty);

        final SharedPreferencesSettingsStore settingsStore =
            SharedPreferencesSettingsStore(
              prefs: prefs,
              broadcasterNgStore: ngStore,
            );

        final Map<String, dynamic> payload = AppSettings.defaults
            .copyWith(ngUserIds: 'legacy', ngWords: 'word')
            .toJson();
        await settingsStore.importFromJson(jsonEncode(payload));
        await ngStore.flushPendingWrites();

        // Template populated, no broadcaster slots created.
        expect(await ngStore.loadTemplateNgUserIds(), <String>{'legacy'});
        expect(ngStore.listBroadcasters(), isEmpty);
      },
    );
  });

  group('importFromJson — precedence', () {
    test('broadcasterNgFilter wins when both new schema and legacy fields are '
        'present', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final BroadcasterNgStore ngStore = SharedPreferencesBroadcasterNgStore(
        prefs: prefs,
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(
            prefs: prefs,
            broadcasterNgStore: ngStore,
          );

      final Map<String, dynamic> payload = AppSettings.defaults
          .copyWith(ngUserIds: 'legacy-user', ngWords: 'legacy-word')
          .toJson();
      payload[SharedPreferencesSettingsStore.exportBroadcasterNgKey] =
          <String, dynamic>{
            'version': 1,
            'template': <String, dynamic>{
              'ngUserIds': <String>['new-user'],
              'ngWordRules': <Map<String, dynamic>>[
                <String, dynamic>{'pattern': 'new-pattern', 'enabled': true},
              ],
            },
            'broadcasters': <String, dynamic>{},
          };

      await settingsStore.importFromJson(jsonEncode(payload));
      await ngStore.flushPendingWrites();

      // Template reflects the new schema, NOT the legacy fields.
      expect(await ngStore.loadTemplateNgUserIds(), <String>{'new-user'});
      final List<NgWordRule> tplRules = await ngStore.loadTemplateNgWordRules();
      expect(tplRules.length, 1);
      expect(tplRules.first.pattern, 'new-pattern');
    });
  });
}
