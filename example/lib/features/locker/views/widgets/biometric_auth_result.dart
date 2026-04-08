/// Biometric authentication result types used by [AuthenticationBottomSheet].
sealed class BiometricAuthResult {
  const BiometricAuthResult();
}

/// Biometric authentication succeeded.
class BiometricSuccess extends BiometricAuthResult {
  const BiometricSuccess();
}

/// Biometric authentication was cancelled by the user.
class BiometricCancelled extends BiometricAuthResult {
  const BiometricCancelled();
}

/// Biometric authentication failed with a message.
class BiometricFailed extends BiometricAuthResult {
  final String message;

  const BiometricFailed(this.message);
}

/// Biometric key was invalidated (e.g., biometric enrollment changed).
class BiometricKeyInvalidated extends BiometricAuthResult {
  final String message;

  const BiometricKeyInvalidated(this.message);
}

/// Biometric authentication is not available on this device.
class BiometricNotAvailable extends BiometricAuthResult {
  const BiometricNotAvailable();
}
