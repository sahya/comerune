import 'package:flutter/foundation.dart';

import '../../domain/comment_log/recent_broadcast_stats.dart';

/// Issue #767: 直前1件の放送統計をメモリ保持する `ChangeNotifier`。
///
/// - **メモリのみ**（再起動で消える / 永続化は Issue #766 の責務）
/// - 1 件だけ保持。新しい放送が ended に到達するたびに置き換わる
/// - `ComeruneApp` レベルで生成され、lv 切り替えを跨いで生存する
/// - 視聴セッションの統計は **保存しない**（呼び出し側で `isBroadcaster`
///   をガードする）
class RecentBroadcastStatsHolder extends ChangeNotifier {
  RecentBroadcastStats? _value;

  /// 現在保持している直前統計。未設定または `clear` 直後は null。
  RecentBroadcastStats? get value => _value;

  /// 1 件保持を更新する。同一 lv の上書きは「再接続→再 end」のような
  /// 流れで自然に発生するので許容する（最新の `endedAt` が勝ち）。
  void update(RecentBroadcastStats stats) {
    _value = stats;
    notifyListeners();
  }

  /// 明示的に破棄する。実運用では使わない（次の `update` で置き換わるため）。
  /// テスト・設定リセット等で利用する想定。
  void clear() {
    if (_value == null) {
      return;
    }
    _value = null;
    notifyListeners();
  }
}
