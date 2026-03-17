class BiometricException implements Exception {
  final BiometricExceptionType type;
  final Object? originalError;

  const BiometricException(
    this.type, {
    this.originalError,
  });

  @override
  String toString() => 'BiometricException(type: $type)';
}

enum BiometricExceptionType {
  /// The user cancelled the biometric authentication prompt.
  cancel,

  /// Biometric authentication failed (wrong fingerprint, lockout, or a generic decryption error).
  failure,

  /// Hardware-backed biometric key permanently invalidated due to a biometric enrollment change.
  keyInvalidated,

  /// The biometric key for the given tag does not exist in the secure hardware.
  keyNotFound,

  /// A biometric key with the given tag already exists in the secure hardware.
  keyAlreadyExists,

  /// Biometric authentication is not available on this device (hardware missing or not enrolled).
  notAvailable,

  /// The biometric cipher has not been configured (e.g. missing title or key tag).
  notConfigured,
}
