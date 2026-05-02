// Issue #727 SHOULD FIX 7: receipt-level coverage of the resolution logic
// that decides which (ngUserIds, ngWords) pair feeds the content filter.
//
// The function under test — [resolveContentFilterLogic] — is exposed via
// `@visibleForTesting` from `select_screen.dart` as a top-level function,
// so we can exercise the resolution rules without spinning up the full
// SelectScreen widget tree.

import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/select/select_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveContentFilterLogic', () {
    AppSettings settingsWith({
      String ngUserIds = '',
      List<NgWordRule> ngWordRules = const <NgWordRule>[],
      String ngWords = '',
    }) {
      return AppSettings.defaults.copyWith(
        ngUserIds: ngUserIds,
        ngWordRules: ngWordRules,
        ngWords: ngWords,
      );
    }

    test(
      'per-broadcaster path unions snapshot with legacy AppSettings '
      'fields (MUST FIX 1 semantics)',
      () {
        final AppSettings settings = settingsWith(
          ngUserIds: 'B',
          ngWordRules: const <NgWordRule>[NgWordRule(pattern: 'X')],
        );
        final BroadcasterNgSnapshot snapshot = (
          broadcasterId: 'caster1',
          ngUserIds: <String>{'A'},
          rules: const <NgWordRule>[NgWordRule(pattern: 'Y')],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            resolveContentFilterLogic(
              settings: settings,
              currentBroadcasterId: 'caster1',
              snapshot: snapshot,
              hasStore: true,
            );

        expect(result.ngUserIds, equals(<String>{'A', 'B'}));
        // Patterns are normalised to lower case via enabledNgWordPatterns
        // / AppSettings.ngWordList; the union must contain both sources.
        expect(result.ngWords.toSet(), equals(<String>{'x', 'y'}));
      },
    );

    test(
      'legacy fallback — store not wired returns only legacy values',
      () {
        final AppSettings settings = settingsWith(
          ngUserIds: 'L',
          ngWords: 'legacy-word',
        );
        const BroadcasterNgSnapshot snapshot = (
          broadcasterId: null,
          ngUserIds: <String>{},
          rules: <NgWordRule>[],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            resolveContentFilterLogic(
              settings: settings,
              currentBroadcasterId: 'caster1',
              snapshot: snapshot,
              hasStore: false,
            );

        expect(result.ngUserIds, equals(<String>{'L'}));
        expect(result.ngWords, equals(<String>['legacy-word']));
      },
    );

    test(
      'legacy fallback — no broadcasterId yet returns only legacy values',
      () {
        final AppSettings settings = settingsWith(
          ngUserIds: 'L',
          ngWords: 'legacy-word',
        );
        // Snapshot for a previous broadcaster, but we are not connected.
        final BroadcasterNgSnapshot snapshot = (
          broadcasterId: 'caster1',
          ngUserIds: <String>{'stale'},
          rules: const <NgWordRule>[NgWordRule(pattern: 'stale-word')],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            resolveContentFilterLogic(
              settings: settings,
              currentBroadcasterId: null,
              snapshot: snapshot,
              hasStore: true,
            );

        expect(result.ngUserIds, equals(<String>{'L'}));
        expect(result.ngWords, equals(<String>['legacy-word']));
      },
    );

    test(
      'legacy fallback — stale snapshot (mismatched broadcasterId) is '
      'ignored and only legacy values are returned',
      () {
        final AppSettings settings = settingsWith(
          ngUserIds: 'L',
          ngWords: 'legacy-word',
        );
        // The snapshot's broadcasterId is from an earlier connection;
        // the resolver must not leak those IDs into the new connection.
        final BroadcasterNgSnapshot snapshot = (
          broadcasterId: 'old-caster',
          ngUserIds: <String>{'stale-id'},
          rules: const <NgWordRule>[NgWordRule(pattern: 'stale-word')],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            resolveContentFilterLogic(
              settings: settings,
              currentBroadcasterId: 'new-caster',
              snapshot: snapshot,
              hasStore: true,
            );

        expect(result.ngUserIds, equals(<String>{'L'}));
        expect(result.ngWords, equals(<String>['legacy-word']));
      },
    );

    test(
      'per-broadcaster path drops disabled snapshot rules and empty '
      'patterns when unioning with legacy ngWordList',
      () {
        final AppSettings settings = settingsWith(
          ngWordRules: const <NgWordRule>[
            NgWordRule(pattern: ' Legacy '),
            NgWordRule(pattern: 'disabled-legacy', enabled: false),
          ],
        );
        final BroadcasterNgSnapshot snapshot = (
          broadcasterId: 'caster1',
          ngUserIds: const <String>{},
          rules: const <NgWordRule>[
            NgWordRule(pattern: '  Snapshot  '),
            NgWordRule(pattern: 'off', enabled: false),
            NgWordRule(pattern: '   '),
          ],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            resolveContentFilterLogic(
              settings: settings,
              currentBroadcasterId: 'caster1',
              snapshot: snapshot,
              hasStore: true,
            );

        // Both sources go through the trim+lower normalisation. Disabled
        // and empty patterns are dropped.
        expect(result.ngWords.toSet(), equals(<String>{'snapshot', 'legacy'}));
      },
    );
  });
}
