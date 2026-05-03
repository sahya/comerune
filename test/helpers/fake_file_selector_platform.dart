import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

/// Test double for [FileSelectorPlatform]. Returns a preconfigured [XFile]
/// or directory path (or null to simulate user cancellation). Can be
/// configured to throw.
class FakeFileSelectorPlatform extends FileSelectorPlatform {
  FakeFileSelectorPlatform();

  /// File returned from [openFile]. Defaults to null (user cancelled).
  XFile? fileToReturn;

  /// Directory returned from [getDirectoryPath]. Defaults to null.
  String? directoryToReturn;

  /// When non-null, [openFile] / [getDirectoryPath] throw this error.
  Object? errorToThrow;

  /// Delay inserted before returning, to simulate slow platform ops during
  /// widget tests (e.g. disabled-button visualisation).
  Duration responseDelay = Duration.zero;

  final List<Map<String, Object?>> pickCalls = <Map<String, Object?>>[];

  void reset() {
    fileToReturn = null;
    directoryToReturn = null;
    errorToThrow = null;
    responseDelay = Duration.zero;
    pickCalls.clear();
  }

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    pickCalls.add(<String, Object?>{
      'op': 'openFile',
      'extensions': acceptedTypeGroups
          ?.expand((XTypeGroup g) => g.extensions ?? const <String>[])
          .toList(),
    });
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return fileToReturn;
  }

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    pickCalls.add(<String, Object?>{'op': 'getDirectoryPath'});
    if (responseDelay > Duration.zero) {
      await Future<void>.delayed(responseDelay);
    }
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return directoryToReturn;
  }
}

/// Convenience to build an [XFile] pointing at a real path on disk
/// (so the screen can read it via `File(path)`).
XFile buildSingleFileResult({required String path}) {
  return XFile(path, mimeType: 'application/json');
}
