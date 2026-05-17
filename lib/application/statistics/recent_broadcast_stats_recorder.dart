import '../../domain/comment_log/recent_broadcast_stats.dart';
import 'recent_broadcast_stats_holder.dart';

/// Issue #767: presentation 層から飛んできた `RecentBroadcastStats`
/// snapshot を、メモリ保持の [RecentBroadcastStatsHolder] に書き込むまでの
/// gating ロジックをアプリ層に切り出したヘルパー。`select_screen` 側で
/// inline 実装していたものをテスト容易な形に集約。
///
/// gating ルール:
/// - `snapshot.isBroadcaster == false` → no-op（視聴セッションは「直前」として
///   扱わない）
/// - `snapshot.lv` が空文字 → no-op（不正な lv で UI 経路を汚染しない）
///
/// gating で no-op になった場合は `false` を、holder を更新した場合は `true`
/// を返す。テストでの観測しやすさのため。
bool recordRecentBroadcastStatsToHolder({
  required RecentBroadcastStats snapshot,
  required RecentBroadcastStatsHolder holder,
}) {
  if (!snapshot.isBroadcaster) {
    return false;
  }
  if (snapshot.lv.isEmpty) {
    return false;
  }
  holder.update(snapshot);
  return true;
}
