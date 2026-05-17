import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/data/app_update/app_version_repository.dart';
import 'package:comerune/domain/models/app_update.dart';

const String _endpoint = 'https://updates.invalid/api/app-version';

void main() {
  group('AppVersionRepository.fetch', () {
    test('returns null when endpoint is not configured', () async {
      final AppVersionRepository repo = AppVersionRepository(endpoint: '');
      expect(await repo.fetch(), isNull);
    });

    test('parses a valid 200 JSON manifest', () async {
      final MockClient mock = MockClient((http.Request request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), _endpoint);
        return http.Response(
          jsonEncode(<String, Object?>{
            'latest': '1.4.0',
            'minSupported': '1.2.0',
            'url': 'https://example.invalid/releases/latest',
          }),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );

      final RemoteVersionManifest? m = await repo.fetch();
      expect(m, isNotNull);
      expect(m!.latest.toString(), '1.4.0');
      expect(m.minSupported.toString(), '1.2.0');
      expect(m.releaseUrl, 'https://example.invalid/releases/latest');
    });

    test('latest null and minSupported defaults when fields missing', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response(jsonEncode(<String, Object?>{}), 200);
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );

      final RemoteVersionManifest? m = await repo.fetch();
      expect(m, isNotNull);
      expect(m!.latest, isNull);
      expect(m.minSupported.toString(), '0.0.0');
      expect(m.releaseUrl, isNull);
    });

    test('rejects non-https release url', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'latest': '1.0.0',
            'url': 'javascript:alert(1)',
          }),
          200,
        );
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );

      final RemoteVersionManifest? m = await repo.fetch();
      expect(m, isNotNull);
      expect(m!.releaseUrl, isNull);
    });

    test('returns null on non-200', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('nope', 503);
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );
      expect(await repo.fetch(), isNull);
    });

    test('returns null on malformed JSON', () async {
      final MockClient mock = MockClient((http.Request request) async {
        return http.Response('{not json', 200);
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );
      expect(await repo.fetch(), isNull);
    });

    test('returns null on network error', () async {
      final MockClient mock = MockClient((http.Request request) async {
        throw const HttpExceptionStub();
      });
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: _endpoint,
        httpClient: mock,
      );
      expect(await repo.fetch(), isNull);
    });

    test('returns null when endpoint is not an absolute URL', () async {
      final AppVersionRepository repo = AppVersionRepository(
        endpoint: '/relative/path',
      );
      expect(await repo.fetch(), isNull);
    });
  });
}

class HttpExceptionStub implements Exception {
  const HttpExceptionStub();
}
