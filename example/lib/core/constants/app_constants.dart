class AppConstants {
  /// Name of the storage file
  static const storageFileName = 'mfa_demo_storage.json';

  /// Default duration before auto-lock activates (fallback for legacy usage).
  static const lockTimeoutDuration = Duration(minutes: 5);

  /// Sentinel duration used when auto-lock should remain disabled.
  static const lockTimeoutDisabledDuration = Duration(days: 3650);

  /// Allowed timeout choices surfaced in settings.
  static const lockTimeoutOptions = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    lockTimeoutDisabledDuration,
  ];

  /// Key tag used for biometric-protected entries.
  static const biometricKeyTag = 'mfa_demo_bio_key';

  AppConstants._();
}
