import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../../application/settings/settings_store.dart';
import '../../domain/comment_log/broadcast_history_entry.dart';

/// Issue #766: 過去放送のコメント統計を再アクセスできる履歴ビューの最小実装。
///
/// 端末ローカルにのみ保存し、外部送信は行わない。設定の Export/Import からは
/// 意図的に除外（端末固有データ・古い Export ファイルとの後方互換性維持）。
abstract class BroadcastHistoryStore {
  /// 直近に記録した順（新しい順）で全件を返す。
  ///
  /// 件数上限は実装依存（[SharedPreferencesBroadcastHistoryStore] の場合
  /// [SharedPreferencesBroadcastHistoryStore.maxEntries]）。同期 API なので
  /// 画面初期化のたびに呼んで問題ない。
  List<BroadcastHistoryEntry> loadAll();

  /// 1 件追加する。同じ放送（lv 一致）が既にある場合は新しい [entry] で
  /// 置き換え（重複排除）。古いほうから保持上限まで切り詰める。
  ///
  /// 並列呼び出しは内部で直列化される。
  Future<void> add(BroadcastHistoryEntry entry);

  /// `lv` を指定して 1 件削除する。存在しない場合は no-op。
  Future<void> removeByLv(String lv);

  /// 全件削除する。
  Future<void> clearAll();
}

/// SharedPreferences 永続化版。1 つのキーに JSON 配列で全件を持つ。
///
/// 50 件程度なので JSON 1 ファイル設計で十分。書き込みは serial chain。
class SharedPreferencesBroadcastHistoryStore implements BroadcastHistoryStore {
  SharedPreferencesBroadcastHistoryStore({
    required SharedPreferencesLike prefs,
    int maxEntries = defaultMaxEntries,
  }) : assert(maxEntries > 0, 'maxEntries must be positive'),
       _prefs = prefs,
       _maxEntries = maxEntries;

  /// 既定の保持上限（Issue #766 設計判断）。
  static const int defaultMaxEntries = 50;

  /// 永続化キー。スキーマを破壊変更する際は v2 に上げて旧キーから移行する想定。
  static const String storageKey = 'stats.broadcastHistory.v1';

  final SharedPreferencesLike _prefs;
  final int _maxEntries;
  Future<void> _pendingWriteChain = Future<void>.value();

  /// 保持上限（テストや設定 UI から参照可能にするための公開フィールド）。
  int get maxEntries => _maxEntries;

  @override
  List<BroadcastHistoryEntry> loadAll() => _readAll();

  @override
  Future<void> add(BroadcastHistoryEntry entry) {
    return _enqueueWrite(() async {
      final List<BroadcastHistoryEntry> current = _readAll();
      // 同じ lv を全て除去してから先頭に追加（重複排除 + 最新化）。
      current.removeWhere(
        (BroadcastHistoryEntry e) => e.isSameBroadcast(entry),
      );
      current.insert(0, entry);
      // 古い側を切り捨てる。
      final List<BroadcastHistoryEntry> trimmed = current.length > _maxEntries
          ? current.sublist(0, _maxEntries)
          : current;
      await _writeAll(trimmed);
    });
  }

  @override
  Future<void> removeByLv(String lv) {
    if (lv.isEmpty) {
      return Future<void>.value();
    }
    return _enqueueWrite(() async {
      final List<BroadcastHistoryEntry> current = _readAll();
      final int before = current.length;
      current.removeWhere((BroadcastHistoryEntry e) => e.lv == lv);
      if (current.length == before) {
        return;
      }
      await _writeAll(current);
    });
  }

  @override
  Future<void> clearAll() {
    return _enqueueWrite(() async {
      await _prefs.remove(storageKey);
    });
  }

  List<BroadcastHistoryEntry> _readAll() {
    final String? raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return <BroadcastHistoryEntry>[];
    }
    try {
      final Object? decoded = json.decode(raw);
      if (decoded is! List<dynamic>) {
        return <BroadcastHistoryEntry>[];
      }
      final List<BroadcastHistoryEntry> result = <BroadcastHistoryEntry>[];
      for (final Object? item in decoded) {
        final BroadcastHistoryEntry? entry = BroadcastHistoryEntry.tryFromJson(
          item,
        );
        if (entry != null) {
          result.add(entry);
        }
      }
      return result;
    } on Object catch (e, st) {
      // 型ずれ・JSON 不整合はログだけ残してエラーを伝播させない
      // （CLAUDE.md: 永続化値のパースで Error 系を素通りさせない方針に倣う）。
      developer.log(
        'Failed to decode broadcast history',
        name: 'BroadcastHistoryStore',
        error: e,
        stackTrace: st,
      );
      return <BroadcastHistoryEntry>[];
    }
  }

  Future<void> _writeAll(List<BroadcastHistoryEntry> entries) async {
    if (entries.isEmpty) {
      await _prefs.remove(storageKey);
      return;
    }
    final List<Map<String, Object?>> encoded = entries
        .map((BroadcastHistoryEntry e) => e.toJson())
        .toList(growable: false);
    await _prefs.setString(storageKey, json.encode(encoded));
  }

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final Future<T> scheduled = _pendingWriteChain.then<T>((_) => operation());
    _pendingWriteChain = scheduled.then<void>((_) {}).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      developer.log(
        'BroadcastHistoryStore write failed',
        name: 'BroadcastHistoryStore',
        error: error,
        stackTrace: stackTrace,
      );
    });
    return scheduled;
  }
}
