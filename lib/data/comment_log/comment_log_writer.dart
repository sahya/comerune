import 'dart:io';

import '../../domain/models/app_message.dart';

/// Writes comment logs to a text file in the specified directory.
///
/// Callers are responsible for filtering messages before passing them in
/// (e.g. excluding gift / nicoad types).
///
/// **File format (Issue #784):**
/// Each row is `commentNo<TAB>HH:MM:SS<TAB>userId<TAB>content` (4
/// tab-separated columns). The `commentNo` column is the empty string for
/// messages that do not carry a number (operator / system / gift /
/// nicoad / forwarded chat / Legacy WebSocket comments). The column
/// count is fixed at 4 even when no message in the file carries a
/// number, so downstream TSV parsers can rely on a stable schema.
///
/// **Intended consumers**: a typical user opens these files in Excel,
/// LibreOffice Calc, pandas (`pd.read_csv(sep='\t')`), or a custom
/// per-broadcast analysis script. None of these tools tolerate a
/// per-row variable column count, which is why the empty string
/// fallback in the first column matters.
///
/// **Backwards compatibility**: the previous format was 3 columns
/// (`HH:MM:SS<TAB>userId<TAB>content`). The 3 → 4 column move is a
/// **breaking change** for any tool that hard-codes the 3-column shape;
/// users with existing analysis scripts must shift column indices by 1
/// (or drop column 0). comerune itself does not currently read these
/// files back, so no in-app reader needs updating.
///
/// **Future-extension policy**: any further column addition (e.g. a
/// future `roomPosition` or `forwardedFromLiveId`) MUST extend the row
/// to the right (5+ columns) so existing 4-column parsers degrade
/// gracefully. Do NOT reorder existing columns. If a non-additive
/// schema change becomes necessary, prefer (a) a new file extension
/// (e.g. `.tsv2`), (b) a versioned header line (e.g. `# format: v3`),
/// or (c) a separate writer class — never silently break the layout
/// again.
abstract class CommentLogWriter {
  /// Saves the given messages as a comment log file.
  ///
  /// When [customDirectory] is provided, saves to that directory instead of
  /// the default app-local directory.
  /// Returns the path to the saved file, or null if saving failed.
  Future<String?> save({
    required String lv,
    required List<AppMessage> messages,
    Directory? customDirectory,
  });

  /// Writes a comment log to a temporary file and returns its path.
  ///
  /// Intended for use with the system share sheet so the user can choose
  /// an external destination (Google Drive, etc.).  Returns null if writing
  /// failed.
  Future<String?> writeToTempFile({
    required String lv,
    required List<AppMessage> messages,
  });
}

class FileCommentLogWriter implements CommentLogWriter {
  const FileCommentLogWriter({
    required Directory directory,
    required Directory tempDirectory,
  }) : _directory = directory,
       _tempDirectory = tempDirectory;

  final Directory _directory;
  final Directory _tempDirectory;

  @override
  Future<String?> save({
    required String lv,
    required List<AppMessage> messages,
    Directory? customDirectory,
  }) async {
    return _writeFile(
      directory: customDirectory ?? _directory,
      lv: lv,
      messages: messages,
    );
  }

  @override
  Future<String?> writeToTempFile({
    required String lv,
    required List<AppMessage> messages,
  }) async {
    return _writeFile(directory: _tempDirectory, lv: lv, messages: messages);
  }

  Future<String?> _writeFile({
    required Directory directory,
    required String lv,
    required List<AppMessage> messages,
  }) async {
    if (messages.isEmpty) {
      return null;
    }

    try {
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final DateTime now = DateTime.now();
      final String timestamp = _formatFileTimestamp(now);
      final String sanitizedLv = lv.replaceAll(RegExp(r'[/\\. ]'), '_');
      final String fileName = '${sanitizedLv}_$timestamp.txt';
      final File file = File('${directory.path}/$fileName');

      final StringBuffer buffer = StringBuffer();
      for (final AppMessage message in messages) {
        final String time = _formatHms(message.timestamp);
        final String user = message.userId ?? '';
        final String escapedContent = message.content
            .replaceAll('\t', ' ')
            .replaceAll('\n', ' ');
        // Issue #784. 4-column TSV: `commentNo<TAB>HH:MM:SS<TAB>userId<TAB>content`.
        // commentNo is the empty string for messages that do not carry a
        // number (operator / system / gift / nicoad / forwarded chat /
        // Legacy WebSocket comments). The column count is fixed regardless
        // of the per-user `showCommentNo` UI toggle so external parsers
        // can rely on a stable schema. See class doc for the format
        // contract and future-extension policy.
        final String commentNoColumn = message.commentNo?.toString() ?? '';
        buffer.writeln('$commentNoColumn\t$time\t$user\t$escapedContent');
      }

      await file.writeAsString(buffer.toString());
      return file.path;
    } on Object {
      return null;
    }
  }

  String _formatFileTimestamp(DateTime value) {
    final String y = value.year.toString();
    final String mo = value.month.toString().padLeft(2, '0');
    final String d = value.day.toString().padLeft(2, '0');
    final String h = value.hour.toString().padLeft(2, '0');
    final String mi = value.minute.toString().padLeft(2, '0');
    final String s = value.second.toString().padLeft(2, '0');
    return '$y$mo${d}_$h$mi$s';
  }

  String _formatHms(DateTime value) {
    final DateTime local = value.toLocal();
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    final String ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
