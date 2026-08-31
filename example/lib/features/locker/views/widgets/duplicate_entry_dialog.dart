import 'package:flutter/material.dart';

import 'package:mfa_demo/features/locker/data/models/duplicate_entry_result.dart';

/// Prompts for a new name when duplicating the entry identified by the tapped
/// row, letting the caller compare two ways to authenticate: two separate
/// biometric checks (read + write) or one check via a single transaction.
class DuplicateEntryDialog extends StatefulWidget {
  const DuplicateEntryDialog({required this.sourceName, super.key});

  final String sourceName;

  @override
  State<DuplicateEntryDialog> createState() => _DuplicateEntryDialogState();
}

class _DuplicateEntryDialogState extends State<DuplicateEntryDialog> {
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Duplicate entry'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source: ${widget.sourceName}'),
        const SizedBox(height: 8),
        const Text(
          'Demo: duplicating normally needs two biometric checks (read + write). '
          'With a transaction, both operations run under one check.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => _submit(context, useTransaction: false),
        child: const Text('Copy (standard: 2 checks)'),
      ),
      FilledButton(
        onPressed: () => _submit(context, useTransaction: true),
        child: const Text('Copy via transaction (1 check)'),
      ),
    ],
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, {required bool useTransaction}) {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      DuplicateEntryResult(
        newName: newName,
        useTransaction: useTransaction,
      ),
    );
  }
}
