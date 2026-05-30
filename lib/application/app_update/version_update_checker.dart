import 'dart:developer';

import '../../data/app_update/github_release_repository.dart';
import '../../domain/models/app_update.dart';
import '../../domain/utils/semantic_version.dart';

/// 現在のアプリ版と GitHub Releases の情報を突き合わせ、更新の要否を判定する。
///
/// 判定は純粋ロジックで、UI も永続化も行わない。
///
/// ## fail-open 方針
/// 次のいずれでも [UpdateCheckResult.unavailable]（=ブロックも通知もしない）:
/// - 非対象プラットフォーム（Android 以外）
/// - GitHub Releases 取得失敗（[GithubReleaseRepository.fetch] が null）
/// - 現在版が解析不能
///
/// オフラインや一時障害で正規ユーザーを締め出さないため、強制ブロックは
/// 「サポート下限を確実に下回ると判明したとき」だけに限定する。
class VersionUpdateChecker {
  VersionUpdateChecker({
    required GithubReleaseRepository repository,
    required bool isSupportedPlatform,
  }) : _repository = repository,
       _isSupportedPlatform = isSupportedPlatform;

  final GithubReleaseRepository _repository;
  final bool _isSupportedPlatform;

  static const String _logName = 'VersionUpdateChecker';

  /// [currentVersion] は `package_info_plus` 由来の版文字列（例 `1.0.0`）。
  Future<UpdateCheckResult> check(String currentVersion) async {
    if (!_isSupportedPlatform) {
      return const UpdateCheckResult.unavailable();
    }

    final SemanticVersion? current = SemanticVersion.tryParse(currentVersion);
    if (current == null) {
      log(
        'current app version is not parseable; skipping update check',
        name: _logName,
      );
      return const UpdateCheckResult.unavailable();
    }

    final RemoteVersionManifest? manifest = await _repository.fetch();
    if (manifest == null) {
      // 取得失敗 → fail-open。
      return const UpdateCheckResult.unavailable();
    }

    if (current < manifest.minSupported) {
      return UpdateCheckResult(
        status: UpdateStatus.forced(
          latestVersion: manifest.latest,
          releaseUrl: manifest.releaseUrl,
        ),
        couldCheck: true,
      );
    }

    final SemanticVersion? latest = manifest.latest;
    if (latest != null && current < latest) {
      return UpdateCheckResult(
        status: UpdateStatus.optional(
          latestVersion: latest,
          releaseUrl: manifest.releaseUrl,
        ),
        couldCheck: true,
      );
    }

    return const UpdateCheckResult(
      status: UpdateStatus.none(),
      couldCheck: true,
    );
  }
}
