import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../app_logging.dart';

/// Outcome of asking the user for a comment-log save folder.
///
/// `FilePicker.getDirectoryPath()` answers `null` both when the user cancels
/// and (on Android) when the chosen folder has no real filesystem path, so
/// the screen could not tell the two apart. This type keeps them separate.
sealed class CommentLogDirectoryPickResult {
  const CommentLogDirectoryPickResult();
}

/// The user chose a folder that can be opened as a `Directory`.
final class CommentLogDirectoryPicked extends CommentLogDirectoryPickResult {
  const CommentLogDirectoryPicked(this.path);

  final String path;
}

/// The user closed the picker without choosing a folder.
final class CommentLogDirectoryPickCancelled
    extends CommentLogDirectoryPickResult {
  const CommentLogDirectoryPickCancelled();
}

/// The user chose a folder, but it has no filesystem path the auto-save can
/// write to (for example a protected folder such as Downloads on Android).
final class CommentLogDirectoryUnusable extends CommentLogDirectoryPickResult {
  const CommentLogDirectoryUnusable();
}

/// The picker reported an error that is not about the chosen folder.
final class CommentLogDirectoryPickFailed
    extends CommentLogDirectoryPickResult {
  const CommentLogDirectoryPickFailed();
}

/// Method channel served by the Android implementation of `file_picker`.
///
/// The Dart side of that implementation catches the `unknown_path` error and
/// returns `null`, which looks exactly like a cancel. Calling the channel
/// directly lets the error through. The channel name, the `dir` method, its
/// `androidSafOptions` argument and the `unknown_path` code are that plugin's
/// wire protocol, not its public API: re-check them in the plugin's native
/// source when upgrading it (see the table in `AGENTS.md`).
@visibleForTesting
const MethodChannel commentLogDirectoryPickerChannel = MethodChannel(
  'miguelruivo.flutter.plugins.filepicker',
);

const String _logName = 'CommentLogDirectoryPicker';

/// Shows the system folder picker and classifies the result.
///
/// On Android this calls [commentLogDirectoryPickerChannel] itself. If that
/// channel is not there, it falls back to `FilePicker.getDirectoryPath()`,
/// where an unusable folder is again reported as a cancel. That is how this
/// screen behaved before, so the fallback never breaks the flow.
///
/// SAF オプション付きの `androidOptions` を渡さないこと
/// （file_picker 12〜13 の挙動）。渡した場合、戻り値が実ファイル
/// パスではなく content:// URI 文字列に変わり、保存先を
/// `Directory` として直接扱っている自動保存が実行時に壊れる。
/// チャネル直呼びでも同じ理由で `androidSafOptions` は常に null にする。
Future<CommentLogDirectoryPickResult> pickCommentLogDirectory() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final String? path = await commentLogDirectoryPickerChannel
          .invokeMethod<String>('dir', <String, Object?>{
            // Same arguments `FilePicker.getDirectoryPath()` sends when no
            // SAF options are given.
            'androidSafOptions': null,
          });
      return _classifyPath(path);
    } on PlatformException catch (e) {
      if (e.code == 'unknown_path') {
        return const CommentLogDirectoryUnusable();
      }
      appErrorLog(
        name: _logName,
        message: 'Folder picker failed (code: ${e.code})',
        error: e,
      );
      return const CommentLogDirectoryPickFailed();
    } on MissingPluginException catch (e) {
      appErrorLog(
        name: _logName,
        message: 'Folder picker channel unavailable; using the default picker',
        error: e,
      );
    }
  }
  return _classifyPath(await FilePicker.getDirectoryPath());
}

CommentLogDirectoryPickResult _classifyPath(String? path) {
  if (path == null) {
    return const CommentLogDirectoryPickCancelled();
  }
  // A URI cannot be opened as a `Directory`. Today the picker only answers
  // with one when SAF options are sent, which this file never does.
  if (path.startsWith('content://')) {
    return const CommentLogDirectoryUnusable();
  }
  return CommentLogDirectoryPicked(path);
}
