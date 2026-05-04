// Internal helper shared by `gen_extension_overrides.dart` and
// `gen_extension_registry.dart`.
//
// Discovers integration packages under the top-level `integrations/`
// directory and exposes a small, fully-validated data model so the
// generator scripts only need to worry about output formatting.
//
// Validation guarantees (so generated YAML / Dart cannot be content-
// injected by a malicious or malformed integration):
//
// - The integration directory name must match `^[a-z_][a-z0-9_]*$` and
//   must equal the package name declared in `pubspec.yaml`. This blocks
//   directory names containing newlines, quotes, path separators, or
//   YAML-significant characters.
// - The package name must additionally not be a Dart reserved word or a
//   Dart / Flutter built-in package prefix (`dart`, `package`,
//   `flutter`, `flutter_test`).
// - This file NEVER imports or evaluates integration source code; it
//   only reads `pubspec.yaml` line-by-line.

import 'dart:io';

/// A validated integration discovered under the integrations directory.
class DiscoveredIntegration {
  DiscoveredIntegration({required this.name, required this.path});

  /// The validated package name. Safe to interpolate into YAML/Dart
  /// without escaping (matches the strict identifier pattern).
  final String name;

  /// Path to the integration directory, formed as `<rootPath>/<name>`.
  ///
  /// Whether this is a relative or absolute path mirrors the
  /// `rootPath` argument passed to [discoverIntegrations]: production
  /// callers pass `'integrations'` (relative to the repository root)
  /// and therefore see relative paths; tests may pass an absolute
  /// temp-directory path. The trailing segment is guaranteed to equal
  /// [name] because directory and pubspec names are required to match.
  final String path;
}

/// Result of scanning the integrations directory.
class IntegrationDiscoveryResult {
  IntegrationDiscoveryResult({
    required this.integrations,
    required this.warnings,
  });

  /// Successfully validated integrations, sorted by package name.
  final List<DiscoveredIntegration> integrations;

  /// Human-readable warnings for skipped / rejected entries. Each is a
  /// generic message safe to print to stderr (no internal-only data).
  final List<String> warnings;
}

const String defaultIntegrationsDir = 'integrations';

/// Discover integrations under [rootPath] (defaults to
/// `integrations/`).
///
/// Returns successfully validated entries plus warnings for anything
/// that was skipped. Never throws on validation failures; callers can
/// emit [IntegrationDiscoveryResult.warnings] to stderr if desired.
IntegrationDiscoveryResult discoverIntegrations({
  String rootPath = defaultIntegrationsDir,
}) {
  final Directory root = Directory(rootPath);
  if (!root.existsSync()) {
    return IntegrationDiscoveryResult(
      integrations: const <DiscoveredIntegration>[],
      warnings: const <String>[],
    );
  }

  final List<DiscoveredIntegration> found = <DiscoveredIntegration>[];
  final List<String> warnings = <String>[];
  final List<FileSystemEntity> children = root.listSync()
    ..sort(
      (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
    );

  for (final FileSystemEntity child in children) {
    if (child is! Directory) {
      continue;
    }
    final String dirName = _lastPathSegment(child.path);
    final String childPath = '$rootPath/$dirName';

    if (!_isValidIdentifier(dirName)) {
      warnings.add(
        'skipped $childPath: directory name is not a valid Dart '
        'identifier (must match ^[a-z_][a-z0-9_]*\$).',
      );
      continue;
    }

    final File pubspec = File('${child.path}/pubspec.yaml');
    if (!pubspec.existsSync()) {
      // Quietly skip directories without a pubspec — likely build
      // artefacts or work-in-progress checkouts. Do not warn.
      continue;
    }

    final String? declaredName = _readPackageName(pubspec);
    if (declaredName == null) {
      warnings.add('skipped $childPath: pubspec.yaml has no `name:` field.');
      continue;
    }
    if (!_isValidIdentifier(declaredName)) {
      warnings.add(
        'skipped $childPath: package name "$declaredName" is not '
        'a valid Dart identifier.',
      );
      continue;
    }
    if (_isReservedOrReservedPrefix(declaredName)) {
      warnings.add(
        'skipped $childPath: package name "$declaredName" collides '
        'with a Dart reserved word or built-in package prefix.',
      );
      continue;
    }
    if (declaredName != dirName) {
      warnings.add(
        'skipped $childPath: directory name "$dirName" does not '
        'match pubspec name "$declaredName"; rename one to match.',
      );
      continue;
    }

    found.add(DiscoveredIntegration(name: declaredName, path: childPath));
  }

  found.sort(
    (DiscoveredIntegration a, DiscoveredIntegration b) =>
        a.name.compareTo(b.name),
  );
  return IntegrationDiscoveryResult(integrations: found, warnings: warnings);
}

String _lastPathSegment(String path) {
  // Use the platform separator; Directory.path on Posix is `/`-
  // separated, on Windows it can be backslash-separated.
  final List<String> segments = path
      .split(RegExp(r'[\\/]'))
      .where((String s) => s.isNotEmpty)
      .toList();
  return segments.isEmpty ? '' : segments.last;
}

/// Pub package name pattern. Mirrors pub's own validator.
final RegExp _identifierPattern = RegExp(r'^[a-z_][a-z0-9_]*$');

bool _isValidIdentifier(String name) => _identifierPattern.hasMatch(name);

/// Dart reserved words and built-in identifiers that would cause the
/// generated `import 'package:<name>/...'` or `as <alias>` to fail to
/// compile. Also blocks names that shadow the SDK's own packages.
const Set<String> _reservedOrBuiltinNames = <String>{
  // Dart reserved words.
  'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
  'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
  'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
  'factory', 'false', 'final', 'finally', 'for', 'function', 'get', 'hide',
  'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
  'mixin', 'new', 'null', 'of', 'on', 'operator', 'part', 'rethrow',
  'return', 'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync',
  'this', 'throw', 'true', 'try', 'typedef', 'var', 'void', 'when',
  'while', 'with', 'yield', 'base',
  // SDK / framework package names — not reserved by language but
  // shadowing them would break the generated imports.
  'dart', 'package', 'flutter', 'flutter_test', 'meta',
};

bool _isReservedOrReservedPrefix(String name) =>
    _reservedOrBuiltinNames.contains(name);

/// Parse `name:` from a minimal pubspec.yaml.
///
/// Reads the file line-by-line and returns the first `name:` value
/// encountered, stripped of surrounding quotes and inline comments.
/// Returns `null` if no `name:` line is found or the value is empty.
///
/// This intentionally does NOT use a full YAML parser: pubspec name
/// validation is strict (whitelist), so the parser only needs to handle
/// the canonical pubspec layout. Dependency-only on `dart:io` keeps
/// this script runnable without `pub get`.
String? _readPackageName(File pubspec) {
  final List<String> lines = pubspec.readAsLinesSync();
  for (final String line in lines) {
    final String trimmed = line.trimLeft();
    if (!trimmed.startsWith('name:')) {
      continue;
    }
    String value = trimmed.substring('name:'.length).trim();
    final int hashIndex = value.indexOf('#');
    if (hashIndex >= 0) {
      value = value.substring(0, hashIndex).trim();
    }
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") &&
        value.endsWith("'") &&
        value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) {
      return null;
    }
    return value;
  }
  return null;
}
