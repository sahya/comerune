import 'package:flutter/material.dart';

/// Shows a dialog with a single text input field.
///
/// Returns the trimmed text when the user confirms, or `null` when cancelled.
Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  String? labelText,
  String? hintText,
  String? initialValue,
  String cancelLabel = 'キャンセル',
  String confirmLabel = 'OK',
  Key? textFieldKey,
  Key? confirmButtonKey,
  TextInputType? keyboardType,
  InputDecoration? decoration,
}) async {
  final TextEditingController controller =
      TextEditingController(text: initialValue ?? '');

  try {
    return await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        final InputDecoration effectiveDecoration = decoration ??
            InputDecoration(
              labelText: labelText,
              hintText: hintText,
            );

        return AlertDialog(
          title: Text(title),
          content: TextField(
            key: textFieldKey,
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            decoration: effectiveDecoration,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(cancelLabel),
            ),
            TextButton(
              key: confirmButtonKey,
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
