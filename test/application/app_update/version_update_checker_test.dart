import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:comerune/application/app_update/version_update_checker.dart';
import 'package:comerune/data/app_update/app_version_repository.dart';
import 'package:comerune/domain/models/app_update.dart';

const String _endpoint = 'https://updates.invalid/api/app-version';

AppVersionRepository _repoReturning(Map<String, Object?> body) {
  final MockClient mock = MockClient((http.Request request) async {
    return http.Response(jsonEncode(body), 200);
  });
  return AppVersionRepository(endpoint: _endpoint, httpClient: mock);
}

AppVersionRepository _repoFailing() {
  final MockClient mock = MockClient((http.Request request) async {
    return http.Response('err', 500);
  });
  return AppVersionRepository(endpoint: _endpoint, httpClient: mock);
}

void main() {
  group('VersionUpdateChecker.check', () {
    test('returns unavailable on unsupported platform', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{'latest': '9.9.9'}),
        isSupportedPlatform: false,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.couldCheck, isFalse);
      expect(r.status.isNone, isTrue);
    });

    test('returns unavailable when current version is unparseable', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{'latest': '9.9.9'}),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('not-a-version');
      expect(r.couldCheck, isFalse);
      expect(r.status.isNone, isTrue);
    });

    test('returns unavailable (fail-open) when fetch fails', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoFailing(),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.couldCheck, isFalse);
      expect(r.status.isForced, isFalse);
    });

    test('forced when current is below minSupported', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{
          'latest': '2.0.0',
          'minSupported': '1.5.0',
          'url': 'https://example.invalid/r',
        }),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.couldCheck, isTrue);
      expect(r.status.isForced, isTrue);
      expect(r.status.latestVersion.toString(), '2.0.0');
      expect(r.status.releaseUrl, 'https://example.invalid/r');
    });

    test('optional when newer release exists but above minSupported', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{
          'latest': '2.0.0',
          'minSupported': '1.0.0',
        }),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.couldCheck, isTrue);
      expect(r.status.isOptional, isTrue);
      expect(r.status.latestVersion.toString(), '2.0.0');
    });

    test('none when already on the latest version', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{
          'latest': '1.0.0',
          'minSupported': '1.0.0',
        }),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.couldCheck, isTrue);
      expect(r.status.isNone, isTrue);
    });

    test('forced takes precedence even if latest is unknown', () async {
      final VersionUpdateChecker checker = VersionUpdateChecker(
        repository: _repoReturning(<String, Object?>{
          'minSupported': '1.5.0',
          'url': 'https://example.invalid/r',
        }),
        isSupportedPlatform: true,
      );
      final UpdateCheckResult r = await checker.check('1.0.0');
      expect(r.status.isForced, isTrue);
      expect(r.status.latestVersion, isNull);
      expect(r.status.releaseUrl, 'https://example.invalid/r');
    });
  });
}
