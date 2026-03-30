import 'package:flutter/material.dart';

/// A centered message displayed when a list or section has no content.
class EmptyStateMessage extends StatelessWidget {
  const EmptyStateMessage({
    super.key,
    required this.message,
    this.textAlign,
  });

  final String message;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(fontSize: 14),
          textAlign: textAlign,
        ),
      ),
    );
  }
}
