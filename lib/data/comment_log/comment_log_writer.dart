import 'dart:io';

import '../../domain/models/app_message.dart';

/// Writes comment logs to a text file in the specified directory.
abstract class CommentLogWriter {
  /// Saves the given messages as a comment log file in the app's local
  /// directory.
  ///
  /// Returns the path to the saved file, or null if saving failed.
  Future<String?> save({
    required String lv,
    required List<AppMessage> messages,
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
  })  : _directory = directory,
        _tempDirectory = tempDirectory;

  final Directory _directory;
  final Directory _tempDirectory;

  @override
  Future<String?> save({
    required String lv,
    required List<AppMessage> messages,
  }) async {
    return _writeFile(
      directory: _directory,
      lv: lv,
      messages: messages,
    );
  }

  @override
  Future<String?> writeToTempFile({
    required String lv,
    required List<AppMessage> messages,
  }) async {
    return _writeFile(
      directory: _tempDirectory,
      lv: lv,
      messages: messages,
    );
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
      final String fileName = '${lv}_$timestamp.txt';
      final File file = File('${directory.path}/$fileName');

      final StringBuffer buffer = StringBuffer();
      for (final AppMessage message in messages) {
        if (!_shouldInclude(message)) {
          continue;
        }
        final String time = _formatHms(message.timestamp);
        final String user = message.userId ?? '';
        final String escapedContent =
            message.content.replaceAll('\t', ' ').replaceAll('\n', ' ');
        buffer.writeln('$time\t$user\t$escapedContent');
      }

      await file.writeAsString(buffer.toString());
      return file.path;
    } on Object {
      return null;
    }
  }

  bool _shouldInclude(AppMessage message) {
    switch (message.type) {
      case AppMessageType.chat:
      case AppMessageType.operator:
      case AppMessageType.notification:
        return true;
      case AppMessageType.gift:
      case AppMessageType.nicoad:
        return false;
    }
  }

  String _formatFileTimestamp(DateTime value) {
    final String y = value.year.toString();
    final String mo = value.month.toString().padLeft(2, '0');
    final String d = value.day.toString().padLeft(2, '0');
    final String h = value.hour.toString().padLeft(2, '0');
    final String mi = value.minute.toString().padLeft(2, '0');
    final String s = value.second.toString().padLeft(2, '0');
    return '${y}${mo}${d}_$h$mi$s';
  }

  String _formatHms(DateTime value) {
    final DateTime local = value.toLocal();
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    final String ss = local.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}
