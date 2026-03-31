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
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _TextInputAlertDialog(
        title: title,
        labelText: labelText,
        hintText: hintText,
        initialValue: initialValue,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        textFieldKey: textFieldKey,
        confirmButtonKey: confirmButtonKey,
        keyboardType: keyboardType,
        decoration: decoration,
      );
    },
  );
}

/// Internal [StatefulWidget] that owns the [TextEditingController] lifecycle.
class _TextInputAlertDialog extends StatefulWidget {
  const _TextInputAlertDialog({
    required this.title,
    this.labelText,
    this.hintText,
    this.initialValue,
    required this.cancelLabel,
    required this.confirmLabel,
    this.textFieldKey,
    this.confirmButtonKey,
    this.keyboardType,
    this.decoration,
  });

  final String title;
  final String? labelText;
  final String? hintText;
  final String? initialValue;
  final String cancelLabel;
  final String confirmLabel;
  final Key? textFieldKey;
  final Key? confirmButtonKey;
  final TextInputType? keyboardType;
  final InputDecoration? decoration;

  @override
  State<_TextInputAlertDialog> createState() => _TextInputAlertDialogState();
}

class _TextInputAlertDialogState extends State<_TextInputAlertDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration effectiveDecoration = widget.decoration ??
        InputDecoration(
          labelText: widget.labelText,
          hintText: widget.hintText,
        );

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.textFieldKey,
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: effectiveDecoration,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          key: widget.confirmButtonKey,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
