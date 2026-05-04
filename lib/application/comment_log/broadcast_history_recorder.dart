import '../../data/comment_log/broadcast_history_store.dart';
import '../../domain/comment_log/broadcast_history_entry.dart';
import '../../presentation/screens/comment_screen_config.dart';

/// Issue #766: presentation 層から飛んできた `BroadcastEndedStatsSnapshot`
/// を、永続化向け `BroadcastHistoryEntry` に詰め替えて
/// `BroadcastHistoryStore` に書き込むまでを 1 関数で表現するアプリ層
/// ヘルパー。
///
/// gating ルール:
/// - `snapshot.isBroadcaster == false` → no-op（自分の放送のみ記録するため）
/// - `snapshot.lv` が空文字 → no-op（永続化キーのスキーマ崩れを避ける）
///
/// 上記いずれかで早期 return した場合は `null` を返す。書き込みを enqueue
/// した場合は対応する `Future<void>` を返す。テスト・統合点での観測しやすさ
/// 向上のため戻り値を `Future<void>?` にしている（select_screen 側は
/// `unawaited` して fire-and-forget する）。
Future<void>? recordBroadcastHistoryFromSnapshot({
  required BroadcastEndedStatsSnapshot snapshot,
  required BroadcastHistoryStore store,
}) {
  if (!snapshot.isBroadcaster) {
    return null;
  }
  if (snapshot.lv.isEmpty) {
    return null;
  }
  final BroadcastHistoryEntry entry = BroadcastHistoryEntry(
    lv: snapshot.lv,
    recordedAt: snapshot.endedAt,
    programTitle: snapshot.programTitle,
    broadcasterUserId: snapshot.broadcasterUserId,
    broadcasterName: snapshot.broadcasterName,
    beginAt: snapshot.beginAt,
    endedAt: snapshot.endedAt,
    totalComments: snapshot.totalComments,
    uniqueUserCount: snapshot.uniqueUserCount,
    durationSeconds: snapshot.durationSeconds,
    peakMinuteOffset: snapshot.peakMinuteOffset,
    peakMinuteCount: snapshot.peakMinuteCount,
    peaks: snapshot.peaks
        .map(
          (BroadcastEndedStatsPeak p) => BroadcastHistoryPeak(
            minuteOffset: p.minuteOffset,
            label: p.label,
            commentCount: p.commentCount,
          ),
        )
        .toList(growable: false),
  );
  return store.add(entry);
}
