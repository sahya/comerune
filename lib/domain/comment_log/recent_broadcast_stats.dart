import 'package:flutter/foundation.dart';

import 'comment_log_stats.dart';

/// Issue #767: 配信中の放送詳細から「直前1件」の統計を再表示するための、
/// メモリ上の最小スナップショット。
///
/// - 永続化はしない（再起動で消える）
/// - 自分の放送のみ記録対象（[isBroadcaster] フラグで呼び出し側がガード）
/// - コメント本文は保持しない（プライバシ + 容量設計の最小化）
/// - 「直前1件」スコープに必要な指標（[CommentLogStats] 由来）と番組メタのみ
///
/// 当初は presentation 層の `RecentBroadcastStatsSnapshot`（コールバック
/// 引数）と、`RecentBroadcastStatsHolder` が保持する `RecentBroadcastStats`
/// の 2 型に分かれていたが、フィールドが完全同型でドリフトリスクが高かった
/// ため 1 型に統合した（Issue #767 賢者レビュー対応）。
/// `isBroadcaster` フラグは callback 受信側のフィルタ用途で使われ、holder
/// に書き込む段階では意味を持たない（true でなければ holder.update が
/// 呼ばれない）。
@immutable
class RecentBroadcastStats {
  const RecentBroadcastStats({
    required this.lv,
    required this.endedAt,
    required this.totalComments,
    required this.uniqueUserCount,
    required this.durationSeconds,
    this.programTitle,
    this.beginAt,
    this.peakMinuteOffset,
    this.peakMinuteCount = 0,
    this.peakMinuteLabel,
    this.isBroadcaster = false,
  });

  /// `CommentLogStats` から `peakMinuteOffset` を決定論的に導出する純関数。
  ///
  /// `commentsPerMinute` の中で `peakMinuteCount` と一致する分のうち
  /// 最小キーを返す。`CommentLogStats.fromMessages` が natural map
  /// iteration で「最初に到達した最大値」を採用しているのに合わせ、再起動
  /// やテストでも同じ値を再現できるようにするための tiebreak 規則。
  ///
  /// `peakMinuteCount` が 0、または `peakMinuteLabel` が null の場合は
  /// 「ピーク無し」とみなし null を返す。
  ///
  /// 元は `comment_screen.dart` 内に inline で書かれていたが、テスト容易
  /// 化と再利用性のため domain 層の純関数として切り出した。
  static int? resolvePeakMinuteOffset(CommentLogStats stats) {
    if (stats.peakMinuteCount <= 0 || stats.peakMinuteLabel == null) {
      return null;
    }
    int? smallest;
    for (final MapEntry<int, int> entry in stats.commentsPerMinute.entries) {
      if (entry.value == stats.peakMinuteCount) {
        if (smallest == null || entry.key < smallest) {
          smallest = entry.key;
        }
      }
    }
    return smallest;
  }

  /// 直前放送の番組ID（`lv348712105` 等）。
  final String lv;

  /// この放送が ended/stopped に到達した時刻。
  ///
  /// 時刻ゾーン: 生成元（`comment_screen._notifyRecentBroadcastStatsCaptured`）
  /// が `_endedAt ?? DateTime.now()` をそのまま渡すため、production では
  /// **ローカル時刻**になる。テストで `DateTime.utc(...)` を渡すと
  /// `==` が時刻ゾーン違いで一致しないので、テスト fixture もローカル時刻
  /// に統一すること。
  final DateTime endedAt;

  /// `CommentLogStats.totalComments` と同等。
  final int totalComments;

  /// `CommentLogStats.uniqueUserCount` と同等。
  final int uniqueUserCount;

  /// `CommentLogStats.duration.inSeconds` と同等。
  final int durationSeconds;

  final String? programTitle;

  /// 放送開始時刻。`endedAt` と同じく**ローカル時刻**で保持される
  /// （生成元の `widget.programInfo.beginAt` がそのまま流れてくる）。
  final DateTime? beginAt;

  /// 最も盛り上がった分の開始からのオフセット（無しなら null）。
  final int? peakMinuteOffset;

  /// 上記の分のコメント数（無しなら 0）。
  final int peakMinuteCount;

  /// 表示用のピークラベル（`開始25分` 形式）。
  final String? peakMinuteLabel;

  /// True when the local user is the broadcaster of this program.
  /// Issue #767 設計判断: 視聴のみの放送は「直前」として扱わない。
  /// callback 受信側はこのフラグが false ならば早期 return する。
  ///
  /// holder にセットされた値は常に true（false なら update が呼ばれない）
  /// なので、UI 描画ロジックは本フラグを見る必要が無い。
  final bool isBroadcaster;

  Duration get duration => Duration(seconds: durationSeconds);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentBroadcastStats &&
          runtimeType == other.runtimeType &&
          lv == other.lv &&
          endedAt == other.endedAt &&
          totalComments == other.totalComments &&
          uniqueUserCount == other.uniqueUserCount &&
          durationSeconds == other.durationSeconds &&
          programTitle == other.programTitle &&
          beginAt == other.beginAt &&
          peakMinuteOffset == other.peakMinuteOffset &&
          peakMinuteCount == other.peakMinuteCount &&
          peakMinuteLabel == other.peakMinuteLabel &&
          isBroadcaster == other.isBroadcaster;

  @override
  int get hashCode => Object.hash(
    lv,
    endedAt,
    totalComments,
    uniqueUserCount,
    durationSeconds,
    programTitle,
    beginAt,
    peakMinuteOffset,
    peakMinuteCount,
    peakMinuteLabel,
    isBroadcaster,
  );
}
