import '../utils/semantic_version.dart';

/// 配信元（optional integration エンドポイント）から取得したバージョン情報。
///
/// 公開リポジトリのため配信元が無いビルド／クローンも存在する。取得経路の
/// 不在・失敗時はリポジトリ層が null を返し、本モデルは生成されない。
class RemoteVersionManifest {
  const RemoteVersionManifest({
    required this.latest,
    required this.minSupported,
    this.releaseUrl,
  });

  /// 公開されている最新版。配信元が最新を解決できない場合は null
  /// （その場合は任意更新通知を出さない）。
  final SemanticVersion? latest;

  /// この版未満は強制更新対象。配信元が値を持たない／不正な場合は
  /// `0.0.0` 相当とし、結果的に誰も強制ブロックされない（安全側）。
  final SemanticVersion minSupported;

  /// 更新を案内する公開ページ URL（配布ページ）。null の場合あり。
  final String? releaseUrl;
}

/// 更新判定の種別。
enum UpdateRequirement {
  /// 更新不要。
  none,

  /// 新しい版があるが任意（あとで閉じられる）。
  optional,

  /// サポート下限未満のため操作をブロックして強制更新する。
  forced,
}

/// 更新判定の結果。
class UpdateStatus {
  const UpdateStatus._(this.requirement, {this.latestVersion, this.releaseUrl});

  const UpdateStatus.none() : this._(UpdateRequirement.none);

  const UpdateStatus.optional({
    required SemanticVersion latestVersion,
    String? releaseUrl,
  }) : this._(
         UpdateRequirement.optional,
         latestVersion: latestVersion,
         releaseUrl: releaseUrl,
       );

  const UpdateStatus.forced({
    SemanticVersion? latestVersion,
    String? releaseUrl,
  }) : this._(
         UpdateRequirement.forced,
         latestVersion: latestVersion,
         releaseUrl: releaseUrl,
       );

  final UpdateRequirement requirement;

  /// 案内する最新版（強制時で最新が解決できない場合は null のことがある）。
  final SemanticVersion? latestVersion;

  /// 配布ページ URL。null の場合あり。
  final String? releaseUrl;

  bool get isNone => requirement == UpdateRequirement.none;
  bool get isOptional => requirement == UpdateRequirement.optional;
  bool get isForced => requirement == UpdateRequirement.forced;
}

/// 判定の結果と「そもそも確認できたか」を併せ持つ。
///
/// 起動時フローは [status] だけ見ればよい。設定画面の手動確認では
/// 「最新です」と「確認できませんでした（オフライン等）」を出し分ける
/// ため [couldCheck] を使う。
class UpdateCheckResult {
  const UpdateCheckResult({required this.status, required this.couldCheck});

  /// 確認不能（非対象 OS／配信元未設定・取得失敗／現在版が解析不能）。
  const UpdateCheckResult.unavailable()
    : status = const UpdateStatus.none(),
      couldCheck = false;

  final UpdateStatus status;

  /// 配信元から情報を取得し判定まで到達できたか。
  final bool couldCheck;
}
