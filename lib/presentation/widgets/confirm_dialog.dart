import 'package:flutter/material.dart';

/// Shows a confirmation dialog with [title] and [content].
///
/// Returns `true` if the user confirmed, `false` or `null` otherwise.
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelLabel = 'キャンセル',
  String confirmLabel = '確認',
  Key? confirmButtonKey,
}) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            key: confirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
