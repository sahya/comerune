import 'dart:convert';

import 'package:meta/meta.dart';

/// Issue #766: 過去放送のコメント統計を再アクセスできる履歴ビューの最小実装。
///
/// 1 件の終了済み放送について、当時の `CommentLogStats` 由来の指標と
/// 番組メタ情報のみを保持する。生コメント本文は保持しない（プライバシ／
/// 容量設計の観点で意図的に除外）。
@immutable
class BroadcastHistoryEntry {
  const BroadcastHistoryEntry({
    required this.lv,
    required this.recordedAt,
    this.programTitle,
    this.broadcasterUserId,
    this.broadcasterName,
    this.beginAt,
    this.endedAt,
    required this.totalComments,
    required this.uniqueUserCount,
    required this.durationSeconds,
    this.peakMinuteOffset,
    this.peakMinuteCount = 0,
    this.peaks = const <BroadcastHistoryPeak>[],
  });

  /// `lv348712105` のような番組ID。
  ///
  /// 永続化値由来であっても [programPageUrl] でクエリ汚染やパス Traversal を
  /// 起こさないよう、生成元 [tryFromJson] 側で [_lvPattern] による形式検証を
  /// 行う。直接生成する production パス（`SelectScreen`）では niconico 由来の
  /// `lv` のみが渡される前提。
  final String lv;

  /// このエントリが履歴に記録された時刻。並び順とユニーク識別の補助に使う。
  final DateTime recordedAt;

  final String? programTitle;
  final String? broadcasterUserId;
  final String? broadcasterName;
  final DateTime? beginAt;
  final DateTime? endedAt;

  final int totalComments;
  final int uniqueUserCount;
  final int durationSeconds;

  /// 最も盛り上がった分（開始からの分オフセット）。盛り上がりが無い時は null。
  final int? peakMinuteOffset;

  /// 上記分のコメント数。
  final int peakMinuteCount;

  /// `CommentLogStats.detectPeaks` から抽出した盛り上がりピーク
  /// （最大 3 件想定）。代表コメント本文は保持しない。
  final List<BroadcastHistoryPeak> peaks;

  Duration get duration => Duration(seconds: durationSeconds);

  /// niconico 公式の番組ページ URL。
  ///
  /// 二重防御として `Uri` ビルダーを使い、`lv` に文字列補間で意図せぬクエリ
  /// (`?...`) や fragment (`#...`) が混じった場合でもパスとして
  /// percent-encode される（[Uri.pathSegments]）。生成元 [tryFromJson] 側でも
  /// [_lvPattern] による事前検証を行うが、直接生成パス・将来の field 増加に
  /// 備える。
  String get programPageUrl => Uri(
    scheme: 'https',
    host: 'live.nicovideo.jp',
    pathSegments: <String>['watch', lv],
  ).toString();

  /// 表示用の盛り上がりピークラベル（`開始25分` 形式）。
  String? get peakMinuteLabel {
    final int? offset = peakMinuteOffset;
    if (offset == null || peakMinuteCount <= 0) {
      return null;
    }
    return _formatPeakLabel(offset);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'lv': lv,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    if (programTitle != null) 'programTitle': programTitle,
    if (broadcasterUserId != null) 'broadcasterUserId': broadcasterUserId,
    if (broadcasterName != null) 'broadcasterName': broadcasterName,
    if (beginAt != null) 'beginAt': beginAt!.toUtc().toIso8601String(),
    if (endedAt != null) 'endedAt': endedAt!.toUtc().toIso8601String(),
    'totalComments': totalComments,
    'uniqueUserCount': uniqueUserCount,
    'durationSeconds': durationSeconds,
    if (peakMinuteOffset != null) 'peakMinuteOffset': peakMinuteOffset,
    'peakMinuteCount': peakMinuteCount,
    if (peaks.isNotEmpty)
      'peaks': peaks.map((BroadcastHistoryPeak p) => p.toJson()).toList(),
  };

  /// niconico の `lv` 形式（`lv` + 数字）を検証する正規表現。永続化値が
  /// 改ざんされていた場合に [programPageUrl] が想定外の URL を組み立てない
  /// ようにする防御層。
  static final RegExp _lvPattern = RegExp(r'^lv\d+$');

  /// JSON からの復元。型不一致や欠損は安全に無視する（旧バージョン互換）。
  ///
  /// `lv` は [_lvPattern] と一致しない値を弾く。整数系フィールドの負数も
  /// 0 にクランプし、表示で負のコメント数のような不整合を出さない。
  static BroadcastHistoryEntry? tryFromJson(Object? raw) {
    if (raw is! Map<dynamic, dynamic>) {
      return null;
    }
    final Object? lvValue = raw['lv'];
    if (lvValue is! String || !_lvPattern.hasMatch(lvValue)) {
      return null;
    }
    final DateTime? recordedAt = _parseDateTime(raw['recordedAt']);
    if (recordedAt == null) {
      return null;
    }
    final List<BroadcastHistoryPeak> peaks = <BroadcastHistoryPeak>[];
    final Object? peaksRaw = raw['peaks'];
    if (peaksRaw is List<dynamic>) {
      for (final Object? item in peaksRaw) {
        final BroadcastHistoryPeak? peak = BroadcastHistoryPeak.tryFromJson(
          item,
        );
        if (peak != null) {
          peaks.add(peak);
        }
      }
    }
    return BroadcastHistoryEntry(
      lv: lvValue,
      recordedAt: recordedAt,
      programTitle: _readString(raw['programTitle']),
      broadcasterUserId: _readString(raw['broadcasterUserId']),
      broadcasterName: _readString(raw['broadcasterName']),
      beginAt: _parseDateTime(raw['beginAt']),
      endedAt: _parseDateTime(raw['endedAt']),
      // 整数系は負数を 0 にクランプ。永続化値が破損してもユーザーに
      // 「-3 件」のような不整合表示が出ないようにする。
      totalComments: _readNonNegativeInt(raw['totalComments']),
      uniqueUserCount: _readNonNegativeInt(raw['uniqueUserCount']),
      durationSeconds: _readNonNegativeInt(raw['durationSeconds']),
      peakMinuteOffset: _readNonNegativeIntOrNull(raw['peakMinuteOffset']),
      peakMinuteCount: _readNonNegativeInt(raw['peakMinuteCount']),
      peaks: peaks,
    );
  }

  String encodeJson() => json.encode(toJson());

  static BroadcastHistoryEntry? tryDecodeJson(String raw) {
    try {
      return tryFromJson(json.decode(raw));
    } on Object {
      return null;
    }
  }

  /// 「同じ放送」を表すかどうかの判定。lv が一致すれば同一放送とみなす。
  bool isSameBroadcast(BroadcastHistoryEntry other) => lv == other.lv;

  static String _formatPeakLabel(int minuteOffset) {
    if (minuteOffset < 60) {
      return '開始$minuteOffset分';
    }
    final int hours = minuteOffset ~/ 60;
    final int minutes = minuteOffset % 60;
    if (minutes == 0) {
      return '開始$hours時間';
    }
    return '開始$hours時間$minutes分';
  }

  static String? _readString(Object? raw) {
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  static int? _readInt(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  static int _readNonNegativeInt(Object? raw) {
    final int v = _readInt(raw) ?? 0;
    return v < 0 ? 0 : v;
  }

  static int? _readNonNegativeIntOrNull(Object? raw) {
    final int? v = _readInt(raw);
    if (v == null) {
      return null;
    }
    return v < 0 ? null : v;
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }
}

/// 履歴エントリ内の盛り上がりピーク 1 件。代表コメント本文は保持しない。
@immutable
class BroadcastHistoryPeak {
  const BroadcastHistoryPeak({
    required this.minuteOffset,
    required this.label,
    required this.commentCount,
  });

  final int minuteOffset;
  final String label;
  final int commentCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'minuteOffset': minuteOffset,
    'label': label,
    'commentCount': commentCount,
  };

  static BroadcastHistoryPeak? tryFromJson(Object? raw) {
    if (raw is! Map<dynamic, dynamic>) {
      return null;
    }
    final Object? minuteOffset = raw['minuteOffset'];
    final Object? label = raw['label'];
    final Object? commentCount = raw['commentCount'];
    if (minuteOffset is! num || label is! String || commentCount is! num) {
      return null;
    }
    final int minute = minuteOffset.toInt();
    final int count = commentCount.toInt();
    if (minute < 0 || count < 0) {
      return null;
    }
    return BroadcastHistoryPeak(
      minuteOffset: minute,
      label: label,
      commentCount: count,
    );
  }
}
