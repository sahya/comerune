// Test for the integration discovery library used by the
// `gen_extension_*` scripts.
//
// The scripts run at dev time and operate on the real filesystem; this
// suite uses temporary directories to exercise the validation rules
// without touching the repository's actual `integrations/` folder.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/_extension_discovery.dart';
import '../../scripts/gen_extension_registry.dart';

void main() {
  group('discoverIntegrations', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync('ext-disc-');
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    String makeIntegration(
      String dirName, {
      required String pubspecName,
      bool createPubspec = true,
    }) {
      final Directory dir = Directory('${tempRoot.path}/$dirName');
      dir.createSync(recursive: true);
      if (createPubspec) {
        File('${dir.path}/pubspec.yaml').writeAsStringSync(
          'name: $pubspecName\n'
          'version: 0.1.0\n',
        );
      }
      return dir.path;
    }

    test('returns empty result when integrations directory is missing', () {
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: '${tempRoot.path}/nonexistent',
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('returns empty result for an empty directory', () {
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('discovers a valid integration', () {
      makeIntegration('foo', pubspecName: 'foo');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, hasLength(1));
      expect(result.integrations.first.name, 'foo');
      expect(result.integrations.first.path, '${tempRoot.path}/foo');
      expect(result.warnings, isEmpty);
    });

    test('skips directories without a pubspec silently', () {
      makeIntegration('bar', pubspecName: 'bar', createPubspec: false);
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('warns and skips when pubspec has no name field', () {
      final Directory dir = Directory('${tempRoot.path}/qux')
        ..createSync(recursive: true);
      File('${dir.path}/pubspec.yaml').writeAsStringSync('version: 0.1.0\n');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.first, contains('no `name:` field'));
    });

    test('warns and skips when pubspec name is invalid', () {
      makeIntegration('badname', pubspecName: 'Not-Valid-Name');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.first, contains('not a valid Dart identifier'));
    });

    test('rejects Dart reserved words as package names', () {
      for (final String reserved in <String>[
        'class',
        'void',
        'null',
        'enum',
        'await',
        'final',
      ]) {
        final Directory dir = Directory('${tempRoot.path}/$reserved')
          ..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $reserved\n');
      }
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(
        result.warnings.where((String w) => w.contains('reserved word')),
        hasLength(6),
      );
    });

    test('rejects Dart / Flutter built-in package names', () {
      for (final String name in <String>[
        'dart',
        'package',
        'flutter',
        'flutter_test',
        'meta',
      ]) {
        final Directory dir = Directory('${tempRoot.path}/$name')
          ..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
      }
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(
        result.warnings.where(
          (String w) => w.contains('built-in package prefix'),
        ),
        hasLength(5),
      );
    });

    test('rejects Dart core type names with a discriminating warning', () {
      // Lowercase forms of `dart:core` types whose package alias would
      // shadow the type for the rest of the file. Names already covered
      // by the reserved-word category (`null`, `function`, `set`,
      // `dynamic`) are intentionally NOT in this list.
      const List<String> coreTypes = <String>[
        'int',
        'string',
        'list',
        'map',
        'future',
        'stream',
        'object',
        'bool',
        'double',
        'num',
        'iterable',
        'iterator',
        'symbol',
        'record',
        'type',
        'never',
      ];
      for (final String name in coreTypes) {
        final Directory dir = Directory('${tempRoot.path}/$name')
          ..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
      }
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(
        result.warnings.where((String w) => w.contains('Dart core type name')),
        hasLength(coreTypes.length),
      );
      // Spot-check that the package name appears verbatim in its
      // warning so a fork developer can grep the build log.
      for (final String name in coreTypes) {
        expect(
          result.warnings.any(
            (String w) =>
                w.contains('"$name"') && w.contains('Dart core type name'),
          ),
          isTrue,
          reason: 'expected core-type warning for "$name"',
        );
      }
    });

    test('reserved-word category takes priority over core-type names', () {
      // `null`, `function`, `set` are language reserved words AND are
      // semantically dart:core members. Verify the warning labels them
      // as reserved words, not core types, so the diagnostic stays
      // consistent with the existing reserved-word tests.
      for (final String name in <String>['null', 'function', 'set']) {
        final Directory dir = Directory('${tempRoot.path}/$name')
          ..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
      }
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(
        result.warnings.where((String w) => w.contains('reserved word')),
        hasLength(3),
      );
      expect(
        result.warnings.where((String w) => w.contains('Dart core type name')),
        isEmpty,
      );
    });

    test('warns and skips when directory name does not match pubspec name', () {
      makeIntegration('actual_dir', pubspecName: 'declared_name');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.first, contains('does not'));
      expect(result.warnings.first, contains('match'));
    });

    test('warns and skips when directory name is not a valid identifier', () {
      // Use a directory name with a hyphen — invalid as a Dart identifier
      // and thus rejected before the pubspec is even read.
      makeIntegration('not-valid', pubspecName: 'whatever');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, isEmpty);
      expect(result.warnings, hasLength(1));
      expect(
        result.warnings.first,
        contains('directory name is not a valid Dart identifier'),
      );
    });

    test('handles multiple valid integrations sorted by name', () {
      makeIntegration('zeta', pubspecName: 'zeta');
      makeIntegration('alpha', pubspecName: 'alpha');
      makeIntegration('mu', pubspecName: 'mu');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(
        result.integrations.map((DiscoveredIntegration i) => i.name).toList(),
        <String>['alpha', 'mu', 'zeta'],
      );
      expect(result.warnings, isEmpty);
    });

    test('parses quoted pubspec names', () {
      final Directory dir = Directory('${tempRoot.path}/qpkg')
        ..createSync(recursive: true);
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: "qpkg"\nversion: 0.1.0\n');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, hasLength(1));
      expect(result.integrations.first.name, 'qpkg');
    });

    test('strips inline comments from name field', () {
      final Directory dir = Directory('${tempRoot.path}/cpkg')
        ..createSync(recursive: true);
      File(
        '${dir.path}/pubspec.yaml',
      ).writeAsStringSync('name: cpkg # the package\nversion: 0.1.0\n');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(result.integrations, hasLength(1));
      expect(result.integrations.first.name, 'cpkg');
    });

    test('processes multiple integrations independently when one fails', () {
      makeIntegration('good', pubspecName: 'good');
      makeIntegration('bad_name_dir', pubspecName: 'NotValid');
      makeIntegration('also_good', pubspecName: 'also_good');
      final IntegrationDiscoveryResult result = discoverIntegrations(
        rootPath: tempRoot.path,
      );
      expect(
        result.integrations.map((DiscoveredIntegration i) => i.name).toList(),
        <String>['also_good', 'good'],
      );
      expect(result.warnings, hasLength(1));
    });
  });

  group('renderRegistry', () {
    test('emits an empty const list when no integrations', () {
      final String body = renderRegistry(const <DiscoveredIntegration>[]);
      expect(body, contains('AUTO-GENERATED'));
      expect(body, contains("import '../comerune_extension.dart';"));
      expect(body, contains('const List<ComeruneExtension Function()>'));
      expect(body, contains('<ComeruneExtension Function()>[];'));
      expect(body, isNot(contains('createExtension,')));
    });

    test('emits one import + factory entry per integration', () {
      final String body = renderRegistry(<DiscoveredIntegration>[
        DiscoveredIntegration(name: 'foo', path: 'integrations/foo'),
        DiscoveredIntegration(name: 'bar', path: 'integrations/bar'),
      ]);
      expect(body, contains("import 'package:foo/foo.dart' as foo;"));
      expect(body, contains("import 'package:bar/bar.dart' as bar;"));
      expect(body, contains('foo.createExtension,'));
      expect(body, contains('bar.createExtension,'));
      expect(body, contains('final List<ComeruneExtension Function()>'));
    });
  });
}
