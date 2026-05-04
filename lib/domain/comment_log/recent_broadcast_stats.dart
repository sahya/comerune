import 'package:flutter/foundation.dart';

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

  /// 直前放送の番組ID（`lv348712105` 等）。
  final String lv;

  /// この放送が ended/stopped に到達した時刻。
  final DateTime endedAt;

  final int totalComments;
  final int uniqueUserCount;

  /// `CommentLogStats.duration.inSeconds` と同等。
  final int durationSeconds;

  final String? programTitle;
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
