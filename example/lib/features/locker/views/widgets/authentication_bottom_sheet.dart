import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/animation_aware_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet_content.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';

/// A generic authentication bottom sheet that handles biometric authentication results.
///
/// This widget listens to a [biometricResultStream] to receive biometric authentication
/// outcomes and updates its UI accordingly.
class AuthenticationBottomSheet extends StatefulWidget {
  const AuthenticationBottomSheet({
    super.key,
    this.title,
    required this.showBiometricButton,
    this.onBiometricPressed,
    required this.biometricResultStream,
  });

  final String? title;
  final bool showBiometricButton;
  final FutureOr<void> Function()? onBiometricPressed;
  final Stream<BiometricAuthResult> biometricResultStream;

  @override
  State<AuthenticationBottomSheet> createState() => _AuthenticationBottomSheetState();
}

class _AuthenticationBottomSheetState extends State<AuthenticationBottomSheet> {
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<BiometricAuthResult>? _subscription;

  @override
  void initState() {
    super.initState();
    _isLoading = widget.showBiometricButton;
    _subscription = widget.biometricResultStream.listen(_handleBiometricResult);
  }

  @override
  Widget build(BuildContext context) => AnimationAwareBottomSheet(
    onAnimationComplete: _onAnimationComplete,
    child: AuthenticationBottomSheetContent(
      title: widget.title,
      showBiometricButton: widget.showBiometricButton,
      onBiometricPressed: widget.onBiometricPressed,
      isLoading: _isLoading,
      errorMessage: _errorMessage,
      onLoadingChanged: (isLoading) => setState(() => _isLoading = isLoading),
      onErrorMessageChanged: (errorMessage) => setState(() => _errorMessage = errorMessage),
    ),
  );

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleBiometricResult(BiometricAuthResult result) {
    if (!mounted) {
      return;
    }

    switch (result) {
      case BiometricSuccess():
        context.pop(result: const AuthenticationResult(isBiometricSuccess: true));
      case BiometricCancelled():
        setState(() {
          _isLoading = false;
          _errorMessage = 'Biometric authentication cancelled.';
        });
      case BiometricFailed(:final message):
        setState(() {
          _isLoading = false;
          _errorMessage = message;
        });
      case BiometricNotAvailable():
        setState(() {
          _isLoading = false;
          _errorMessage = 'Biometric authentication not available. Please use password.';
        });
    }
  }

  void _onAnimationComplete() {
    if (widget.showBiometricButton && widget.onBiometricPressed != null) {
      widget.onBiometricPressed!();
    }
  }
}
