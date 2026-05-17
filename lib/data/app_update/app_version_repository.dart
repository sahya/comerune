import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;

import '../../domain/models/app_update.dart';
import '../../domain/utils/semantic_version.dart';

/// バージョン情報配信エンドポイントから最新版・サポート下限版を取得する。
///
/// エンドポイント URL はビルド時注入（`--dart-define=APP_VERSION_ENDPOINT=...`）
/// で渡す。OAuth ホストと同じ流儀で、公開リポジトリのフォーク／クローンに
/// 本番識別子を埋め込まないための措置。未設定ビルドでは機能全体が静かに
/// no-op になる（[fetch] が null を返す）。
///
/// CLAUDE.md「オプション参照先の 2 段フォールバック」に従い、URL 未設定・
/// ネットワーク不通・不正レスポンスのいずれでも例外を投げず、ログだけ
/// 残して null を返す。ログ・例外メッセージに内部ホストを出さない
/// （`optional integration` の汎用表現）。
class AppVersionRepository {
  AppVersionRepository({
    String? endpoint,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 8),
  }) : _endpoint =
           endpoint ??
           const String.fromEnvironment(
             'APP_VERSION_ENDPOINT',
             defaultValue: '',
           ),
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  final String _endpoint;
  final http.Client _httpClient;
  final Duration _timeout;

  static const String _logName = 'AppVersionRepository';

  /// 設定されていれば配信エンドポイントの取得を試みる。
  ///
  /// 取得・解析に成功した場合のみ [RemoteVersionManifest] を返す。
  /// それ以外（未設定・通信失敗・JSON 不正など）はすべて null。
  Future<RemoteVersionManifest?> fetch() async {
    if (_endpoint.isEmpty) {
      // 公開クローン等で配信元が無いビルド。機能を no-op にする。
      return null;
    }

    final Uri? uri = Uri.tryParse(_endpoint);
    if (uri == null || !uri.isAbsolute) {
      log(
        'optional integration endpoint is not a valid absolute URL; '
        'skipping update check',
        name: _logName,
      );
      return null;
    }

    final http.Response response;
    try {
      response = await _httpClient
          .get(
            uri,
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_timeout);
    } on Object catch (e) {
      // ネットワーク例外の文字列に URL が含まれることがあるため
      // `$e` を展開せず種別のみ記録する。
      log(
        'optional integration request failed (${e.runtimeType})',
        name: _logName,
      );
      return null;
    }

    if (response.statusCode != 200) {
      log(
        'optional integration returned status ${response.statusCode}',
        name: _logName,
      );
      return null;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      log('optional integration returned malformed JSON', name: _logName);
      return null;
    }
    if (decoded is! Map<String, dynamic>) {
      log('optional integration JSON is not an object', name: _logName);
      return null;
    }

    final SemanticVersion? latest = SemanticVersion.tryParse(
      _asString(decoded['latest']),
    );
    // サポート下限が無い／不正なら 0.0.0（誰も強制ブロックされない安全側）。
    final SemanticVersion minSupported =
        SemanticVersion.tryParse(_asString(decoded['minSupported'])) ??
        const SemanticVersion(0, 0, 0);
    final String? releaseUrl = _asHttpsUrl(decoded['url']);

    return RemoteVersionManifest(
      latest: latest,
      minSupported: minSupported,
      releaseUrl: releaseUrl,
    );
  }

  static String? _asString(Object? value) {
    return value is String ? value : null;
  }

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
