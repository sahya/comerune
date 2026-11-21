// Tests for the archive checksum verification in
// `scripts/setup-voicevox-libs.sh`.
//
// The script is sourced in a bash subprocess (sourcing only defines the
// functions; `main` runs when the script is executed directly), so the
// verification can be exercised against temporary files without network
// access. Skipped on hosts without bash (e.g. Windows without a POSIX shell).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _scriptPath = 'scripts/setup-voicevox-libs.sh';

// SHA-256("abc") from FIPS 180-2 Appendix B.1.
const String _abcSha256 =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

bool _hasBash() {
  if (Platform.isWindows) {
    return false;
  }
  try {
    return Process.runSync('bash', <String>['-c', 'true']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Sources the script, then runs [snippet] in the same bash process.
/// Positional arguments are available to [snippet] as `$1`, `$2`, ...
ProcessResult _runWithScript(String snippet, [List<String> args = const []]) {
  return Process.runSync('bash', <String>[
    '-c',
    'source "$_scriptPath"; $snippet',
    'setup-voicevox-libs-test',
    ...args,
  ]);
}

void main() {
  final bool bashAvailable = _hasBash();
  final String? skipReason = bashAvailable ? null : 'bash is not available';

  group('setup-voicevox-libs.sh archive verification', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('voicevox-libs-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File writeArchive(String name, String content) {
      return File('${tempDir.path}/$name')..writeAsStringSync(content);
    }

    test('every archive the script downloads has a pinned SHA-256', () {
      final ProcessResult result = _runWithScript(r'''
for arch in arm64 x86_64; do
  echo "voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}.zip=$(expected_sha256 "voicevox_core-android-${arch}-${VOICEVOX_CORE_VERSION}.zip")"
done
for arch in arm64 x64; do
  echo "voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}.tgz=$(expected_sha256 "voicevox_onnxruntime-android-${arch}-${ONNXRUNTIME_VERSION}.tgz")"
done
''');

      expect(result.exitCode, 0, reason: '${result.stderr}');
      final List<String> lines = (result.stdout as String)
          .split('\n')
          .where((String line) => line.isNotEmpty)
          .toList();
      expect(lines, hasLength(4));
      final RegExp pinned = RegExp(r'=[0-9a-f]{64}$');
      for (final String line in lines) {
        expect(
          pinned.hasMatch(line),
          isTrue,
          reason: 'Archive has no pinned SHA-256: $line',
        );
      }
    }, skip: skipReason);

    test('accepts an archive whose digest matches the pin', () {
      final File archive = writeArchive('asset.zip', 'abc');

      final ProcessResult result = _runWithScript(
        'expected_sha256() { echo "$_abcSha256"; }; verify_archive "\$1"',
        <String>[archive.path],
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout as String, contains('sha256 OK'));
      expect(archive.existsSync(), isTrue);
    }, skip: skipReason);

    test('rejects and deletes an archive whose digest differs', () {
      final File archive = writeArchive(
        'voicevox_core-android-arm64-0.16.2.zip',
        'not the published archive',
      );

      final ProcessResult result = _runWithScript(
        'verify_archive "\$1"',
        <String>[archive.path],
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr as String, contains('一致しません'));
      expect(archive.existsSync(), isFalse);
    }, skip: skipReason);

    test('rejects and deletes an archive without a pinned digest', () {
      final File archive = writeArchive(
        'voicevox_core-android-arm64-9.9.9.zip',
        'abc',
      );

      final ProcessResult result = _runWithScript(
        'verify_archive "\$1"',
        <String>[archive.path],
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr as String, contains('未登録'));
      expect(archive.existsSync(), isFalse);
    }, skip: skipReason);

    test('verifies each archive before extracting it', () {
      final String source = File(_scriptPath).readAsStringSync();
      final int verifyCore = source.indexOf(
        'verify_archive "\$TMP_DIR/\$archive"',
      );
      final int unzip = source.indexOf('unzip -o "\$TMP_DIR/\$archive"');
      final int verifyOnnx = source.indexOf(
        'verify_archive "\$TMP_DIR/\$archive"',
        verifyCore + 1,
      );
      final int untar = source.indexOf('tar xzf "\$TMP_DIR/\$archive"');

      expect(verifyCore, greaterThanOrEqualTo(0));
      expect(unzip, greaterThan(verifyCore));
      expect(verifyOnnx, greaterThan(unzip));
      expect(untar, greaterThan(verifyOnnx));
    });
  });
}
