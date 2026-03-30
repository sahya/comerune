import 'package:flutter/material.dart';

/// Shows a confirmation dialog with cancel and confirm buttons.
///
/// Returns `true` when the user taps the confirm button, `false` when the
/// cancel button is tapped, and `null` when dismissed without a choice.
Future<bool?> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelLabel = 'キャンセル',
  String confirmLabel = '確認',
  Key? confirmButtonKey,
}) async {
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
