import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import '../../domain/models/app_update.dart';
import '../../domain/utils/semantic_version.dart';

/// GitHub Releases API から最新の安定リリースを取得し、強制更新マーカーを
/// 含めて [RemoteVersionManifest] にマッピングする。
///
/// ## 設計意図
/// 自前のバージョン配信エンドポイントを置くと、そこが単一障害点／攻撃面に
/// なり、運用者が同意なしにダッシュボード操作だけで全ユーザーを強制更新で
/// ブリックできてしまう。本実装は**公開リポジトリの GitHub Releases そのもの**
/// を唯一の真実の源にすることで、
///
/// - 新たな自前インフラを増やさない（攻撃面を増やさない）
/// - 強制更新の発動には GitHub Release の作成（＝コードレビュー後のタグ
///   操作）が必須で、リポジトリ履歴・Release 編集履歴に監査痕跡が残る
/// - サポート下限の変更も Release 本文の編集として GitHub 上に履歴が残る
///
/// ## 強制更新マーカー
/// Release 本文に `<!-- min-supported: X.Y.Z -->` を埋めると、その Release
/// 公開以降に古い版で起動したユーザーは強制更新画面でブロックされる。
/// HTML コメントなので GitHub の Release ページ表示では非表示。マーカーは
/// 大文字小文字を区別せず、`v` プレフィクスも許容する。
///
/// ## `/releases/latest` の仕様メモ
/// GitHub の `/releases/latest` は**最後に「latest としてマーク」された
/// 非プレリリース**を返す（厳密に最高 SemVer ではない）。例えば `v1.4.0`
/// 公開後に過去ブランチから `v1.3.5` を後発で公開すると `latest=1.3.5`
/// となるが、本実装は `current < latest` のときだけ通知する設計なので
/// `v1.4.0` 利用者には何も起きず実害は出ない。
///
/// ## レート制限
/// 匿名 GitHub API は IP あたり 60 req/h。起動毎 1 回・キャッシュ無しでも
/// 個人利用なら事実上問題ない。共有 NAT で多数ユーザーが同 IP の場合は
/// 通信失敗→ no-op（fail-open）になる。
///
/// ## 失敗時の挙動（CLAUDE.md 2 段フォールバック）
/// 通信失敗・タイムアウト・JSON 不正・SemVer 解析不能のいずれでも例外を
/// 投げず、ログだけ残して null を返す。呼び出し側で「判定不能」として
/// 安全側に倒す。
class GithubReleaseRepository {
  GithubReleaseRepository({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 8),
    String owner = _defaultOwner,
    String repo = _defaultRepo,
    String userAgent = _defaultUserAgent,
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _owner = owner,
       _repo = repo,
       _userAgent = userAgent;

  static const String _defaultOwner = 'sahya';
  static const String _defaultRepo = 'comerune';
  // GitHub API は User-Agent 必須。クライアント識別子を控えめに名乗る。
  static const String _defaultUserAgent = 'comerune-android';
  static const String _logName = 'GithubReleaseRepository';

  final http.Client _httpClient;
  final Duration _timeout;
  final String _owner;
  final String _repo;
  final String _userAgent;

  /// `<!-- min-supported: X.Y.Z -->`（前後空白・先頭 `v`/`V`・大文字小文字を
  /// 許容）を抽出する正規表現。
  static final RegExp _minSupportedRe = RegExp(
    r'<!--\s*min-supported:\s*v?([0-9]+\.[0-9]+\.[0-9]+)\s*-->',
    caseSensitive: false,
  );

  Uri get _endpoint =>
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');

  /// 取得・解析に成功した場合のみ [RemoteVersionManifest] を返す。
  /// それ以外（通信失敗・JSON 不正・タグ解析不能など）はすべて null。
  Future<RemoteVersionManifest?> fetch() async {
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            _endpoint,
            headers: <String, String>{
              'Accept': 'application/vnd.github+json',
              'User-Agent': _userAgent,
            },
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      // 例外の文字列に URL が含まれることがあるため `$e` を展開しない。
      // `Error` は伝搬させる。
      log('release fetch failed (${e.runtimeType})', name: _logName);
      return null;
    }

    if (response.statusCode != 200) {
      log(
        'release fetch returned status ${response.statusCode}',
        name: _logName,
      );
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      log('release fetch returned malformed JSON', name: _logName);
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      log('release JSON is not an object', name: _logName);
      return null;
    }

    // `/releases/latest` は draft / prerelease を除外するが、念のため
    // フラグでも防御する（true なら latest 扱いしない）。
    if (decoded['draft'] == true || decoded['prerelease'] == true) {
      return RemoteVersionManifest(
        latest: null,
        minSupported: const SemanticVersion(0, 0, 0),
        releaseUrl: _asHttpsUrl(decoded['html_url']),
      );
    }

    final SemanticVersion? latest = SemanticVersion.tryParse(
      _asString(decoded['tag_name']) ?? _asString(decoded['name']),
    );
    final SemanticVersion minSupported =
        _extractMinSupported(_asString(decoded['body'])) ??
        const SemanticVersion(0, 0, 0);
    final String? releaseUrl = _asHttpsUrl(decoded['html_url']);

    return RemoteVersionManifest(
      latest: latest,
      minSupported: minSupported,
      releaseUrl: releaseUrl,
    );
  }

  static SemanticVersion? _extractMinSupported(String? body) {
    if (body == null) {
      return null;
    }
    final RegExpMatch? m = _minSupportedRe.firstMatch(body);
    if (m == null) {
      return null;
    }
    return SemanticVersion.tryParse(m.group(1));
  }

  static String? _asString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  /// `url` は外部ブラウザで開くため https のみ受け付ける
  /// （javascript: 等のスキーム注入を弾く防御）。
  static String? _asHttpsUrl(Object? value) {
    if (value is! String) {
      return null;
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return null;
    }
    return value;
  }
}
