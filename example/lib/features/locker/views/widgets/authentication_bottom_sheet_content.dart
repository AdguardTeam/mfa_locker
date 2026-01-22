import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';

/// Unified authentication bottom sheet content with password + optional biometric.
///
/// This widget does NOT auto-trigger biometric authentication. The parent is responsible
/// for calling [onBiometricPressed] at the appropriate time (e.g., after bottom sheet
/// animation completes). Use [AnimationAwareBottomSheet] to detect animation completion.
class AuthenticationBottomSheetContent extends StatefulWidget {
  final String? title;
  final bool showBiometricButton;
  final FutureOr<void> Function()? onBiometricPressed;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<bool>? onLoadingChanged;
  final ValueChanged<String?>? onErrorMessageChanged;

  const AuthenticationBottomSheetContent({
    super.key,
    this.title,
    required this.showBiometricButton,
    this.onBiometricPressed,
    this.isLoading = false,
    this.errorMessage,
    this.onLoadingChanged,
    this.onErrorMessageChanged,
  });

  @override
  State<AuthenticationBottomSheetContent> createState() => _AuthenticationBottomSheetContentState();
}

class _AuthenticationBottomSheetContentState extends State<AuthenticationBottomSheetContent> {
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outlined, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.title ?? 'Enter your password',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            enabled: !widget.isLoading,
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: _togglePasswordVisibility,
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _onContinuePressed(),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.isLoading || _passwordController.text.trim().isEmpty ? null : _onContinuePressed,
                  child: widget.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ),
              if (widget.showBiometricButton) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  width: 48,
                  child: ElevatedButton(
                    onPressed: widget.isLoading ? null : _onBiometricPressed,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Icon(Icons.fingerprint, size: 24),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.isLoading ? null : _onCancelPressed,
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _isPasswordVisible = !_isPasswordVisible;
    });
  }

  void _onContinuePressed() {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      return;
    }

    context.pop(
      result: AuthenticationResult(password: password),
    );
  }

  Future<void> _onBiometricPressed() async {
    if (widget.onBiometricPressed == null) {
      return;
    }

    widget.onLoadingChanged?.call(true);
    widget.onErrorMessageChanged?.call(null);

    await widget.onBiometricPressed?.call();
  }

  void _onCancelPressed() {
    context.pop(
      result: const AuthenticationResult(cancelled: true),
    );
  }
}
