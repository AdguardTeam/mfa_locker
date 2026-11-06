import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet_content.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';

/// Requests authentication, trying biometrics before opening the password sheet.
///
/// When biometrics are available ([showBiometricButton] is `true` and
/// [onBiometricPressed] is provided), the attempt starts before any sheet is shown.
/// A successful attempt resolves with [AuthenticationResult.isBiometricSuccess] and
/// never opens [AuthenticationBottomSheet]; every other outcome — cancelled, failed,
/// invalidated key or unavailable — opens the sheet for password entry, seeded with
/// that outcome so the user sees why biometrics did not complete.
Future<AuthenticationResult?> showAuthenticationBottomSheet(
  BuildContext context, {
  String? title,
  required bool showBiometricButton,
  FutureOr<void> Function()? onBiometricPressed,
  required Stream<BiometricAuthResult> biometricResultStream,
}) async {
  BiometricAuthResult? initialBiometricResult;

  if (showBiometricButton && onBiometricPressed != null) {
    // Subscribe before triggering so a fast result cannot slip past the attempt.
    final biometricAttempt = biometricResultStream.first;
    await onBiometricPressed();
    initialBiometricResult = await biometricAttempt;

    if (initialBiometricResult is BiometricSuccess) {
      return const AuthenticationResult(isBiometricSuccess: true);
    }
  }

  if (!context.mounted) {
    return null;
  }

  return showModalBottomSheet<AuthenticationResult?>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => AuthenticationBottomSheet(
      title: title,
      showBiometricButton: showBiometricButton,
      biometricResultStream: biometricResultStream,
      onBiometricPressed: onBiometricPressed,
      initialBiometricResult: initialBiometricResult,
    ),
  );
}

/// A generic authentication bottom sheet that handles biometric authentication results.
///
/// This widget listens to a [biometricResultStream] to receive biometric authentication
/// outcomes and updates its UI accordingly. It never triggers biometric authentication on
/// its own: the sheet opens for password entry, and only the user tapping the fingerprint
/// button starts an attempt.
class AuthenticationBottomSheet extends StatefulWidget {
  const AuthenticationBottomSheet({
    super.key,
    this.title,
    required this.showBiometricButton,
    this.onBiometricPressed,
    required this.biometricResultStream,
    this.initialBiometricResult,
  });

  final String? title;
  final bool showBiometricButton;
  final FutureOr<void> Function()? onBiometricPressed;
  final Stream<BiometricAuthResult> biometricResultStream;

  /// Outcome of a biometric attempt made before the sheet opened, if any.
  ///
  /// It seeds the sheet's error state so the user knows why biometrics fell through;
  /// [BiometricKeyInvalidated] also hides the biometric button.
  final BiometricAuthResult? initialBiometricResult;

  @override
  State<AuthenticationBottomSheet> createState() => _AuthenticationBottomSheetState();
}

class _AuthenticationBottomSheetState extends State<AuthenticationBottomSheet> {
  bool _isLoading = false;
  late bool _showBiometricButton = widget.showBiometricButton;
  String? _errorMessage;
  StreamSubscription<BiometricAuthResult>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.biometricResultStream.listen(_handleBiometricResult);

    final initialBiometricResult = widget.initialBiometricResult;
    if (initialBiometricResult != null) {
      _applyFailureState(initialBiometricResult);
    }
  }

  @override
  Widget build(BuildContext context) => AuthenticationBottomSheetContent(
    title: widget.title,
    showBiometricButton: _showBiometricButton,
    onBiometricPressed: widget.onBiometricPressed,
    isLoading: _isLoading,
    errorMessage: _errorMessage,
    onLoadingChanged: (isLoading) => setState(() => _isLoading = isLoading),
    onErrorMessageChanged: (errorMessage) => setState(() => _errorMessage = errorMessage),
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

    if (result is BiometricSuccess) {
      context.pop(result: const AuthenticationResult(isBiometricSuccess: true));

      return;
    }

    setState(() => _applyFailureState(result));
  }

  void _applyFailureState(BiometricAuthResult result) {
    _isLoading = false;

    switch (result) {
      case BiometricSuccess():
        break;
      case BiometricCancelled():
        _errorMessage = 'Biometric authentication cancelled.';
      case BiometricFailed(:final message):
        _errorMessage = message;
      case BiometricKeyInvalidated(:final message):
        _showBiometricButton = false;
        _errorMessage = message;
      case BiometricNotAvailable():
        _errorMessage = 'Biometric authentication not available. Please use password.';
    }
  }
}
