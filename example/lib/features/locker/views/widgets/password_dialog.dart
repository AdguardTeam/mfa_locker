import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';

/// Dialog for entering password
class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Enter Password'),
    content: TextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
      ),
      autofocus: true,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => context.pop(),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _submit,
        child: const Text('OK'),
      ),
    ],
  );

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (password.isNotEmpty) {
      context.pop(result: password);
    }
  }
}
