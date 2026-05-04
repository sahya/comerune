import 'dart:convert';

import 'package:comerune/application/settings/settings_store.dart';
import 'package:comerune/data/comment_log/broadcast_history_store.dart';
import 'package:comerune/domain/comment_log/broadcast_history_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_shared_preferences.dart';

/// Issue #766 受け入れ基準: 設定の Export/Import 機能との整合性が取れている
/// （履歴は端末固有データとして除外する）。CLAUDE.md「設定項目の変更時の
/// 注意」: 古い Export ファイルに当該キーが無くても安全に動作する形を維持。
///
/// 本テストは「Export には history キーを含めない」「Import で history が
/// 消去・改変されない」の 2 点を回帰防御として保証する。
void main() {
  group('broadcast history × settings Export/Import 整合性', () {
    test('exportAsJson は stats.broadcastHistory.v1 を絶対に含まない', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore historyStore =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);
      // 履歴を 1 件入れた状態で Export しても出力 JSON に含まれないこと。
      await historyStore.add(
        BroadcastHistoryEntry(
          lv: 'lv999',
          recordedAt: DateTime.utc(2026, 5, 1),
          totalComments: 5,
          uniqueUserCount: 2,
          durationSeconds: 60,
        ),
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      final String exported = await settingsStore.exportAsJson();

      expect(
        exported.contains(SharedPreferencesBroadcastHistoryStore.storageKey),
        isFalse,
        reason:
            'Export JSON は stats.broadcastHistory.v1 を含むべきではない。'
            '含まれている場合 CLAUDE.md の整合性ルールが破れる。',
      );
      final Map<String, dynamic> json =
          jsonDecode(exported) as Map<String, dynamic>;
      expect(
        json.containsKey(SharedPreferencesBroadcastHistoryStore.storageKey),
        isFalse,
      );
    });

    test('importFromJson は履歴データを破壊しない', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore historyStore =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);
      await historyStore.add(
        BroadcastHistoryEntry(
          lv: 'lv1',
          recordedAt: DateTime.utc(2026, 5, 1),
          totalComments: 1,
          uniqueUserCount: 1,
          durationSeconds: 1,
        ),
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      // 別環境からの古い Export を模した JSON（history キーは無い）。
      final String oldExport = await settingsStore.exportAsJson();
      // 履歴は事前に 1 件あったが、history キーを含まない export を import
      // してもストアの履歴は維持されるべき。
      await settingsStore.importFromJson(oldExport);

      final List<BroadcastHistoryEntry> after = historyStore.loadAll();
      expect(after, hasLength(1));
      expect(after.first.lv, 'lv1');
    });

    test('不正な history-key を含む Import を渡しても history は変更されない', () async {
      final InMemorySharedPreferences prefs = InMemorySharedPreferences();
      final SharedPreferencesBroadcastHistoryStore historyStore =
          SharedPreferencesBroadcastHistoryStore(prefs: prefs);
      await historyStore.add(
        BroadcastHistoryEntry(
          lv: 'lv1',
          recordedAt: DateTime.utc(2026, 5, 1),
          totalComments: 1,
          uniqueUserCount: 1,
          durationSeconds: 1,
        ),
      );
      final SharedPreferencesSettingsStore settingsStore =
          SharedPreferencesSettingsStore(prefs: prefs);

      // 攻撃者由来 / 古い拡張バージョン由来で誤って history キーが
      // 混入したシナリオ。Import 経路は当該キーを無視する想定。
      final String malicious =
          '{"${SharedPreferencesBroadcastHistoryStore.storageKey}":'
          '"hijacked"}';
      await settingsStore.importFromJson(malicious);

      final List<BroadcastHistoryEntry> after = historyStore.loadAll();
      expect(after, hasLength(1));
      expect(after.first.lv, 'lv1');
    });
  });
}
