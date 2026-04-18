import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';

/// Test double for `FilePickerPlatform`.  Returns a preconfigured
/// [FilePickerResult] (or null to simulate user cancellation).  Can be
/// configured to throw.
class FakeFilePickerPlatform extends FilePickerPlatform {
  FakeFilePickerPlatform();

  /// Result returned from [pickFiles].  Defaults to null (user cancelled).
  FilePickerResult? resultToReturn;

  /// When non-null, `pickFiles` throws this error.
  Object? errorToThrow;

  /// Delay inserted before `pickFiles` returns, to simulate slow platform ops
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
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    pickCalls.add(<String, Object?>{
      'type': type,
      'allowedExtensions': allowedExtensions,
      'allowMultiple': allowMultiple,
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

/// Convenience to build a [FilePickerResult] whose single file points at a
/// real path on disk (so the screen can read it via `File(path)`).
FilePickerResult buildSingleFileResult({required String path}) {
  final String name = path.split(Platform.pathSeparator).last;
  return FilePickerResult(<PlatformFile>[
    PlatformFile(
      path: path,
      name: name,
      size: 0,
      bytes: Uint8List(0),
      readStream: null,
    ),
  ]);
}
