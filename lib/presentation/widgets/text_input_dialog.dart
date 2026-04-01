import 'package:flutter/material.dart';

/// Shows a dialog with a single text input field.
///
/// Returns the trimmed text when the user confirms, or `null` when cancelled.
/// When [clearButtonLabel] is provided and tapped, this returns `''`.
Future<String?> showTextInputDialog({
  required BuildContext context,
  required String title,
  String? labelText,
  String? hintText,
  String? initialValue,
  String cancelLabel = 'キャンセル',
  String? clearButtonLabel,
  String confirmLabel = 'OK',
  Key? textFieldKey,
  Key? clearButtonKey,
  Key? confirmButtonKey,
  TextInputType? keyboardType,
  InputDecoration? decoration,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _TextInputDialog(
        title: title,
        labelText: labelText,
        hintText: hintText,
        initialValue: initialValue,
        cancelLabel: cancelLabel,
        clearButtonLabel: clearButtonLabel,
        confirmLabel: confirmLabel,
        textFieldKey: textFieldKey,
        clearButtonKey: clearButtonKey,
        confirmButtonKey: confirmButtonKey,
        keyboardType: keyboardType,
        decoration: decoration,
      );
    },
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
    this.clearButtonLabel,
    this.labelText,
    this.hintText,
    this.initialValue,
    this.textFieldKey,
    this.clearButtonKey,
    this.confirmButtonKey,
    this.keyboardType,
    this.decoration,
  });

  final String title;
  final String? labelText;
  final String? hintText;
  final String? initialValue;
  final String cancelLabel;
  final String? clearButtonLabel;
  final String confirmLabel;
  final Key? textFieldKey;
  final Key? clearButtonKey;
  final Key? confirmButtonKey;
  final TextInputType? keyboardType;
  final InputDecoration? decoration;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
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
        if (widget.clearButtonLabel != null)
          TextButton(
            key: widget.clearButtonKey,
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(widget.clearButtonLabel!),
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
