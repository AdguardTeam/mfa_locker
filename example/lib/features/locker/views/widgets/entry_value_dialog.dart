import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';

class EntryValueDialog extends StatelessWidget {
  final String entryName;
  final String entryValue;

  const EntryValueDialog({
    super.key,
    required this.entryName,
    required this.entryValue,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        const Icon(Icons.vpn_key, color: Colors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            entryName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: 100,
        maxHeight: 400,
        minWidth: 300,
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          entryValue,
          style: const TextStyle(fontSize: 14),
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: context.pop,
        child: const Text('Close'),
      ),
    ],
  );
}
