import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/views/widgets/confirmation_style.dart';

/// A reusable confirmation dialog for destructive actions.
class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    required this.title,
    required this.content,
    required this.confirmText,
    this.style = ConfirmationStyle.warning,
    super.key,
  });

  final String title;
  final String content;
  final String confirmText;
  final ConfirmationStyle style;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: Icon(Icons.warning_amber_rounded, color: style.iconColor),
    title: Text(title),
    content: Text(content),
    actions: [
      TextButton(
        onPressed: () => context.pop(result: false),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => context.pop(result: true),
        style: TextButton.styleFrom(foregroundColor: style.iconColor),
        child: Text(confirmText),
      ),
    ],
  );
}

/// Shows a confirmation dialog and returns true if confirmed, false otherwise.
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
  ConfirmationStyle style = ConfirmationStyle.warning,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ConfirmationDialog(
      title: title,
      content: content,
      confirmText: confirmText,
      style: style,
    ),
  );

  return result ?? false;
}
