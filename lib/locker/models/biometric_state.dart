/// Granular biometric authentication state based on TPM and hardware availability
enum BiometricState {
  /// TPM not supported on this device
  tpmUnsupported,

  /// TPM version is incompatible or unsupported
  tpmVersionIncompatible,

  /// Biometric hardware unavailable (unsupported, not present, or busy)
  hardwareUnavailable,

  /// User hasn't enrolled biometric (fingerprint/face) in device settings
  notEnrolled,

  /// Biometric authentication disabled by administrator or policy
  disabledByPolicy,

  /// Android security patch required for biometric authentication
  securityUpdateRequired,

  /// Biometric available but not enabled in app
  availableButDisabled,

  /// Biometric enabled and ready to use
  enabled;

  /// Whether biometric is available for use (not an error state)
  bool get isAvailable => this == availableButDisabled || this == enabled;

  /// Whether biometric is currently enabled
  bool get isEnabled => this == enabled;
}
