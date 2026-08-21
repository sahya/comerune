import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Test double for `FilePickerPlatform`.  Returns a preconfigured
/// [PlatformFile] (or null to simulate user cancellation).  Can be
/// configured to throw.
class FakeFilePickerPlatform extends FilePickerPlatform {
  FakeFilePickerPlatform();

  /// Result returned from [pickFile].  Defaults to null (user cancelled).
  PlatformFile? resultToReturn;

  /// When non-null, `pickFile` throws this error.
  Object? errorToThrow;

  /// Delay inserted before `pickFile` returns, to simulate slow platform ops
  /// during widget tests (e.g. disabled-button visualisation).
  Duration responseDelay = Duration.zero;

  final List<Map<String, Object?>> pickCalls = <Map<String, Object?>>[];

  void reset() {
    resultToReturn = null;
    errorToThrow = null;
    responseDelay = Duration.zero;
    pickCalls.clear();
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickCalls.add(<String, Object?>{
      'type': type,
      'allowedExtensions': allowedExtensions,
    });
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn;
  }
}

/// Convenience to build a [PlatformFile] that points at a real path on disk
/// (so the screen can read it via `File(path)`).
PlatformFile buildDiskPlatformFile({required String path}) {
  return _FakePlatformFile(Uri.file(path));
}

/// Convenience to build a [PlatformFile] whose URI is not a `file:` URI.
///
/// `file_picker` 12 derives [PlatformFile.path] from the URI, so this is the
/// shape a pick takes when it has no local filesystem path and `path` is null.
PlatformFile buildPathlessPlatformFile({
  String uri = 'content://com.example.provider/document/1',
}) {
  return _FakePlatformFile(Uri.parse(uri));
}

/// [PlatformFile] built from a bare [Uri].  `file_picker` 12 made
/// [PlatformFile] abstract, so tests provide their own concrete subclass;
/// `path` comes for free from the inherited getter that reads [uri].
final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile(this.uri);

  @override
  final Uri uri;

  @override
  String get name => uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;

  /// Screens under test read the file via [path] + `dart:io`, so the
  /// `cross_file` conversion is intentionally unimplemented.
  @override
  Never get xFile => throw UnsupportedError('xFile is not used in tests');

  /// Throws for a non-`file:` URI, which is correct: a screen that reached a
  /// read on a pathless pick would be skipping its own null-path guard.
  File get _file => File(uri.toFilePath());

  @override
  Future<int> length() => _file.length();

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      _file.openRead().map(Uint8List.fromList);
}
