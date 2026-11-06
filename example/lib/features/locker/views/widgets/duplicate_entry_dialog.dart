import 'package:flutter/material.dart';
import 'package:mfa_demo/features/locker/data/models/duplicate_entry_auth_method.dart';
import 'package:mfa_demo/features/locker/data/models/duplicate_entry_result.dart';

/// Prompts for a new name and how to authenticate, then reports whether the
/// duplication runs in one transaction or in two separate authentications.
class DuplicateEntryDialog extends StatefulWidget {
  const DuplicateEntryDialog({
    required this.sourceName,
    required this.biometricAvailable,
    super.key,
  });

  final String sourceName;

  /// Whether biometric authentication can actually be used right now — the
  /// plugin is present and the user has enabled it.
  final bool biometricAvailable;

  @override
  State<DuplicateEntryDialog> createState() => _DuplicateEntryDialogState();
}

class _DuplicateEntryDialogState extends State<DuplicateEntryDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();

  late DuplicateEntryAuthMethod _authMethod = widget.biometricAvailable
      ? DuplicateEntryAuthMethod.biometric
      : DuplicateEntryAuthMethod.password;

  bool get _usesPassword => _authMethod == DuplicateEntryAuthMethod.password;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Duplicate entry'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Source: ${widget.sourceName}'),
        const SizedBox(height: 12),
        SegmentedButton<DuplicateEntryAuthMethod>(
          segments: [
            if (widget.biometricAvailable)
              const ButtonSegment(
                value: DuplicateEntryAuthMethod.biometric,
                label: Text('Biometrics'),
              ),
            const ButtonSegment(
              value: DuplicateEntryAuthMethod.password,
              label: Text('Password'),
            ),
          ],
          selected: {_authMethod},
          onSelectionChanged: (selection) => setState(() => _authMethod = selection.first),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New name'),
        ),
        if (_usesPassword) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _usesPassword
              ? 'Demo: duplicating normally derives the key twice (read + write). '
                  'With a transaction, both operations run under one derivation.'
              : 'Demo: duplicating normally needs two biometric checks (read + write). '
                  'With a transaction, both operations run under one check.',
          style: const TextStyle(fontSize: 13),
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
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, {required bool useTransaction}) {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      return;
    }

    final password = _passwordController.text;
    if (_usesPassword && password.isEmpty) {
      return;
    }

    Navigator.of(context).pop(
      DuplicateEntryResult(
        newName: newName,
        useTransaction: useTransaction,
        authMethod: _authMethod,
        password: _usesPassword ? password : null,
      ),
    );
  }
}
