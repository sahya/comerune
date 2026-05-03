// Issue #727 SHOULD FIX 7: receipt-level coverage of the resolution logic
// that decides which (ngUserIds, ngWords) pair feeds the content filter.
//
// The function under test — [computeContentFilterInputs] — is exposed via
// `@visibleForTesting` from `select_screen.dart` as a top-level function,
// so we can exercise the resolution rules without spinning up the full
// SelectScreen widget tree.
//
// PR2 retargeted the NG list / NG word management screens to write
// through [BroadcasterNgStore], so the per-broadcaster path now returns
// the snapshot verbatim. The legacy union with `AppSettings` fields has
// been removed; tests assert that behaviour explicitly.

import 'package:comerune/data/filter/broadcaster_ng_store.dart';
import 'package:comerune/domain/models/app_settings.dart';
import 'package:comerune/domain/models/ng_word_rule.dart';
import 'package:comerune/presentation/select/select_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeContentFilterInputs', () {
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

    test('per-broadcaster path returns ONLY the snapshot values (no legacy '
        'union, PR2 semantics)', () {
      // The legacy AppSettings fields hold values that should be
      // ignored: writes now go through BroadcasterNgStore.
      final AppSettings settings = settingsWith(
        ngUserIds: 'legacy-user',
        ngWordRules: const <NgWordRule>[NgWordRule(pattern: 'legacy')],
      );
      final BroadcasterNgSnapshot snapshot = (
        broadcasterId: 'caster1',
        ngUserIds: <String>{'A'},
        rules: const <NgWordRule>[NgWordRule(pattern: 'Y')],
      );

      final ({Set<String> ngUserIds, List<String> ngWords}) result =
          computeContentFilterInputs(
            settings: settings,
            currentBroadcasterId: 'caster1',
            snapshot: snapshot,
            hasStore: true,
          );

      expect(result.ngUserIds, equals(<String>{'A'}));
      // Snapshot patterns are normalised through enabledNgWordPatterns.
      expect(result.ngWords, equals(<String>['y']));
    });

    test('per-broadcaster path drops disabled snapshot rules and empty '
        'patterns', () {
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
          computeContentFilterInputs(
            settings: settingsWith(),
            currentBroadcasterId: 'caster1',
            snapshot: snapshot,
            hasStore: true,
          );

      expect(result.ngWords, equals(<String>['snapshot']));
    });

    test('legacy fallback — store not wired returns only legacy values', () {
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
          computeContentFilterInputs(
            settings: settings,
            currentBroadcasterId: 'caster1',
            snapshot: snapshot,
            hasStore: false,
          );

      expect(result.ngUserIds, equals(<String>{'L'}));
      expect(result.ngWords, equals(<String>['legacy-word']));
    });

    test(
      'legacy fallback — no broadcasterId yet returns only legacy values',
      () {
        final AppSettings settings = settingsWith(
          ngUserIds: 'L',
          ngWords: 'legacy-word',
        );
        final BroadcasterNgSnapshot snapshot = (
          broadcasterId: 'caster1',
          ngUserIds: <String>{'stale'},
          rules: const <NgWordRule>[NgWordRule(pattern: 'stale-word')],
        );

        final ({Set<String> ngUserIds, List<String> ngWords}) result =
            computeContentFilterInputs(
              settings: settings,
              currentBroadcasterId: null,
              snapshot: snapshot,
              hasStore: true,
            );

        expect(result.ngUserIds, equals(<String>{'L'}));
        expect(result.ngWords, equals(<String>['legacy-word']));
      },
    );

    test('legacy fallback — stale snapshot (mismatched broadcasterId) is '
        'ignored and only legacy values are returned', () {
      final AppSettings settings = settingsWith(
        ngUserIds: 'L',
        ngWords: 'legacy-word',
      );
      final BroadcasterNgSnapshot snapshot = (
        broadcasterId: 'old-caster',
        ngUserIds: <String>{'stale-id'},
        rules: const <NgWordRule>[NgWordRule(pattern: 'stale-word')],
      );

      final ({Set<String> ngUserIds, List<String> ngWords}) result =
          computeContentFilterInputs(
            settings: settings,
            currentBroadcasterId: 'new-caster',
            snapshot: snapshot,
            hasStore: true,
          );

      expect(result.ngUserIds, equals(<String>{'L'}));
      expect(result.ngWords, equals(<String>['legacy-word']));
    });
  });
}
