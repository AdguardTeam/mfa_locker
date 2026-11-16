import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locker/locker.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet_content.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_auth_result.dart';
import 'package:mfa_demo/features/locker/views/widgets/biometric_state_known_failure.dart';

/// Requests authentication, trying biometrics before opening the password sheet.
///
/// A successful attempt resolves without opening the sheet and every other outcome opens it for
/// password entry, seeded with the reason biometrics did not complete; a caller that was gone —
/// abandoned attempt, unmounted context — resolves with `null` and no sheet.
Future<AuthenticationResult?> showAuthenticationBottomSheet(
  BuildContext context, {
  String? title,
  required BiometricState biometricState,
  FutureOr<void> Function()? onBiometricPressed,
  required Stream<BiometricAuthResult> biometricResultStream,
}) async {
  final biometricPressed = biometricState.isEnabled ? onBiometricPressed : null;
  final showBiometricButton = biometricPressed != null;
  BiometricAuthResult? initialBiometricResult = biometricState.knownAuthFailure;

  if (biometricPressed != null) {
    final biometricAttempt = _awaitFirstResult(biometricResultStream);
    await biometricPressed();
    initialBiometricResult = await biometricAttempt;

    if (initialBiometricResult == null) {
      return null;
    }

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
      onBiometricPressed: biometricPressed,
      initialBiometricResult: initialBiometricResult,
    ),
  );
}

/// Awaits the first outcome of [biometricResultStream], or `null` when its producer closes
/// before delivering one — which happens when the attempt outlives its caller.
Future<BiometricAuthResult?> _awaitFirstResult(Stream<BiometricAuthResult> biometricResultStream) async {
  final completer = Completer<BiometricAuthResult?>();
  final subscription = biometricResultStream.listen(
    (result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    },
  );

  try {
    return await completer.future;
  } finally {
    await subscription.cancel();
  }
}

/// A generic authentication bottom sheet that handles biometric authentication results.
///
/// It never triggers an attempt itself: only a tap on the fingerprint button starts one.
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

  /// Seeds the sheet's error state: a pre-sheet attempt outcome, or a failure known before one
  /// could start. [BiometricKeyInvalidated] also hides the biometric button.
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

    if (result is BiometricKeyInvalidated) {
      _showBiometricButton = false;
    }

    _errorMessage = switch (result) {
      BiometricSuccess() => _errorMessage,
      BiometricCancelled() => 'Biometric authentication cancelled.',
      BiometricFailed(:final message) || BiometricKeyInvalidated(:final message) => message,
      BiometricNotAvailable() => 'Biometric authentication not available. Please use password.',
    };
  }
}
