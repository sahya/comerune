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
  return _DiskPlatformFile(path);
}

/// [PlatformFile] backed by a real file on the local disk.  `file_picker` 12
/// made [PlatformFile] abstract, so tests provide their own concrete subclass.
final class _DiskPlatformFile extends PlatformFile {
  _DiskPlatformFile(this._path);

  final String _path;

  @override
  String get name => _path.split(Platform.pathSeparator).last;

  @override
  Uri get uri => Uri.file(_path);

  /// Screens under test read the file via [path] + `dart:io`, so the
  /// `cross_file` conversion is intentionally unimplemented.
  @override
  Never get xFile => throw UnsupportedError('xFile is not used in tests');

  @override
  Future<int> length() => File(_path).length();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(_path).openRead().map(Uint8List.fromList);
}
