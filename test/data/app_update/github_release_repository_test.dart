import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/data/app_update/github_release_repository.dart';
import 'package:comerune/domain/models/app_update.dart';

// MockClient の http.Response はデフォルト Latin1 エンコードで日本語が
// 通らないため utf8 を明示する。
http.Response _utf8Response(Map<String, Object?> json, [int status = 200]) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(json)),
    status,
    headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('GithubReleaseRepository.fetch', () {
    test('parses tag, body marker, and html_url', () async {
      late http.Request lastRequest;
      final MockClient mock = MockClient((http.Request request) async {
        lastRequest = request;
        return _utf8Response(<String, Object?>{
          'tag_name': 'v1.4.0',
          'html_url': 'https://github.com/sahya/comerune/releases/tag/v1.4.0',
          'body': '## 新機能\n- foo\n\n<!-- min-supported: 1.2.0 -->\n',
          'draft': false,
          'prerelease': false,
        });
      });
      final RemoteVersionManifest? m = await GithubReleaseRepository(
        httpClient: mock,
      ).fetch();
      expect(m, isNotNull);
      expect(m!.latest.toString(), '1.4.0');
      expect(m.minSupported.toString(), '1.2.0');
      expect(
        m.releaseUrl,
        'https://github.com/sahya/comerune/releases/tag/v1.4.0',
      );
      // GitHub API は User-Agent 必須。
      expect(lastRequest.headers['User-Agent'], isNotEmpty);
      expect(lastRequest.url.host, 'api.github.com');
    });

    test('falls back to 0.0.0 when no marker present', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return _utf8Response(<String, Object?>{
          'tag_name': '1.4.0',
          'html_url': 'https://github.com/sahya/comerune/releases/tag/1.4.0',
          'body': '## release notes only, no marker',
        });
      });
      final RemoteVersionManifest? m = await GithubReleaseRepository(
        httpClient: mock,
      ).fetch();
      expect(m, isNotNull);
      expect(m!.latest.toString(), '1.4.0');
      expect(m.minSupported.toString(), '0.0.0');
    });

    test('latest null when tag is unparseable', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return _utf8Response(<String, Object?>{
          'tag_name': 'release-2026-05-30',
        });
      });
      final RemoteVersionManifest? m = await GithubReleaseRepository(
        httpClient: mock,
      ).fetch();
      expect(m, isNotNull);
      expect(m!.latest, isNull);
    });

    test('treats prerelease flag as no latest', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return _utf8Response(<String, Object?>{
          'tag_name': 'v1.9.0',
          'prerelease': true,
          'html_url': 'https://github.com/sahya/comerune/releases/tag/v1.9.0',
          'body': '<!-- min-supported: 1.2.0 -->',
        });
      });
      final RemoteVersionManifest? m = await GithubReleaseRepository(
        httpClient: mock,
      ).fetch();
      expect(m, isNotNull);
      expect(m!.latest, isNull);
    });

    test('rejects non-https html_url', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return _utf8Response(<String, Object?>{
          'tag_name': 'v1.0.0',
          'html_url': 'javascript:alert(1)',
        });
      });
      final RemoteVersionManifest? m = await GithubReleaseRepository(
        httpClient: mock,
      ).fetch();
      expect(m, isNotNull);
      expect(m!.releaseUrl, isNull);
    });

    test('returns null on non-200', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('rate limited', 403);
      });
      expect(await GithubReleaseRepository(httpClient: mock).fetch(), isNull);
    });

    test('returns null on malformed JSON', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('{not json', 200);
      });
      expect(await GithubReleaseRepository(httpClient: mock).fetch(), isNull);
    });

    test('returns null on network error', () async {
      final MockClient mock = MockClient((http.Request request) async {
        throw const _HttpExceptionStub();
      });
      expect(await GithubReleaseRepository(httpClient: mock).fetch(), isNull);
    });
  });
}

class _HttpExceptionStub implements Exception {
  const _HttpExceptionStub();
}
