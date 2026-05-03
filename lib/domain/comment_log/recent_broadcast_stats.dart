import 'package:flutter/foundation.dart';

/// Issue #767: 配信中の放送詳細から「直前1件」の統計を再表示するための、
/// メモリ上の最小スナップショット。
///
/// - 永続化はしない（再起動で消える）
/// - 自分の放送のみ記録対象（呼び出し側で `isBroadcaster` ガード）
/// - コメント本文は保持しない（プライバシ + 容量設計の最小化）
/// - 「直前1件」スコープに必要な指標（[CommentLogStats] 由来）と番組メタのみ
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
  });

  /// 直前放送の番組ID（`lv348712105` 等）。
  final String lv;

  /// この放送が ended/stopped に到達した時刻。同じ lv で再記録するか
  /// （再接続後の再 end）、取り扱いの判定に使う。
  final DateTime endedAt;

  /// `CommentLogStats.totalComments` と同等。
  final int totalComments;

  /// `CommentLogStats.uniqueUserCount` と同等。
  final int uniqueUserCount;

  /// `CommentLogStats.duration.inSeconds` と同等。
  final int durationSeconds;

  final String? programTitle;
  final DateTime? beginAt;

  /// 最も盛り上がった分の開始からのオフセット（無しなら null）。
  final int? peakMinuteOffset;

  /// 上記の分のコメント数（無しなら 0）。
  final int peakMinuteCount;

  /// 表示用のピークラベル（`開始25分` 形式）。再生成は呼び出し側に委ねる
  /// 設計だが、UI で計算ロジックを持ちたくないので保持する。
  final String? peakMinuteLabel;

  Duration get duration => Duration(seconds: durationSeconds);
}
